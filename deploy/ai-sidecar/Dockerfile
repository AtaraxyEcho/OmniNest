FROM python:3.11-slim

WORKDIR /app

# OpenCV 运行库和模型下载证书。
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

ENV INSIGHTFACE_ROOT=/app/models/insightface \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN mkdir -p /app/models/insightface && \
    useradd --system --create-home --home-dir /home/sidecar --shell /usr/sbin/nologin sidecar && \
    chown -R sidecar:sidecar /app

EXPOSE 8090

USER sidecar

HEALTHCHECK --interval=30s --timeout=10s --start-period=10m --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/ready', timeout=5)"]

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8090"]
