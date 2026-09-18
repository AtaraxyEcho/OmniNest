#!/usr/bin/env bash
set -euo pipefail

BASE=/opt/omninest
ROOT="$BASE"
PROD="$BASE/deploy/prod"

echo "=== sync layout ==="
mkdir -p \
  "$BASE/backend/omninest-app/target" \
  "$BASE/deploy/backend" \
  "$BASE/deploy/netease-api" \
  "$BASE/deploy/prod/nginx/templates" \
  "$BASE/.omninest/local-media" \
  "$BASE/web"

# nginx prebuilt image expects context root with web/ + deploy/prod/nginx/
if [ -f /tmp/omninest-web.tgz ]; then
  echo "extract web"
  rm -rf "$BASE/web"
  mkdir -p "$BASE/web"
  tar -xzf /tmp/omninest-web.tgz -C "$BASE/web"
fi

if [ -f /tmp/omninest-backend.jar ]; then
  echo "install backend jar"
  mv -f /tmp/omninest-backend.jar "$BASE/backend/omninest-app/target/omninest-app-0.1.0-SNAPSHOT.jar"
fi

if [ -f /tmp/omninest-deploy.tgz ]; then
  echo "extract deploy package"
  tar -xzf /tmp/omninest-deploy.tgz -C "$BASE"
fi

# 4C4G：nginx 使用本地预构建 Web，避免在小内存机下载 Flutter SDK
if [ -f "$PROD/nginx/Dockerfile.prebuilt" ]; then
  cp -f "$PROD/nginx/Dockerfile.prebuilt" "$PROD/nginx/Dockerfile"
fi

if [ -f /tmp/omninest-vm-4c4g.env ]; then
  cp -f /tmp/omninest-vm-4c4g.env "$PROD/.env"
fi

echo "=== verify package ==="
ls -lah "$BASE/backend/omninest-app/target"
ls -la "$PROD"
ls -la "$PROD/nginx" | head
test -f "$BASE/web/index.html" && echo "web index ok" || echo "web index MISSING"
test -f "$PROD/docker-compose.yml" && echo "compose ok"
test -f "$PROD/.env" && echo "env ok"
du -sh "$BASE" "$BASE/web" 2>/dev/null || true
echo "sync done"
