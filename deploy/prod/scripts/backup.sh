#!/bin/sh
# OmniNest 生产数据备份：PostgreSQL 逻辑备份 + MinIO 数据卷打包。
# 用法：在 deploy/prod 目录执行 sh scripts/backup.sh [备份目录]
# 建议 crontab 每日运行；产物为 omninest-<时间戳>/ 目录。
set -eu

BACKUP_ROOT="${1:-./backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/omninest-${STAMP}"
COMPOSE_FILE="docker-compose.yml"

# 数据库与对象存储凭据从 .env 读取（与 Compose 一致）。
if [ -f .env ]; then
    # shellcheck disable=SC1091
    . ./.env
fi
POSTGRES_DB="${POSTGRES_DB:-omninest}"
POSTGRES_USER="${POSTGRES_USER:-omninest}"
PROJECT_NAME="${PROJECT_NAME:-omninest}"

mkdir -p "${BACKUP_DIR}"

echo "[1/3] PostgreSQL 逻辑备份 (${POSTGRES_DB})..."
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Fc \
    > "${BACKUP_DIR}/postgres.dump"

echo "[2/3] MinIO 数据卷打包 (omninest-minio)..."
docker run --rm --volumes-from "${PROJECT_NAME}-minio-1" \
    -v "$(cd "${BACKUP_DIR}" && pwd):/backup" alpine \
    sh -c "tar czf /backup/minio-data.tar.gz -C /data ."

echo "[3/3] 写入清单..."
{
    echo "omninest backup ${STAMP}"
    echo "postgres: ${POSTGRES_DB} (custom format dump)"
    echo "minio: omninest-minio volume tarball"
    du -sh "${BACKUP_DIR}"/* 2>/dev/null || true
} > "${BACKUP_DIR}/MANIFEST.txt"

echo "备份完成: ${BACKUP_DIR}"
echo "注意：MinIO 为运行中快照，恢复时以数据库为准校验对象一致性。"
