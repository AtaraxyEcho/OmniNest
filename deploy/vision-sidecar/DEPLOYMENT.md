# 图像分析侧车（Image Analysis Sidecar）部署说明

本文档覆盖图片识别侧车的镜像构建、Compose 启动、模型缓存和运行参数。接口契约与能力边界见 [README.md](README.md)。

## 镜像构建

在仓库根目录执行：

```bash
docker build -f deploy/vision-sidecar/Dockerfile -t omninest-vision-sidecar:v6 deploy/vision-sidecar
```

开发和生产 Compose 使用同一份 `deploy/vision-sidecar/Dockerfile` 与 `requirements.txt`。镜像包含 Python 运行时、RapidOCR、CPU ONNX Runtime、OpenCV 与 Pillow，不包含 PyTorch、torchvision、Ultralytics、Places365 或 COCO 模型。

依赖中只保留一个 OpenCV 发行包 `opencv-python`，避免同时安装 `opencv-python` 与 `opencv-python-headless` 导致文件覆盖和版本不确定。镜像构建会执行 `pip check`：

```bash
docker run --rm --entrypoint python omninest-vision-sidecar:v6 -m pip check
```

## Compose 启动

开发环境：

```bash
cd deploy/dev
cp .env.example .env
docker compose up -d vision-sidecar
```

生产环境：

```bash
cd deploy/prod
cp .env.example .env
docker compose build vision-sidecar
docker compose up -d vision-sidecar
```

生产环境必须在 `.env` 中设置随机的 `OMNINEST_AI_SIDECAR_SECRET`，并让后端使用相同值。完整的 PostgreSQL、RabbitMQ、MinIO、网关和 HTTPS 配置见 [`deploy/README.md`](../README.md)。

## 模型缓存与就绪检查

Compose 将命名卷 `omninest-ai-models` 挂载到 `/app/models`。将 `mobileclip2_s0_vision_fp32.onnx` 与 `policy_text_embeds.npz` 放入该卷即可启用轻量视觉标签；RapidOCR 模型随安装包内置。删除卷不会丢失 OCR 能力，但会移除视觉档模型资产。

模型文件缺失时侧车仍可提供 OCR；`/ready` 始终返回 HTTP 200，流水线版本改为不透明指纹（视觉档位或模型文件状态任一变化都会改变该指纹），不再返回档位与缺失状态明文。补齐模型并重启容器后版本指纹随之变化，照片库重分析会按新版本重新执行，不会把缺模型结果误判为已完成。

侧车就绪只是必要条件之一：`photo.ai.enabled` 在配置中心基线里内置为 `false`，管理员必须显式置为 `true`，图像分析才会对照片下发任务；关闭时任务直接取消，不会写分析记录。

`ram_plus_int8` 档需要额外的 RAM++ ONNX 与标签文件，且容器内存限额必须不低于 2GB。侧车启动时会读取 cgroup 限额，低于门槛自动降级为 `lightweight`。

容器的 Docker `HEALTHCHECK` 和 Worker 都请求 `/ready`。`/ready` 返回当前视觉档位与流水线版本，后端用它做幂等短路与重分析判断：

```bash
docker compose logs -f vision-sidecar
curl http://127.0.0.1:8090/ready
```

侧车端口默认只绑定到宿主机回环地址（开发 Compose 为 `127.0.0.1:8090`）；生产 Compose 通过内部网络由后端访问，不应直接暴露到公网。

## 环境变量

| 变量 | 默认值 | 作用 |
| --- | --- | --- |
| `OMNINEST_AI_SIDECAR_SECRET` | 空 | 受保护接口共享密钥；生产环境必须显式设置 |
| `AI_VISION_PROFILE` | `lightweight` | 视觉档位：`lightweight` 或 `ram_plus_int8` |
| `AI_MODEL_DIR` | `/app/models` | 视觉模型目录 |
| `AI_MAX_IMAGE_BYTES` | `67108864` | 单张图片最大字节数 |
| `AI_MAX_IMAGE_WIDTH` | `30000` | 图片最大宽度 |
| `AI_MAX_IMAGE_HEIGHT` | `30000` | 图片最大高度 |
| `AI_MAX_IMAGE_PIXELS` | `100000000` | 图片最大像素数 |
| `AI_MAX_CONCURRENT_INFERENCES` | `1` | 并发推理槽位数 |
| `AI_ORT_INTRA_THREADS` | `2` | ONNX Runtime CPU 线程数 |
| `AI_OCR_DET_LIMIT_SIDE_LEN` | `2048` | OCR 检测输入长边上限 |
| `AI_OCR_MIN_SCORE` | `0.65` | 常规文字框置信度阈值 |
| `AI_OCR_SMALL_BOX_MIN_SCORE` | `0.78` | 8–12px 小字框置信度阈值 |
| `AI_RAM_IDLE_TTL_SECONDS` | `180` | RAM++ 空闲卸载秒数 |
| `OMP_NUM_THREADS` | `2`（Compose） | OpenMP CPU 线程数 |

大图限制应与后端 `OMNINEST_PHOTO_AI_MAX_IMAGE_BYTES` 保持一致或更严格。调整限制后需重新创建容器使环境变量生效。
