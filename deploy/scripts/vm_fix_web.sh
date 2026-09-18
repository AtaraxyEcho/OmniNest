#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/omninest
echo "=== current web tree ==="
ls -la "$BASE/web" 2>/dev/null || true
find "$BASE/web" -maxdepth 3 -type d 2>/dev/null | head -20 || true
echo "=== archive sample ==="
tar -tzf /tmp/omninest-web.tgz 2>/dev/null | head -20 || true
echo "=== re-extract web correctly ==="
rm -rf "$BASE/web" "$BASE/build"
mkdir -p "$BASE/web"
tar -xzf /tmp/omninest-web.tgz -C "$BASE"
if [ -d "$BASE/build/web" ]; then
  rm -rf "$BASE/web"
  mv "$BASE/build/web" "$BASE/web"
  rmdir "$BASE/build" 2>/dev/null || true
fi
ls -la "$BASE/web" | head -20
if [ -f "$BASE/web/index.html" ]; then
  echo WEB_INDEX_OK
else
  echo WEB_INDEX_MISSING
  find "$BASE" -name 'index.html' 2>/dev/null | head
fi
du -sh "$BASE/web"
cp -f "$BASE/deploy/prod/nginx/Dockerfile.prebuilt" "$BASE/deploy/prod/nginx/Dockerfile"
echo "=== Dockerfile ==="
head -8 "$BASE/deploy/prod/nginx/Dockerfile"
echo "=== env key fields ==="
grep -E 'IMAGE_TAG|PUBLIC_HOST|ALLOWED|LOCAL_MEDIA|CLAMAV|SETUP_WEB|MINIO_PUBLIC|COMPOSE_PROFILES' "$BASE/deploy/prod/.env"
echo "fix done"
