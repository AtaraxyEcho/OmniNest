#!/usr/bin/env bash
set -uo pipefail
cd /opt/omninest/deploy/prod

echo "=== dmesg OOM ==="
dmesg -T 2>/dev/null | grep -iE 'oom|killed process|out of memory' | tail -30 || true

echo "=== container restart counts ==="
docker inspect -f '{{.Name}} RestartCount={{.RestartCount}} OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}} Status={{.State.Status}}' \
  omninest-backend-api-1 omninest-backend-worker-1 omninest-backend-scheduler-1 2>/dev/null || true

echo "=== backend-api full recent ==="
docker compose logs --tail=200 backend-api 2>/dev/null | tail -200

echo "=== backend-worker recent ==="
docker compose logs --tail=80 backend-worker 2>/dev/null | tail -80

echo "=== backend-scheduler recent ==="
docker compose logs --tail=80 backend-scheduler 2>/dev/null | tail -80

echo "=== probe once ==="
curl -sS -m 5 -o /tmp/omni_setup_status.json -w 'direct=%{http_code}\n' http://127.0.0.1:8080/api/v1/setup/status || true
cat /tmp/omni_setup_status.json 2>/dev/null || true
echo
curl -sS -m 5 -o /tmp/omni_nginx.json -w 'via_nginx=%{http_code}\n' http://127.0.0.1/api/v1/setup/status || true
cat /tmp/omni_nginx.json 2>/dev/null || true
echo
curl -sS -m 5 -o /tmp/omni_act.json -w 'actuator=%{http_code}\n' http://127.0.0.1:8080/actuator/health || true
cat /tmp/omni_act.json 2>/dev/null || true
echo

echo "=== free ==="
free -h
echo "=== docker stats ==="
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}'
echo "=== ps ==="
docker compose ps -a
echo done
