#!/usr/bin/env bash
set -euo pipefail

cd /opt/omninest/deploy/prod

# Docker Compose 默认值插值必须是 ${VAR:-default}
sed -i 's/\${OMNINEST_LOG_PATH:logs\/omninest.log}/${OMNINEST_LOG_PATH:-logs\/omninest.log}/g' docker-compose.yml

# 预构建 Web 镜像需要放行 web/ 构建上下文
if [ -f /opt/omninest/deploy/prod/nginx/Dockerfile.dockerignore ]; then
  if ! grep -q '^!web/$' /opt/omninest/deploy/prod/nginx/Dockerfile.dockerignore; then
    printf '%s\n' '**' '!web/' '!web/**' '' > /tmp/omninest-nginx.dockerignore
    tail -n +2 /opt/omninest/deploy/prod/nginx/Dockerfile.dockerignore >> /tmp/omninest-nginx.dockerignore
    # 原文件首行是 **，合并后避免重复
    if ! grep -q '^!web/$' /tmp/omninest-nginx.dockerignore; then
      sed -i '1a !web/\n!web/**' /opt/omninest/deploy/prod/nginx/Dockerfile.dockerignore
    else
      cp /tmp/omninest-nginx.dockerignore /opt/omninest/deploy/prod/nginx/Dockerfile.dockerignore
    fi
  fi
fi

# 若仓库版 dockerignore 已含 !web/ 则以上为幂等；再强制写入部署期安全版本
cat > /opt/omninest/deploy/prod/nginx/Dockerfile.dockerignore <<'EOF'
**

!web/
!web/**
!deploy/
deploy/*
!deploy/prod/
deploy/prod/*
!deploy/prod/nginx/
!deploy/prod/nginx/**
EOF

cp -f /opt/omninest/deploy/prod/nginx/Dockerfile.prebuilt /opt/omninest/deploy/prod/nginx/Dockerfile

echo "=== compose config sanity ==="
docker compose config --services

echo "=== reuse netease image if present ==="
if docker image inspect omninest-netease-music-api:latest >/dev/null 2>&1; then
  echo "netease image available"
else
  echo "netease image missing, will build"
fi

echo "=== build backend + nginx ==="
docker compose build backend-api nginx
if ! docker image inspect omninest-netease-music-api:latest >/dev/null 2>&1; then
  docker compose build netease-music-api
fi

echo "=== start stack (no clamav/photo-ai/certbot) ==="
docker compose up -d --no-build

echo "=== wait for nginx health ==="
for i in $(seq 1 90); do
  if curl -fsS http://127.0.0.1/health >/dev/null 2>&1; then
    echo "nginx health ok at try $i"
    break
  fi
  sleep 5
done

echo "=== wait for backend api ==="
for i in $(seq 1 90); do
  code=$(curl -sS -o /tmp/omni_setup_status.json -w '%{http_code}' http://127.0.0.1:8080/api/v1/setup/status || true)
  if [ "$code" = "200" ]; then
    echo "api setup status ok at try $i"
    cat /tmp/omni_setup_status.json || true
    echo
    break
  fi
  echo "api probe $i code=$code"
  sleep 5
done

echo "=== status ==="
docker compose ps -a
echo "=== memory ==="
free -h
echo "=== docker stats snapshot ==="
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'
echo "=== probes ==="
curl -sS -o /dev/null -w 'nginx_health=%{http_code}\n' http://127.0.0.1/health || true
curl -sS -o /dev/null -w 'web_index=%{http_code}\n' http://127.0.0.1/ || true
curl -sS -o /tmp/omni_api_via_nginx.json -w 'setup_via_nginx=%{http_code}\n' http://127.0.0.1/api/v1/setup/status || true
cat /tmp/omni_api_via_nginx.json 2>/dev/null || true
echo
curl -sS -o /dev/null -w 'api_direct=%{http_code}\n' http://127.0.0.1:8080/api/v1/setup/status || true
curl -sS -o /dev/null -w 'minio_public=%{http_code}\n' http://127.0.0.1:9000/minio/health/live || true
curl -sS -o /dev/null -w 'actuator_direct=%{http_code}\n' http://127.0.0.1:8080/actuator/health || true

echo "=== recent backend-api logs ==="
docker compose logs --tail=100 backend-api || true
echo "=== recent nginx logs ==="
docker compose logs --tail=40 nginx || true
echo "=== deploy script finished ==="
