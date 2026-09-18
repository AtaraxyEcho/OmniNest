# OmniNest 图像分析侧车（Image Analysis Sidecar）

> 目录名与代码 ID 仍为 `ai-sidecar`；产品文案统一使用「图像分析 / Image Analysis」，不使用「照片 AI」。

图片分析侧车仅提供照片人脸识别能力：人脸检测、512 维人脸嵌入和基于嵌入的聚类。镜像使用 InsightFace `buffalo_l` 与 CPU 版 ONNX Runtime，不再安装 PyTorch、torchvision、Places365 或 COCO 主体检测模型。

## API

除健康检查外，接口都要求 `X-OmniNest-Sidecar-Token` 请求头。

| 接口 | 说明 |
| --- | --- |
| `POST /detect-faces` | 检测人脸并返回边界框与 512 维嵌入 |
| `POST /cluster-faces` | 对人脸嵌入聚类并返回逐向量聚类 ID |
| `POST /analyze-content` | 保留后端结构化分析契约，当前返回空 `observations` |
| `POST /classify-scene` | 保留旧客户端契约，当前返回空 `labels` |
| `GET /health` | 返回进程状态和各能力状态 |
| `GET /ready` | 仅在检测与识别模型均加载完成后返回 HTTP 200 |

上传图片会校验字节数、宽高、像素总数和实际编码。模型缺失或加载不完整时，人脸接口返回 HTTP 503，避免把只有检测模型的进程误报为可用。

## 部署

镜像构建、开发/生产 Compose、模型缓存、环境变量和首次启动检查见 [DEPLOYMENT.md](DEPLOYMENT.md)。生产环境的网关、HTTPS 与完整服务编排见 [`deploy/README.md`](../README.md)。

## 模型许可

InsightFace 代码与预训练模型分别受上游项目及模型许可约束。部署前请根据实际用途核对 InsightFace、ONNX Runtime、OpenCV、NumPy、scikit-learn 等依赖的许可证和再分发条件。
