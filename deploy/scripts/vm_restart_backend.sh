#!/usr/bin/env bash
set -euo pipefail

cd /opt/omninest/deploy/prod

if [ -f /tmp/omninest-backend.jar ]; then
  mv -f /tmp/omninest-backend.jar /opt/omninest/backend/omninest-app/target/omninest-app-0.1.0-SNAPSHOT.jar
fi
if [ -f /tmp/omninest-compose.yml ]; then
  cp -f /tmp/omninest-compose.yml /opt/omninest/deploy/prod/docker-compose.yml
fi
sed -i 's/\${OMNINEST_LOG_PATH:logs\/omninest.log}/${OMNINEST_LOG_PATH:-logs\/omninest.log}/g' docker-compose.yml

echo "=== rebuild backend image ==="
docker compose build backend-api

echo "=== restart backend roles ==="
docker compose up -d --no-build backend-api backend-worker backend-scheduler

echo "=== wait for API ==="
ok=0
for i in $(seq 1 80); do
  code=$(curl -sS -o /tmp/omni_setup_status.json -w '%{http_code}' http://127.0.0.1:8080/api/v1/setup/status || true)
  if [ "$code" = "200" ]; then
    echo "API ok at try $i"
    cat /tmp/omni_setup_status.json || true
    echo
    ok=1
    break
  fi
  echo "api probe $i code=$code"
  sleep 5
done

echo "=== probes ==="
curl -sS -o /dev/null -w 'nginx_health=%{http_code}\n' http://127.0.0.1/health || true
curl -sS -o /dev/null -w 'web_index=%{http_code}\n' http://127.0.0.1/ || true
curl -sS -o /tmp/omni_api_via_nginx.json -w 'setup_via_nginx=%{http_code}\n' http://127.0.0.1/api/v1/setup/status || true
cat /tmp/omni_api_via_nginx.json 2>/dev/null || true
echo
curl -sS -o /dev/null -w 'api_direct=%{http_code}\n' http://127.0.0.1:8080/api/v1/setup/status || true
curl -sS -o /dev/null -w 'actuator=%{http_code}\n' http://127.0.0.1:8080/actuator/health || true
curl -sS -o /dev/null -w 'minio_public=%{http_code}\n' http://127.0.0.1:9000/minio/health/live || true

echo "=== container status ==="
docker compose ps -a
echo "=== memory ==="
free -h
echo "=== docker stats ==="
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' | grep -E 'omninest|hermes|NAME'
echo "=== backend-api last 60 lines ==="
docker compose logs --tail=60 backend-api || true

if [ "$ok" != "1" ]; then
  echo "DEPLOY_SMOKE_FAILED"
  exit 1
fi
echo "DEPLOY_SMOKE_OK"
