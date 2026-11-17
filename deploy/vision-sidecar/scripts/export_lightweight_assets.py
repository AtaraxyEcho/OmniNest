"""
离线导出轻量视觉档位资产（仅在构建模型资产时运行一次）。

侧车生产容器不安装 torch / open_clip_torch。请在具备以下依赖的构建机上执行：

    pip install torch open_clip_torch==3.3.0 onnx onnxruntime onnxscript

产物：
- mobileclip2_s0_vision_fp32.onnx  (~44 MB)
- policy_text_embeds.npz           (~76 KB)

视觉塔按 FP32 导出：`quantize_dynamic` 会连 FastViT 的深度可分离卷积一起量化，
实测 INT8 产物与 torch 前向的余弦只有 -0.07（等于换了一个随机编码器），
只查 `onnx.checker` 与文件大小都发现不了，因此导出脚本改用前向一致性闸门并保留 FP32。

将两个文件放入 deploy/vision-sidecar/models/ 或挂载卷 omninest-ai-models 的 /app/models。

轻量档取 open_clip 3.3.0 中同为 S0 量级的 MobileCLIP2-S0（dfndr2b 权重）：
open_clip 各版本都未发布 MobileCLIP-S0 模型配置，可选的最小档位只有 MobileCLIP2-S0。

STYLE:screenshot 与 STYLE:document 由 RapidOCR 版面密度权威判定，
不包含在自然图像零样本词表中。
"""

import os
import sys

import numpy as np
import onnx
import onnxruntime as ort
import open_clip
import torch
from PIL import Image

VISION_MODEL = "MobileCLIP2-S0"
VISION_PRETRAINED = "dfndr2b"

# 与后端 PhotoLabelPolicy.java 严格对齐的 41 个受控视觉标签及英文 Prompt。
POLICY_PROMPTS = [
    ("SUBJECT", "person", "a photo of a person, man, woman, or child"),
    ("SUBJECT", "cat", "a photo of a cat or kitten"),
    ("SUBJECT", "dog", "a photo of a dog or puppy"),
    ("SUBJECT", "bird", "a photo of a bird"),
    ("SUBJECT", "horse", "a photo of a horse"),
    ("SUBJECT", "sheep", "a photo of a sheep"),
    ("SUBJECT", "cow", "a photo of a cow or cattle"),
    ("SUBJECT", "elephant", "a photo of an elephant"),
    ("SUBJECT", "bear", "a photo of a bear"),
    ("SUBJECT", "zebra", "a photo of a zebra"),
    ("SUBJECT", "giraffe", "a photo of a giraffe"),
    ("SUBJECT", "vehicle", "a photo of a car, bus, train, motorcycle, bicycle, or vehicle"),
    ("SUBJECT", "food", "a photo of food, dish, meal, dessert, or fruit"),
    ("SUBJECT", "plant", "a photo of a plant, flower, or tree"),
    ("SUBJECT", "book", "a photo of a book or bookshelf"),
    ("SCENE", "indoor", "an indoor photo inside a building or room"),
    ("SCENE", "outdoor", "an outdoor photo"),
    ("SCENE", "nature", "a natural landscape photo of nature"),
    ("SCENE", "urban", "an urban scene with buildings"),
    ("SCENE", "beach", "a photo of a beach, coast, or seaside"),
    ("SCENE", "mountain", "a photo of mountains or hills"),
    ("SCENE", "forest", "a photo of a forest or woods"),
    ("SCENE", "lake", "a photo of a lake"),
    ("SCENE", "ocean", "a photo of the ocean or sea"),
    ("SCENE", "river", "a photo of a river or stream"),
    ("SCENE", "office", "an indoor photo of an office or desk"),
    ("SCENE", "restaurant", "an indoor photo of a restaurant or cafe"),
    ("SCENE", "kitchen", "an indoor photo of a kitchen"),
    ("SCENE", "bedroom", "an indoor photo of a bedroom"),
    ("SCENE", "classroom", "an indoor photo of a classroom"),
    ("SCENE", "city", "a photo of a city skyline or downtown"),
    ("SCENE", "street", "a photo of a street or road"),
    ("SCENE", "park", "a photo of a park or garden"),
    ("SCENE", "stadium", "a photo of a stadium or sports field"),
    ("SCENE", "night", "a night scene photo taken at night"),
    ("STYLE", "photograph", "a realistic camera photograph"),
    ("STYLE", "illustration", "a digital illustration, drawing, or sketch"),
    ("STYLE", "anime", "an anime, cartoon, or comic picture"),
    ("STYLE", "3d_render", "a 3D computer graphics render"),
    ("STYLE", "artwork", "a painting, sculpture, or traditional artwork"),
]


class VisionEncoderWrapper(torch.nn.Module):
    def __init__(self, clip_model):
        super().__init__()
        self.visual = clip_model.visual

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        feature = self.visual(image)
        return feature / feature.norm(dim=-1, keepdim=True).clamp(min=1e-6)


def _assert_export_fidelity(onnx_path: str, checks) -> None:
    """校验导出的 ONNX 图与导出前取好的 torch 前向一致。

    动态 INT8 量化会把 FastViT 的视觉嵌入完全打散（实测与 torch 前向余弦 -0.07），
    只查 `onnx.checker` 与文件大小都发现不了；用两个互不相关的输入各比一次，
    也顺带排除"图只对 trace 样本成立"的失真。
    """
    session = ort.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    for tag, sample, expected in checks:
        actual = session.run(None, {input_name: sample.numpy()})[0][0].squeeze()
        cosine = float(
            np.dot(expected, actual) / (np.linalg.norm(expected) * np.linalg.norm(actual))
        )
        if cosine < 0.999:
            raise RuntimeError(f"ONNX 视觉塔前向与 torch 偏差过大: sample={tag}, cos={cosine:.4f}")
        print(f"导出保真校验通过: sample={tag}, cos={cosine:.4f}")


def _extract_image_normalization(transform):
    """从 open_clip 预处理链提取归一化参数，供无 torch 的生产侧车复用。"""
    mean = [0.0, 0.0, 0.0]
    std = [1.0, 1.0, 1.0]

    def walk(node):
        yield node
        for child in getattr(node, "transforms", []) or []:
            yield from walk(child)

    for node in walk(transform):
        if type(node).__name__ == "Normalize":
            mean = [float(value) for value in node.mean]
            std = [float(value) for value in node.std]
    return (
        np.asarray(mean, dtype=np.float32).reshape(1, 1, 3),
        np.asarray(std, dtype=np.float32).reshape(1, 1, 3),
    )


def main(output_dir: str = "./models"):
    os.makedirs(output_dir, exist_ok=True)
    model, _, preprocess = open_clip.create_model_and_transforms(
        VISION_MODEL, pretrained=VISION_PRETRAINED
    )
    model.eval()
    tokenizer = open_clip.get_tokenizer(VISION_MODEL)
    image_mean, image_std = _extract_image_normalization(preprocess)
    _, input_height, input_width = preprocess(Image.new("RGB", (640, 480))).shape
    if (input_height, input_width) != (256, 256):
        raise RuntimeError(
            f"视觉模型输入尺寸 {input_height}x{input_width} 与侧车 256 中心裁剪假设不符"
        )
    print(
        "模型预处理: "
        f"input={input_height}x{input_width}, mean={image_mean.ravel().tolist()}, "
        f"std={image_std.ravel().tolist()}"
    )

    prompts = [item[2] for item in POLICY_PROMPTS]
    with torch.no_grad():
        tokens = tokenizer(prompts)
        text_features = model.encode_text(tokens)
        text_features = text_features / text_features.norm(dim=-1, keepdim=True).clamp(min=1e-6)
        embeddings = text_features.cpu().numpy().astype(np.float32)

    npz_path = os.path.join(output_dir, "policy_text_embeds.npz")
    np.savez_compressed(
        npz_path,
        namespaces=np.array([item[0] for item in POLICY_PROMPTS]),
        codes=np.array([item[1] for item in POLICY_PROMPTS]),
        embeddings=embeddings,
        image_mean=image_mean,
        image_std=image_std,
    )
    print(f"Saved text embeddings: {npz_path} ({os.path.getsize(npz_path)} bytes)")

    vision_onnx = os.path.join(output_dir, "mobileclip2_s0_vision_fp32.onnx")
    wrapper = VisionEncoderWrapper(model)
    generator = torch.Generator().manual_seed(0)
    samples = [
        ("gaussian", torch.randn(1, 3, 256, 256, generator=generator)),
        ("uniform", torch.rand(1, 3, 256, 256, generator=generator)),
    ]
    # torch 参考前向必须在导出之前取：torch.onnx.export 会改写模块内部状态，
    # 之后再跑同一个 wrapper 得到的就不是同一个编码器了。
    with torch.no_grad():
        checks = [
            (tag, sample, wrapper(sample).numpy().squeeze()) for tag, sample in samples
        ]
    # dynamo=False 走 legacy TorchScript 导出器：dynamo 导出器对本模型会报
    # ShapeInferenceError（1024 vs 512）。
    torch.onnx.export(
        wrapper,
        samples[0][1],
        vision_onnx,
        input_names=["image"],
        output_names=["image_embedding"],
        opset_version=17,
        dynamo=False,
    )
    onnx.checker.check_model(vision_onnx)
    _assert_export_fidelity(vision_onnx, checks)
    print(
        "Saved vision ONNX: "
        f"{vision_onnx} ({os.path.getsize(vision_onnx) / 1024 / 1024:.2f} MB)"
    )


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "./models")
