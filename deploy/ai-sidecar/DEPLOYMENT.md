# 图像分析侧车（Image Analysis Sidecar）部署说明

本文档覆盖图片识别侧车的镜像构建、Compose 启动、模型缓存和运行参数。接口契约与能力边界见 [README.md](README.md)。

## 镜像构建

在仓库根目录执行：

```bash
docker build -f deploy/ai-sidecar/Dockerfile -t omninest-ai-sidecar:face-only deploy/ai-sidecar
```

开发和生产 Compose 使用同一份 `deploy/ai-sidecar/Dockerfile` 与 `requirements.txt`。镜像包含 Python 运行时、InsightFace 人脸检测/识别模型适配、CPU ONNX Runtime、OpenCV、Pillow 和 DBSCAN 依赖，不包含 PyTorch、torchvision、Places365 或 COCO 模型。

依赖中只保留一个 OpenCV 发行包 `opencv-python`，避免同时安装 `opencv-python` 与 `opencv-python-headless` 导致文件覆盖和版本不确定。构建后可检查依赖一致性：

```bash
docker run --rm --entrypoint python omninest-ai-sidecar:face-only -m pip check
```

## Compose 启动

开发环境：

```bash
cd deploy/dev
cp .env.example .env
docker compose up -d ai-sidecar
```

生产环境：

```bash
cd deploy/prod
cp .env.example .env
docker compose build ai-sidecar
docker compose up -d ai-sidecar
```

生产环境必须在 `.env` 中设置随机的 `OMNINEST_AI_SIDECAR_SECRET`，并让后端使用相同值。完整的 PostgreSQL、RabbitMQ、MinIO、网关和 HTTPS 配置见 [`deploy/README.md`](../README.md)。

## 模型缓存与就绪检查

Compose 将命名卷 `omninest-ai-models` 挂载到 `/app/models`。首次启动时，InsightFace 将 `buffalo_l` 的检测和识别模型下载到 `/app/models/insightface`；后续重建容器会复用该卷，删除卷会触发重新下载。

容器的 Docker `HEALTHCHECK` 和 Worker 都请求 `/ready`。只有 detection 与 recognition 两个模型都存在并完成初始化时才返回 HTTP 200；下载或加载期间返回 HTTP 503。首次启动应预留最多 10 分钟的健康检查启动窗口，并在日志中确认模型加载完成：

```bash
docker compose logs -f ai-sidecar
curl http://127.0.0.1:8090/ready
```

侧车端口默认只绑定到宿主机回环地址（开发 Compose 为 `127.0.0.1:8090`）；生产 Compose 通过内部网络由后端访问，不应直接暴露到公网。

## 环境变量

| 变量 | 默认值 | 作用 |
| --- | --- | --- |
| `OMNINEST_AI_SIDECAR_SECRET` | 空 | 受保护接口共享密钥；生产环境必须显式设置 |
| `INSIGHTFACE_ROOT` | `/app/models/insightface` | InsightFace 模型目录 |
| `AI_MAX_IMAGE_BYTES` | `33554432` | 单张图片最大字节数 |
| `AI_MAX_IMAGE_WIDTH` | `30000` | 图片最大宽度 |
| `AI_MAX_IMAGE_HEIGHT` | `30000` | 图片最大高度 |
| `AI_MAX_IMAGE_PIXELS` | `100000000` | 图片最大像素数 |
| `AI_MAX_CLUSTER_FACES` | `10000` | 单次聚类允许的人脸向量数 |
| `AI_FACE_EMBEDDING_DIMENSION` | `512` | 人脸嵌入维度校验值 |
| `AI_MAX_CONCURRENT_INFERENCES` | `2` | 并发推理槽位数 |
| `OMP_NUM_THREADS` | `2`（Compose） | ONNX Runtime CPU 线程数 |
| `IMAGE_ANALYSIS_PIPELINE_VERSION` | `face-recognition-v1` | 结构化兼容响应中的流水线版本 |

大图限制应与后端 `OMNINEST_PHOTO_AI_MAX_IMAGE_BYTES` 保持一致或更严格。调整限制后需重新创建容器使环境变量生效。
