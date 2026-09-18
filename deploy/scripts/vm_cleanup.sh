#!/usr/bin/env bash
set -euo pipefail

echo "=== stop leftover omninest containers ==="
names="$(docker ps -a --format '{{.Names}}' | grep -E '^omninest' || true)"
if [ -n "$names" ]; then
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    echo "removing container: $c"
    docker rm -f "$c" || true
  done <<< "$names"
else
  echo "no omninest containers"
fi

echo "=== keep hermes-workstation untouched ==="
docker ps --format 'table {{.Names}}\t{{.Status}}'

echo "=== remove old validation directory ==="
rm -rf /opt/omninest-validation
ls -la /opt | grep -E 'omninest|hermes' || true

echo "=== retag netease for compose project name ==="
if docker image inspect omninest-validation-netease-music-api:latest >/dev/null 2>&1; then
  docker tag omninest-validation-netease-music-api:latest omninest-netease-music-api:latest
  docker image rm omninest-validation-netease-music-api:latest || true
fi
docker image rm omninest-validation-ai-sidecar:latest 2>/dev/null || true

echo "=== prune dangling images ==="
docker image prune -f || true

echo "=== ensure deploy dirs and media root ==="
mkdir -p /opt/omninest/.omninest/local-media
mkdir -p /opt/omninest/deploy/prod/nginx/templates
mkdir -p /opt/omninest/deploy/netease-api
mkdir -p /opt/omninest/backend/omninest-app/target

echo "=== disk after cleanup ==="
df -h /
du -sh /opt/omninest 2>/dev/null || true
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep -E 'omninest|REPOSITORY' || true
echo "cleanup done"
