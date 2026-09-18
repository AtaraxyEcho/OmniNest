#!/usr/bin/env bash
set -euo pipefail
cd /opt/omninest/deploy/prod

cp -f /tmp/omninest-compose.yml docker-compose.yml 2>/dev/null || true
cp -f /tmp/omninest-vm-4c4g.env .env 2>/dev/null || true
sed -i 's/\${OMNINEST_LOG_PATH:logs\/omninest.log}/${OMNINEST_LOG_PATH:-logs\/omninest.log}/g' docker-compose.yml
# 强制去掉过小的 MaxMetaspaceSize（Boot4 + Hibernate7 启动需要更大 Metaspace）
sed -i 's/-XX:MaxMetaspaceSize=128m //g; s/-XX:MaxMetaspaceSize=96m //g; s/-XX:ReservedCodeCacheSize=64m //g; s/-XX:ReservedCodeCacheSize=48m //g' docker-compose.yml
sed -i 's/-Xmx256m/-Xmx320m/g; s/-Xmx128m -XX/-Xmx160m -XX/g' docker-compose.yml
echo "JAVA_OPTS from compose:"
grep -n 'JAVA_OPTS' docker-compose.yml || true
echo "mem_limit from compose:"
grep -n 'BACKEND_.*MEM_LIMIT' docker-compose.yml || true
grep -n 'BACKEND_.*MEM_LIMIT' .env || true

if [ -f /tmp/omninest-backend.jar ]; then
  mv -f /tmp/omninest-backend.jar /opt/omninest/backend/omninest-app/target/omninest-app-0.1.0-SNAPSHOT.jar
fi

echo "=== rebuild backend image ==="
docker compose build backend-api

echo "=== stop backend roles for sequential boot ==="
docker compose stop backend-api backend-worker backend-scheduler || true

wait_http() {
  local name="$1"
  local url="$2"
  local expect="$3"
  local tries="${4:-60}"
  local i code
  for i in $(seq 1 "$tries"); do
    code=$(curl -sS -m 4 -o /tmp/probe_body.json -w '%{http_code}' "$url" || true)
    if [ "$code" = "$expect" ]; then
      echo "$name OK try=$i code=$code"
      cat /tmp/probe_body.json 2>/dev/null || true
      echo
      return 0
    fi
    echo "$name wait $i code=$code"
    sleep 5
  done
  echo "$name FAILED"
  docker compose logs --tail=80 "$name" || true
  return 1
}

echo "=== start API only ==="
docker compose up -d --no-build backend-api
wait_http backend-api http://127.0.0.1:8080/api/v1/setup/status 200 70

echo "=== start worker ==="
docker compose up -d --no-build backend-worker
sleep 20
docker compose ps backend-worker
docker compose logs --tail=40 backend-worker || true

echo "=== start scheduler ==="
docker compose up -d --no-build backend-scheduler
sleep 20
docker compose ps backend-scheduler
docker compose logs --tail=40 backend-scheduler || true

echo "=== final probes ==="
curl -sS -m 5 -o /dev/null -w 'nginx_health=%{http_code}\n' http://127.0.0.1/health || true
curl -sS -m 5 -o /dev/null -w 'web_index=%{http_code}\n' http://127.0.0.1/ || true
curl -sS -m 5 -o /tmp/omni_api_via_nginx.json -w 'setup_via_nginx=%{http_code}\n' http://127.0.0.1/api/v1/setup/status || true
cat /tmp/omni_api_via_nginx.json 2>/dev/null || true
echo
curl -sS -m 5 -o /dev/null -w 'api_direct=%{http_code}\n' http://127.0.0.1:8080/api/v1/setup/status || true
curl -sS -m 5 -o /tmp/omni_act.json -w 'actuator=%{http_code}\n' http://127.0.0.1:8080/actuator/health || true
cat /tmp/omni_act.json 2>/dev/null || true
echo
curl -sS -m 5 -o /dev/null -w 'minio_public=%{http_code}\n' http://127.0.0.1:9000/minio/health/live || true

echo "=== status ==="
docker compose ps -a
echo "=== memory ==="
free -h
echo "=== stats ==="
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}'
echo "=== oom recent ==="
dmesg -T 2>/dev/null | grep -i oom | tail -8 || true
echo done
