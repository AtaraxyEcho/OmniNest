#!/usr/bin/env bash
set -euo pipefail
cd /opt/omninest/deploy/prod
echo "=== wait 90s for roles to settle ==="
sleep 90
echo "=== compose ps ==="
docker compose ps -a
echo "=== probes ==="
curl -sS -m 5 -o /dev/null -w 'nginx_health=%{http_code}\n' http://127.0.0.1/health || true
curl -sS -m 5 -o /dev/null -w 'web_index=%{http_code}\n' http://127.0.0.1/ || true
curl -sS -m 5 -o /tmp/s1.json -w 'setup_via_nginx=%{http_code}\n' http://127.0.0.1/api/v1/setup/status || true
cat /tmp/s1.json; echo
curl -sS -m 5 -o /tmp/a1.json -w 'actuator=%{http_code}\n' http://127.0.0.1:8080/actuator/health || true
cat /tmp/a1.json; echo
curl -sS -m 5 -o /dev/null -w 'minio=%{http_code}\n' http://127.0.0.1:9000/minio/health/live || true
echo "=== restart counts / oom flags ==="
docker inspect -f '{{.Name}} RestartCount={{.RestartCount}} OOMKilled={{.State.OOMKilled}} Status={{.State.Status}}' \
  omninest-backend-api-1 omninest-backend-worker-1 omninest-backend-scheduler-1
echo "=== memory ==="
free -h
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}'
echo "=== recent oom ==="
dmesg -T 2>/dev/null | grep -i 'out of memory' | tail -5 || true
echo "=== worker/sch tail ==="
docker compose logs --tail=15 backend-worker || true
docker compose logs --tail=15 backend-scheduler || true
echo done
