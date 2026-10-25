"""
OmniNest 图像识别侧车服务。
提供基于 ONNX Runtime 的 RapidOCR 文字提取与双档位视觉多标签识别。
"""

import asyncio
import ctypes
import gc
import hmac
import io
import logging
import os
import threading
import time
from asyncio import Semaphore, to_thread
from contextlib import asynccontextmanager
from typing import Annotated, Dict, List, Optional, Tuple

import cv2
import numpy as np
import onnxruntime as ort
from fastapi import Depends, FastAPI, File, Header, HTTPException, Query, UploadFile
from PIL import Image
from pydantic import BaseModel, Field
from rapidocr_onnxruntime import RapidOCR

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("omninest-vision-sidecar")

SIDECAR_TOKEN_HEADER = "X-OmniNest-Sidecar-Token"
SIDECAR_SECRET = os.environ.get("OMNINEST_AI_SIDECAR_SECRET", "")
MAX_IMAGE_BYTES = int(os.environ.get("AI_MAX_IMAGE_BYTES", str(64 * 1024 * 1024)))
MAX_IMAGE_WIDTH = int(os.environ.get("AI_MAX_IMAGE_WIDTH", "30000"))
MAX_IMAGE_HEIGHT = int(os.environ.get("AI_MAX_IMAGE_HEIGHT", "30000"))
MAX_IMAGE_PIXELS = int(os.environ.get("AI_MAX_IMAGE_PIXELS", "100000000"))
Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS
# OCR 检测长边本身就是 2048；超过该尺寸再保留原图只会放大解码峰值。
# 先按长边缩放再转 BGR，避免 1 亿像素同时持有 RGB 与 OpenCV 两份全尺寸数组。
DECODE_MAX_SIDE = max(256, int(os.environ.get("AI_DECODE_MAX_SIDE", "2048")))

MAX_CONCURRENT_INFERENCES = max(1, int(os.environ.get("AI_MAX_CONCURRENT_INFERENCES", "1")))
ORT_INTRA_THREADS = max(1, int(os.environ.get("AI_ORT_INTRA_THREADS", "2")))
# GPU 开关：显式启用时才把 CUDA 放在 CPU 前；CUDA 不可用时 ORT 会回落到第二个 provider。
VISION_ENABLE_GPU = os.environ.get("VISION_ENABLE_GPU", "false").strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
}
VISION_EXECUTION_PROVIDERS = (
    ["CUDAExecutionProvider", "CPUExecutionProvider"]
    if VISION_ENABLE_GPU
    else ["CPUExecutionProvider"]
)
UPLOAD_READ_CHUNK_SIZE = 1024 * 1024
MIN_RAM_PLUS_CONTAINER_BYTES = 2 * 1024 * 1024 * 1024


def _read_cgroup_memory_limit() -> Optional[int]:
    """读取容器 cgroup v2/v1 内存上限（字节），无限制或宿主机直跑时返回 None。"""
    for path in ("/sys/fs/cgroup/memory.max", "/sys/fs/cgroup/memory/memory.limit_in_bytes"):
        if os.path.isfile(path):
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    raw = handle.read().strip()
                if raw and raw != "max":
                    value = int(raw)
                    if 0 < value < (1 << 60):
                        return value
            except (OSError, ValueError):
                pass
    return None


def _resolve_safe_vision_profile() -> str:
    requested = os.environ.get("AI_VISION_PROFILE", "lightweight").strip().lower()
    if requested == "ram_plus_int8":
        memory_limit = _read_cgroup_memory_limit()
        if memory_limit is not None and memory_limit < MIN_RAM_PLUS_CONTAINER_BYTES:
            logger.warning(
                "容器内存限制 (%d MB) 低于 RAM++ 最低准入要求 (2048 MB)，已自动降级为 lightweight 档位",
                memory_limit // (1024 * 1024),
            )
            return "lightweight"
    return requested if requested in ("lightweight", "ram_plus_int8") else "lightweight"


VISION_PROFILE = _resolve_safe_vision_profile()
MODEL_DIR = os.environ.get("AI_MODEL_DIR", "/app/models")

LIGHTWEIGHT_VISION_ONNX_PATH = os.environ.get(
    "AI_LIGHTWEIGHT_ONNX_PATH",
    os.path.join(MODEL_DIR, "mobileclip2_s0_vision_fp32.onnx"),
)
LIGHTWEIGHT_TEXT_EMBEDS_PATH = os.environ.get(
    "AI_LIGHTWEIGHT_EMBEDS_PATH",
    os.path.join(MODEL_DIR, "policy_text_embeds.npz"),
)
LIGHTWEIGHT_LOGIT_SCALE = float(os.environ.get("AI_LIGHTWEIGHT_LOGIT_SCALE", "14.28"))
# 实测 MobileCLIP2-S0 与 41 条受控 prompt 的余弦分布：无意义图像的上沿是 0.12-0.16，
# 命中的标签落在 0.23-0.29。0.18 取在两者之间，作为相似度到置信度的映射中点。
LIGHTWEIGHT_SIMILARITY_MIDPOINT = 0.18
LIGHTWEIGHT_SUBJECT_MIN_SIMILARITY = float(
    os.environ.get("AI_LIGHTWEIGHT_SUBJECT_MIN_SIMILARITY", "0.24")
)

RAM_ONNX_PATH = os.environ.get(
    "AI_RAM_ONNX_PATH",
    os.path.join(MODEL_DIR, "ram_plus_swin_base_int8.onnx"),
)
RAM_TAGS_PATH = os.environ.get(
    "AI_RAM_TAGS_PATH",
    os.path.join(MODEL_DIR, "ram_tag_list_zh_en.txt"),
)
RAM_IDLE_TTL_SECONDS = max(30, int(os.environ.get("AI_RAM_IDLE_TTL_SECONDS", "180")))


def _vision_model_state(profile: str) -> str:
    """返回当前视觉档位所需模型文件是否齐全，用于阻止缺模型结果被误判为已完成。"""
    if profile == "ram_plus_int8":
        required_paths = (RAM_ONNX_PATH, RAM_TAGS_PATH)
    else:
        required_paths = (LIGHTWEIGHT_VISION_ONNX_PATH, LIGHTWEIGHT_TEXT_EMBEDS_PATH)
    return "ready" if all(os.path.isfile(path) for path in required_paths) else "missing"


def current_vision_pipeline_version() -> str:
    """模型目录可能在容器启动后才挂载，版本串必须在每次响应时重新计算。"""
    return f"vision-v7-{VISION_PROFILE}-{_vision_model_state(VISION_PROFILE)}"


def current_content_pipeline_version() -> str:
    return f"{current_vision_pipeline_version()}+{OCR_PIPELINE_VERSION}"


OCR_DET_LIMIT_SIDE_LEN = int(os.environ.get("AI_OCR_DET_LIMIT_SIDE_LEN", "2048"))
OCR_MIN_SCORE = float(os.environ.get("AI_OCR_MIN_SCORE", "0.65"))
OCR_SMALL_BOX_MIN_SCORE = float(os.environ.get("AI_OCR_SMALL_BOX_MIN_SCORE", "0.78"))
OCR_NORMAL_BOX_SIDE = float(os.environ.get("AI_OCR_NORMAL_BOX_SIDE", "12.0"))
OCR_MIN_BOX_SIDE = float(os.environ.get("AI_OCR_MIN_BOX_SIDE", "8.0"))
OCR_MAX_BOXES = int(os.environ.get("AI_OCR_MAX_BOXES", "40"))
OCR_MAX_TEXT_CHARS = int(os.environ.get("AI_OCR_MAX_TEXT_CHARS", "4000"))

CONTENT_ANALYSIS_SCHEMA_VERSION = 2
OCR_PIPELINE_VERSION = "ppocr-v4-onnx-v1"

inference_slots = Semaphore(MAX_CONCURRENT_INFERENCES)

_libc_malloc_trim = None
try:
    _libc = ctypes.CDLL("libc.so.6")
    if hasattr(_libc, "malloc_trim"):
        _libc.malloc_trim.argtypes = [ctypes.c_size_t]
        _libc.malloc_trim.restype = ctypes.c_int
        _libc_malloc_trim = _libc.malloc_trim
        logger.info("已启用 glibc malloc_trim(0) 原生堆内存回收支持")
except (OSError, AttributeError) as exception:
    logger.warning("当前运行环境未检测到 glibc libc.so.6 malloc_trim: %s", exception)


def _trim_native_heap() -> None:
    if _libc_malloc_trim is not None:
        try:
            _libc_malloc_trim(0)
        except Exception as exception:
            logger.debug("执行 malloc_trim(0) 失败: %s", exception)


def _build_restricted_session_options() -> ort.SessionOptions:
    """显式关闭 CPU Memory Arena 与 MemPattern，防止 RSS 膨胀。"""
    options = ort.SessionOptions()
    options.intra_op_num_threads = ORT_INTRA_THREADS
    options.inter_op_num_threads = 1
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    options.enable_cpu_mem_arena = False
    options.enable_mem_pattern = False
    return options


# RAM++ 开放集英文原始词归一化为 PhotoLabelPolicy 的受控 (namespace, code)。
# STYLE:screenshot/document 完全由 RapidOCR 版面分析产出，不由自然图像模型触发。
RAW_TAG_TO_POLICY_CODE: Dict[str, Tuple[str, str]] = {
    "person": ("SUBJECT", "person"), "man": ("SUBJECT", "person"), "woman": ("SUBJECT", "person"),
    "child": ("SUBJECT", "person"), "girl": ("SUBJECT", "person"), "boy": ("SUBJECT", "person"),
    "cat": ("SUBJECT", "cat"), "kitten": ("SUBJECT", "cat"),
    "dog": ("SUBJECT", "dog"), "puppy": ("SUBJECT", "dog"),
    "bird": ("SUBJECT", "bird"), "horse": ("SUBJECT", "horse"), "sheep": ("SUBJECT", "sheep"),
    "cow": ("SUBJECT", "cow"), "elephant": ("SUBJECT", "elephant"), "bear": ("SUBJECT", "bear"),
    "zebra": ("SUBJECT", "zebra"), "giraffe": ("SUBJECT", "giraffe"),
    "car": ("SUBJECT", "vehicle"), "bus": ("SUBJECT", "vehicle"), "train": ("SUBJECT", "vehicle"),
    "bicycle": ("SUBJECT", "vehicle"), "motorcycle": ("SUBJECT", "vehicle"),
    "vehicle": ("SUBJECT", "vehicle"),
    "food": ("SUBJECT", "food"), "dish": ("SUBJECT", "food"), "dessert": ("SUBJECT", "food"),
    "fruit": ("SUBJECT", "food"),
    "plant": ("SUBJECT", "plant"), "flower": ("SUBJECT", "plant"), "tree": ("SUBJECT", "plant"),
    "book": ("SUBJECT", "book"),
    "indoor": ("SCENE", "indoor"), "outdoor": ("SCENE", "outdoor"), "nature": ("SCENE", "nature"),
    "urban": ("SCENE", "urban"), "beach": ("SCENE", "beach"), "mountain": ("SCENE", "mountain"),
    "forest": ("SCENE", "forest"), "lake": ("SCENE", "lake"), "ocean": ("SCENE", "ocean"),
    "river": ("SCENE", "river"), "office": ("SCENE", "office"), "restaurant": ("SCENE", "restaurant"),
    "kitchen": ("SCENE", "kitchen"), "bedroom": ("SCENE", "bedroom"),
    "classroom": ("SCENE", "classroom"), "city": ("SCENE", "city"), "street": ("SCENE", "street"),
    "park": ("SCENE", "park"), "stadium": ("SCENE", "stadium"), "night": ("SCENE", "night"),
    "photograph": ("STYLE", "photograph"), "illustration": ("STYLE", "illustration"),
    "drawing": ("STYLE", "illustration"), "sketch": ("STYLE", "illustration"),
    "anime": ("STYLE", "anime"), "cartoon": ("STYLE", "anime"), "comic": ("STYLE", "anime"),
    "3d_render": ("STYLE", "3d_render"), "artwork": ("STYLE", "artwork"),
    "painting": ("STYLE", "artwork"),
}


class ModelLifecycleManager:
    """管理 RapidOCR、轻量常驻视觉模型与 RAM++ 按需懒加载/空闲卸载。"""

    DEFAULT_IMAGE_MEAN = np.zeros((1, 1, 3), dtype=np.float32)
    DEFAULT_IMAGE_STD = np.ones((1, 1, 3), dtype=np.float32)

    def __init__(self) -> None:
        self._lock = threading.Lock()
        # RapidOCR 单例内部状态不是线程安全的；即使把并发档位调高，也不能并发调用。
        self._ocr_inference_lock = threading.Lock()
        self._ocr: Optional[RapidOCR] = None
        self._lw_session: Optional[ort.InferenceSession] = None
        self._lw_labels: List[Tuple[str, str]] = []
        self._lw_text_embeds: Optional[np.ndarray] = None
        self._lw_image_mean = self.DEFAULT_IMAGE_MEAN.copy()
        self._lw_image_std = self.DEFAULT_IMAGE_STD.copy()
        self._ram_session: Optional[ort.InferenceSession] = None
        self._ram_tags: List[Tuple[str, str]] = []
        self._ram_last_used: float = 0.0
        self._lw_missing_logged = False
        self._ram_missing_logged = False

    def get_ocr(self) -> RapidOCR:
        if self._ocr is None:
            with self._lock:
                if self._ocr is None:
                    logger.info(
                        "初始化 RapidOCR (PP-OCRv4 ONNX, det_limit_side_len=%s)",
                        OCR_DET_LIMIT_SIDE_LEN,
                    )
                    self._ocr = RapidOCR(
                        det_use_cuda=VISION_ENABLE_GPU,
                        cls_use_cuda=VISION_ENABLE_GPU,
                        rec_use_cuda=VISION_ENABLE_GPU,
                        det_limit_side_len=OCR_DET_LIMIT_SIDE_LEN,
                        det_limit_type="max",
                        intra_op_num_threads=ORT_INTRA_THREADS,
                    )
        return self._ocr

    def run_ocr(self, bgr: np.ndarray):
        """串行执行 RapidOCR 推理，避免多线程共享单例内部状态。"""
        with self._ocr_inference_lock:
            return self.get_ocr()(bgr)

    def acquire_lightweight_vision(
        self,
    ) -> Tuple[
        Optional[ort.InferenceSession],
        List[Tuple[str, str]],
        Optional[np.ndarray],
        np.ndarray,
        np.ndarray,
    ]:
        if not os.path.isfile(LIGHTWEIGHT_VISION_ONNX_PATH) or not os.path.isfile(
            LIGHTWEIGHT_TEXT_EMBEDS_PATH
        ):
            if not self._lw_missing_logged:
                self._lw_missing_logged = True
                logger.warning(
                    "Lightweight 视觉模型或嵌入文件缺失，视觉标签暂不可用: onnx=%s, embeds=%s",
                    LIGHTWEIGHT_VISION_ONNX_PATH,
                    LIGHTWEIGHT_TEXT_EMBEDS_PATH,
                )
            return None, [], None, self.DEFAULT_IMAGE_MEAN.copy(), self.DEFAULT_IMAGE_STD.copy()
        if self._lw_session is None:
            with self._lock:
                if self._lw_session is None:
                    started_at = time.monotonic()
                    options = _build_restricted_session_options()
                    self._lw_session = ort.InferenceSession(
                        LIGHTWEIGHT_VISION_ONNX_PATH,
                        sess_options=options,
                        providers=VISION_EXECUTION_PROVIDERS,
                    )
                    with np.load(LIGHTWEIGHT_TEXT_EMBEDS_PATH, allow_pickle=False) as data:
                        namespaces = [str(value) for value in data["namespaces"]]
                        codes = [str(value) for value in data["codes"]]
                        embeddings = np.asarray(data["embeddings"], dtype=np.float32)
                        norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
                        self._lw_text_embeds = embeddings / np.clip(norms, 1e-6, None)
                        self._lw_labels = list(zip(namespaces, codes))
                        mean = data["image_mean"] if "image_mean" in data else self.DEFAULT_IMAGE_MEAN
                        std = data["image_std"] if "image_std" in data else self.DEFAULT_IMAGE_STD
                        self._lw_image_mean = np.asarray(mean, dtype=np.float32).reshape(1, 1, 3)
                        self._lw_image_std = np.asarray(std, dtype=np.float32).reshape(1, 1, 3)
                    logger.info(
                        "Lightweight 视觉模型加载完成: labels=%d, 耗时 %.2fs",
                        len(self._lw_labels),
                        time.monotonic() - started_at,
                    )
        return (
            self._lw_session,
            self._lw_labels,
            self._lw_text_embeds,
            self._lw_image_mean.copy(),
            self._lw_image_std.copy(),
        )

    def acquire_ram_session(self) -> Tuple[Optional[ort.InferenceSession], List[Tuple[str, str]]]:
        if VISION_PROFILE != "ram_plus_int8" or not os.path.isfile(RAM_ONNX_PATH):
            if VISION_PROFILE == "ram_plus_int8" and not self._ram_missing_logged:
                self._ram_missing_logged = True
                logger.warning("RAM++ 模型文件缺失，视觉标签暂不可用: %s", RAM_ONNX_PATH)
            return None, []
        with self._lock:
            self._ram_last_used = time.monotonic()
            if self._ram_session is None:
                started_at = time.monotonic()
                logger.info("按需懒加载 RAM++ INT8 ONNX 模型: %s", RAM_ONNX_PATH)
                options = _build_restricted_session_options()
                self._ram_session = ort.InferenceSession(
                    RAM_ONNX_PATH,
                    sess_options=options,
                    providers=VISION_EXECUTION_PROVIDERS,
                )
                if not self._ram_tags and os.path.isfile(RAM_TAGS_PATH):
                    with open(RAM_TAGS_PATH, "r", encoding="utf-8") as handle:
                        self._ram_tags = [
                            tuple(line.strip().split("\t")[:2])
                            if "\t" in line
                            else (line.strip(), line.strip())
                            for line in handle
                            if line.strip()
                        ]
                logger.info("RAM++ ONNX 加载完成，耗时 %.2fs", time.monotonic() - started_at)
            return self._ram_session, self._ram_tags

    def evict_idle_models(self) -> None:
        with self._lock:
            if self._ram_session is not None and (
                time.monotonic() - self._ram_last_used
            ) >= RAM_IDLE_TTL_SECONDS:
                logger.info(
                    "RAM++ 空闲超过 %ss，卸载 Session 并执行 malloc_trim(0)",
                    RAM_IDLE_TTL_SECONDS,
                )
                self._ram_session = None
                gc.collect()
                _trim_native_heap()

    def shutdown(self) -> None:
        with self._lock:
            self._ram_session = None
            self._lw_session = None
            self._lw_text_embeds = None
            self._lw_image_mean = self.DEFAULT_IMAGE_MEAN.copy()
            self._lw_image_std = self.DEFAULT_IMAGE_STD.copy()
            self._ocr = None
            gc.collect()
            _trim_native_heap()


model_manager = ModelLifecycleManager()


class BoundingBox(BaseModel):
    x: float
    y: float
    width: float
    height: float


class ContentObservation(BaseModel):
    namespace: str
    code: str
    confidence: float
    source: str
    boxes: list[BoundingBox] = Field(default_factory=list)


class ContentAnalysis(BaseModel):
    schema_version: int = Field(alias="schemaVersion")
    pipeline_version: str = Field(alias="pipelineVersion")
    ocr_pipeline_version: str = Field(default=OCR_PIPELINE_VERSION, alias="ocrPipelineVersion")
    observations: list[ContentObservation]
    semantic_tags: list[str] = Field(default_factory=list, alias="semanticTags")
    ocr_text: Optional[str] = Field(default=None, alias="ocrText")

    model_config = {"populate_by_name": True}


def _require_sidecar_token(
    token: Annotated[str | None, Header(alias=SIDECAR_TOKEN_HEADER)] = None,
) -> None:
    if not SIDECAR_SECRET:
        raise HTTPException(status_code=503, detail="AI sidecar authentication is not configured")
    if token is None or not hmac.compare_digest(token, SIDECAR_SECRET):
        raise HTTPException(status_code=401, detail="Unauthorized")


async def _read_image_bytes(image: UploadFile) -> bytes:
    chunks = bytearray()
    while True:
        chunk = await image.read(UPLOAD_READ_CHUNK_SIZE)
        if not chunk:
            break
        if len(chunks) + len(chunk) > MAX_IMAGE_BYTES:
            raise HTTPException(status_code=413, detail="Image exceeds size limit")
        chunks.extend(chunk)
    if not chunks:
        raise HTTPException(status_code=400, detail="Image is empty")
    return bytes(chunks)


def _decode_single_pass_bgr(raw_bytes: bytes) -> np.ndarray:
    try:
        with Image.open(io.BytesIO(raw_bytes)) as decoded:
            width, height = decoded.size
            if (
                width <= 0
                or height <= 0
                or width > MAX_IMAGE_WIDTH
                or height > MAX_IMAGE_HEIGHT
                or width * height > MAX_IMAGE_PIXELS
            ):
                raise HTTPException(status_code=413, detail="Image dimensions exceed limit")
            # JPEG 可先按目标尺寸解码；其余格式由 thumbnail 在解码后缩小。
            # 两者都不放大，小图保持原尺寸，避免无谓插值。
            decoded.draft("RGB", (DECODE_MAX_SIDE, DECODE_MAX_SIDE))
            if decoded.width > DECODE_MAX_SIDE or decoded.height > DECODE_MAX_SIDE:
                decoded.thumbnail(
                    (DECODE_MAX_SIDE, DECODE_MAX_SIDE),
                    Image.Resampling.LANCZOS,
                )
            rgb = decoded.convert("RGB")
            return cv2.cvtColor(np.asarray(rgb), cv2.COLOR_RGB2BGR)
    except HTTPException:
        raise
    except Image.DecompressionBombError as exception:
        raise HTTPException(status_code=413, detail="Image exceeds maximum pixel limit") from exception
    except Exception as exception:
        raise HTTPException(status_code=400, detail="Unable to decode image") from exception


def _run_gated_ocr(bgr: np.ndarray) -> Tuple[Optional[str], int, float]:
    """
    执行 RapidOCR 并按框高分档过滤：
    短边 < 8px 丢弃；8~12px 要求 score >= 0.78；>= 12px 要求 score >= 0.65。
    """
    height, width = bgr.shape[:2]
    ocr_result, _ = model_manager.run_ocr(bgr)
    if not ocr_result:
        return None, 0, 0.0

    valid_items = []
    total_text_area = 0.0
    for box, text, score in ocr_result:
        if not text or not text.strip():
            continue
        points = np.asarray(box, dtype=np.float32)
        box_width = float(np.linalg.norm(points[1] - points[0]))
        box_height = float(np.linalg.norm(points[3] - points[0]))
        min_side = min(box_width, box_height)
        if min_side < OCR_MIN_BOX_SIDE:
            continue
        effective_min_score = OCR_MIN_SCORE if min_side >= OCR_NORMAL_BOX_SIDE else OCR_SMALL_BOX_MIN_SCORE
        if float(score) < effective_min_score:
            continue
        total_text_area += box_width * box_height
        valid_items.append((float(points[0][1]), float(points[0][0]), text.strip()))

    if not valid_items:
        return None, 0, 0.0

    valid_items.sort(key=lambda item: (round(item[0] / 12.0), item[1]))
    lines = [item[2] for item in valid_items[:OCR_MAX_BOXES]]
    joined = "\n".join(lines)[:OCR_MAX_TEXT_CHARS]
    area_ratio = total_text_area / float(max(1, width * height))
    return joined, len(lines), area_ratio


def _preprocess_mobileclip_256(
    bgr: np.ndarray,
    image_mean: np.ndarray,
    image_std: np.ndarray,
) -> np.ndarray:
    """保持宽高比将短边缩放至 256，再执行 256x256 中心裁剪。"""
    height, width = bgr.shape[:2]
    scale = 256.0 / float(min(height, width))
    new_width = max(256, int(round(width * scale)))
    new_height = max(256, int(round(height * scale)))
    # 导出的 open_clip 预处理链用 antialias 双线性缩小；cv2 的 INTER_AREA 是等价降采样，
    # INTER_LINEAR 只在放大时使用。
    interpolation = cv2.INTER_AREA if scale < 1.0 else cv2.INTER_LINEAR
    resized = cv2.resize(bgr, (new_width, new_height), interpolation=interpolation)
    top = (new_height - 256) // 2
    left = (new_width - 256) // 2
    cropped = resized[top : top + 256, left : left + 256]
    rgb = cv2.cvtColor(cropped, cv2.COLOR_BGR2RGB)
    normalized = (rgb.astype(np.float32) / 255.0 - image_mean) / image_std
    return np.transpose(normalized, (2, 0, 1))[np.newaxis, ...]


def _lightweight_confidence(similarity: float) -> float:
    """把绝对余弦相似度映射为置信度。

    命名空间内部的 softmax 只保留相对名次：实测正确标签（lake 0.232、mountain 0.291）
    的概率只有 0.18-0.30，后端 0.55/0.70 的门永远够不到，而无关图像也会推出一个
    "相对最优"的错标签，因此三个命名空间统一按绝对相似度打分。
    """
    return float(
        1.0 / (1.0 + np.exp(-(similarity - LIGHTWEIGHT_SIMILARITY_MIDPOINT) * LIGHTWEIGHT_LOGIT_SCALE))
    )


def _run_lightweight_visual_inference(
    bgr: np.ndarray,
    policy_scores: Dict[Tuple[str, str], Tuple[float, str]],
) -> None:
    session, labels, text_embeds, image_mean, image_std = model_manager.acquire_lightweight_vision()
    if session is None or text_embeds is None or not labels:
        return

    input_tensor = _preprocess_mobileclip_256(bgr, image_mean, image_std)
    input_name = session.get_inputs()[0].name
    image_feature = session.run(None, {input_name: input_tensor})[0][0]
    image_norm = float(np.linalg.norm(image_feature))
    if image_norm <= 1e-6 or not np.isfinite(image_norm):
        return
    image_feature = image_feature / image_norm

    similarities = np.dot(text_embeds, image_feature)
    namespace_indices: Dict[str, List[int]] = {"SUBJECT": [], "SCENE": [], "STYLE": []}
    for index, (namespace, _) in enumerate(labels):
        if namespace in namespace_indices:
            namespace_indices[namespace].append(index)

    for index in namespace_indices["SUBJECT"]:
        similarity = float(similarities[index])
        if similarity >= LIGHTWEIGHT_SUBJECT_MIN_SIMILARITY:
            confidence = _lightweight_confidence(similarity)
            key = labels[index]
            if confidence > policy_scores.get(key, (0.0, ""))[0]:
                policy_scores[key] = (confidence, "mobileclip2-s0-onnx")

    for namespace in ("SCENE", "STYLE"):
        indices = namespace_indices[namespace]
        if not indices:
            continue
        best_index = max(indices, key=lambda position: similarities[position])
        confidence = _lightweight_confidence(float(similarities[best_index]))
        key = labels[best_index]
        if confidence > policy_scores.get(key, (0.0, ""))[0]:
            policy_scores[key] = (confidence, "mobileclip2-s0-onnx")


def _run_ram_plus_inference(
    bgr: np.ndarray,
    policy_scores: Dict[Tuple[str, str], Tuple[float, str]],
    semantic_tags: List[str],
) -> None:
    """RAM++ 官方预处理为 384x384 直接拉伸，保持官方规范。"""
    session, tags = model_manager.acquire_ram_session()
    if session is None or not tags:
        return
    resized = cv2.resize(
        cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB),
        (384, 384),
        interpolation=cv2.INTER_CUBIC,
    )
    normalized = resized.astype(np.float32) / 255.0
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    input_tensor = np.transpose((normalized - mean) / std, (2, 0, 1))[np.newaxis, ...]

    input_name = session.get_inputs()[0].name
    logits = session.run(None, {input_name: input_tensor})[0][0]
    probabilities = 1.0 / (1.0 + np.exp(-logits))
    top_indices = np.where(probabilities >= 0.68)[0]
    ranked_indices = top_indices[np.argsort(-probabilities[top_indices])][:15]

    for index in ranked_indices:
        if index >= len(tags):
            continue
        en_tag, zh_tag = tags[index]
        confidence = float(probabilities[index])
        semantic_tag = zh_tag or en_tag
        if semantic_tag and semantic_tag not in semantic_tags and len(semantic_tags) < 10:
            semantic_tags.append(semantic_tag)
        mapped = RAW_TAG_TO_POLICY_CODE.get(en_tag.lower().strip())
        if mapped is not None and confidence > policy_scores.get(mapped, (0.0, ""))[0]:
            policy_scores[mapped] = (confidence, "ram-plus-onnx")


def _analyze_content_sync(contents: bytes, hint: str, skip_ocr: bool) -> ContentAnalysis:
    bgr = _decode_single_pass_bgr(contents)
    height, width = bgr.shape[:2]
    aspect = max(width, height) / float(max(1, min(width, height)))

    policy_scores: Dict[Tuple[str, str], Tuple[float, str]] = {}
    semantic_tags: List[str] = []
    ocr_text: Optional[str] = None
    is_dense_text = False

    if not skip_ocr:
        ocr_text, line_count, text_area_ratio = _run_gated_ocr(bgr)
        if line_count >= 4 and hint == "TEXT_GRAPHIC" and 1.7 <= aspect <= 2.4:
            policy_scores[("STYLE", "screenshot")] = (
                min(0.96, 0.72 + text_area_ratio * 2.0),
                "rapidocr-layout",
            )
            is_dense_text = True
        elif line_count >= 6 or text_area_ratio >= 0.08:
            style_code = (
                "screenshot"
                if (hint == "TEXT_GRAPHIC" and 1.7 <= aspect <= 2.4)
                else "document"
            )
            policy_scores[("STYLE", style_code)] = (
                min(0.97, 0.74 + text_area_ratio * 2.0),
                "rapidocr-layout",
            )
            is_dense_text = True

    if not is_dense_text:
        if VISION_PROFILE == "ram_plus_int8":
            _run_ram_plus_inference(bgr, policy_scores, semantic_tags)
        else:
            _run_lightweight_visual_inference(bgr, policy_scores)

    observations = [
        ContentObservation(
            namespace=namespace,
            code=code,
            confidence=round(confidence, 4),
            source=source,
            boxes=[],
        )
        for (namespace, code), (confidence, source) in sorted(
            policy_scores.items(), key=lambda item: -item[1][0]
        )
    ]

    return ContentAnalysis(
        schemaVersion=CONTENT_ANALYSIS_SCHEMA_VERSION,
        pipelineVersion=current_content_pipeline_version(),
        ocrPipelineVersion=OCR_PIPELINE_VERSION,
        observations=observations,
        semanticTags=semantic_tags,
        ocrText=ocr_text,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    stop_event = asyncio.Event()

    async def _eviction_loop():
        while not stop_event.is_set():
            await asyncio.sleep(30)
            await to_thread(model_manager.evict_idle_models)

    eviction_task = asyncio.create_task(_eviction_loop())
    logger.info(
        "OmniNest Vision Sidecar V6 已启动 (profile=%s, visionModel=%s)",
        VISION_PROFILE,
        _vision_model_state(VISION_PROFILE),
    )
    yield
    stop_event.set()
    eviction_task.cancel()
    model_manager.shutdown()


app = FastAPI(title="OmniNest Image Analysis Sidecar", version="6.0.0", lifespan=lifespan)


@app.get("/health")
@app.get("/ready")
async def ready():
    return {
        "status": "ok",
        "visionProfile": VISION_PROFILE,
        "visionModelState": _vision_model_state(VISION_PROFILE),
        "pipelineVersion": current_content_pipeline_version(),
        "ocrVersion": OCR_PIPELINE_VERSION,
    }


@app.post(
    "/analyze-content",
    response_model=ContentAnalysis,
    dependencies=[Depends(_require_sidecar_token)],
)
async def analyze_content(
    image: UploadFile = File(...),
    hint: str = Query(default="AUTO", description="AUTO | TEXT_GRAPHIC | NATURAL_PHOTO"),
    skip_ocr: bool = Query(default=False, alias="skipOcr", description="OCR 版本未变时跳过重复识别"),
):
    # 请求体读取也必须在推理并发槽内：否则排队请求会各自把最多 64MB 原图
    # 读进内存，绕过槽位限制形成内存峰值。
    async with inference_slots:
        contents = await _read_image_bytes(image)
        return await to_thread(_analyze_content_sync, contents, hint.upper(), skip_ocr)
