# OmniNest 图像分析侧车（Image Analysis Sidecar）

> 目录名与服务名为 `vision-sidecar`；Java 类名、`OMNINEST_AI_SIDECAR_SECRET` 与 `photo.ai.*` 配置键保持既有命名，避免破坏已部署配置。产品文案统一使用「图像分析 / Image Analysis」，不使用「照片 AI」。

侧车提供照片的图片内嵌文字识别（OCR）与受控视觉标签：

- `RapidOCR (PP-OCRv4 Mobile ONNX)` 常驻，提取截图、发票、身份证、文档文字，并按版面密度判定 `STYLE:screenshot` / `STYLE:document`。
- `lightweight` 默认视觉档：`MobileCLIP2-S0 Vision FP32 ONNX` + 41 类受控词表文本嵌入，输出 `SUBJECT` / `SCENE` / `STYLE` 观察项。
- `ram_plus_int8` 增强档：`RAM++ Swin-B INT8 ONNX`，额外输出开放集 `semanticTags`；按需懒加载、空闲 180 秒卸载。

镜像只依赖 `onnxruntime`、`opencv-python`、`numpy`、`Pillow` 与 `rapidocr-onnxruntime`，不安装 PyTorch、Ultralytics 或 OpenCLIP 运行时。

## API

除健康检查外，接口都要求 `X-OmniNest-Sidecar-Token` 请求头。

| 接口 | 说明 |
| --- | --- |
| `POST /analyze-content?hint=AUTO\|TEXT_GRAPHIC\|NATURAL_PHOTO&skipOcr=false` | 返回 `schemaVersion`、`pipelineVersion`、`ocrPipelineVersion`、`observations`、`semanticTags` 与 `ocrText` |
| `GET /health` | 返回进程状态、当前视觉档位与流水线版本 |
| `GET /ready` | 返回同样的状态；侧车进程可服务即返回 HTTP 200 |

上传图片会校验字节数、宽高、像素总数和实际编码。OCR 为常驻能力；轻量视觉模型文件缺失时 OCR 仍可用，`/ready` 会返回 `visionModelState=missing`，且流水线版本带 `-missing` 后缀。补齐模型并重启后版本变为 `-ready`，后端会据此重新分析。

## 模型资产

RapidOCR 的 PP-OCRv4 模型随 `rapidocr-onnxruntime` 安装包提供。轻量视觉档需要两个离线资产，放在 `/app/models`（Compose 命名卷 `omninest-ai-models`）：

- `mobileclip2_s0_vision_fp32.onnx`
- `policy_text_embeds.npz`

构建机上执行一次导出脚本（需要 torch / open_clip_torch / onnx；脚本按
`MobileCLIP2-S0 + dfndr2b` 权重导出，第二个参数是输出目录）：

```bash
pip install torch open_clip_torch==3.3.0 onnx onnxruntime
python deploy/vision-sidecar/scripts/export_lightweight_assets.py deploy/vision-sidecar/models
```

`ram_plus_int8` 档还需要 `ram_plus_swin_base_int8.onnx`（约 873MB）与 `ram_tag_list_zh_en.txt`。容器内存限额低于 2GB 时侧车会自动降级到 `lightweight`，避免 OOM。

## 部署

镜像构建、开发/生产 Compose、模型缓存、环境变量和首次启动检查见 [DEPLOYMENT.md](DEPLOYMENT.md)。生产环境的网关、HTTPS 与完整服务编排见 [`deploy/README.md`](../README.md)。

## 模型许可

RapidOCR / PaddleOCR、MobileCLIP、RAM++、ONNX Runtime、OpenCV、NumPy 与 Pillow 分别受各自上游许可约束。部署前请根据实际用途核对许可证和再分发条件。
