# 必须使用基于 Debian (glibc) 的 python:3.11-slim 镜像：
# 1. onnxruntime 官方 wheel 依赖 glibc；
# 2. 模型空闲卸载依赖 glibc 的 libc.so.6 malloc_trim(0) 归还物理内存，严禁改为 Alpine (musl)。
FROM python:3.11-slim

WORKDIR /app

RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && python -m pip check

COPY app.py .

# MALLOC_MMAP_THRESHOLD_=65536 让 >=64KB 的 ONNX/Numpy 缓冲区直接走 mmap，释放时立即归还 OS；
# MALLOC_TRIM_THRESHOLD_=65536 降低 glibc brk 堆收缩阈值，配合 malloc_trim(0) 避免 RSS 高水位滞留。
ENV AI_MODEL_DIR=/app/models \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    MALLOC_TRIM_THRESHOLD_=65536 \
    MALLOC_MMAP_THRESHOLD_=65536

RUN mkdir -p /app/models && \
    useradd --system --create-home --home-dir /home/sidecar --shell /usr/sbin/nologin sidecar && \
    chown -R sidecar:sidecar /app

EXPOSE 8090

USER sidecar

HEALTHCHECK --interval=30s --timeout=10s --start-period=2m --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/ready', timeout=5)"]

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8090"]
