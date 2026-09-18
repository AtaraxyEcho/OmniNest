#!/usr/bin/env bash
set -euo pipefail
cd /opt/omninest/deploy/prod
cp -f /tmp/omninest-compose.yml docker-compose.yml
cp -f /tmp/omninest-vm-4c4g.env .env
python3 - <<'PY'
from pathlib import Path
p = Path('docker-compose.yml')
text = p.read_text(encoding='utf-8')
text = text.replace('${OMNINEST_LOG_PATH:logs/omninest.log}', '${OMNINEST_LOG_PATH:-logs/omninest.log}')
text = text.replace('-XX:MaxMetaspaceSize=128m ', '')
text = text.replace('-XX:MaxMetaspaceSize=96m ', '')
p.write_text(text, encoding='utf-8')
print('compose patched')
PY
grep -n 'JAVA_OPTS_SCHEDULER\|BACKEND_SCHEDULER_MEM' docker-compose.yml .env || true
docker compose up -d --no-build backend-scheduler
sleep 50
docker compose ps backend-api backend-worker backend-scheduler
echo '=== scheduler logs ==='
docker compose logs --tail=25 backend-scheduler || true
echo '=== probes ==='
curl -sS -m 5 -o /dev/null -w 'api=%{http_code}\n' http://127.0.0.1:8080/api/v1/setup/status || true
curl -sS -m 5 -o /dev/null -w 'nginx=%{http_code}\n' http://127.0.0.1/api/v1/setup/status || true
docker inspect -f '{{.Name}} RestartCount={{.RestartCount}} Status={{.State.Status}} OOM={{.State.OOMKilled}}' \
  omninest-backend-api-1 omninest-backend-worker-1 omninest-backend-scheduler-1
free -h
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}' | head -20
echo done
