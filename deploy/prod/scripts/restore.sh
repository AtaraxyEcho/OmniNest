#!/bin/sh
# OmniNest 生产数据恢复：将 backup.sh 的产物恢复到当前部署。
# 用法：sh scripts/restore.sh <备份目录（含 postgres.dump 与 minio-data.tar.gz）>
# 前置：先 docker compose down 停止全部服务，恢复后 up -d。
set -eu

BACKUP_DIR="${1:?用法: restore.sh <备份目录>}"
COMPOSE_FILE="docker-compose.yml"

if [ ! -f "${BACKUP_DIR}/postgres.dump" ] || [ ! -f "${BACKUP_DIR}/minio-data.tar.gz" ]; then
    echo "错误: ${BACKUP_DIR} 缺少 postgres.dump 或 minio-data.tar.gz" >&2
    exit 1
fi

if [ -f .env ]; then
    # shellcheck disable=SC1091
    . ./.env
fi
POSTGRES_DB="${POSTGRES_DB:-omninest}"
POSTGRES_USER="${POSTGRES_USER:-omninest}"
PROJECT_NAME="${PROJECT_NAME:-omninest}"

echo "[1/4] 恢复 MinIO 数据卷..."
docker run --rm --volumes-from "${PROJECT_NAME}-minio-1" \
    -v "$(cd "${BACKUP_DIR}" && pwd):/backup" alpine \
    sh -c "rm -rf /data/* && tar xzf /backup/minio-data.tar.gz -C /data"

echo "[2/4] 启动 PostgreSQL..."
docker compose -f "${COMPOSE_FILE}" up -d postgres
sleep 8

echo "[3/4] 重建数据库 ${POSTGRES_DB}..."
# dropdb/recreatedb 需要连接可用；容器内本地信任认证。
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    sh -c "dropdb --if-exists -U ${POSTGRES_USER} ${POSTGRES_DB} && createdb -U ${POSTGRES_USER} ${POSTGRES_DB}"
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    sh -c "pg_restore -U ${POSTGRES_USER} -d ${POSTGRES_DB} --no-owner --no-privileges" \
    < "${BACKUP_DIR}/postgres.dump"

echo "[4/4] 完成。现在可以 docker compose -f ${COMPOSE_FILE} up -d 启动全部服务。"
echo "提示：恢复后首次启动应用会执行 Flyway 基线校验；如跨版本恢复请先阅读发布说明。"
