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

# 旧版本产物没有校验文件，跳过并告警；校验不匹配时直接中止，避免恢复损坏数据。
if [ -f "${BACKUP_DIR}/SHA256SUMS" ]; then
    (cd "${BACKUP_DIR}" && sha256sum -c SHA256SUMS) || {
        echo "错误: 备份文件 SHA-256 校验失败" >&2
        exit 1
    }
else
    echo "警告: 备份缺少 SHA256SUMS（旧版本产物），跳过完整性校验" >&2
fi

# .env 是 Compose 的属性文件而非 shell 脚本（值可能含括号/空格），整体
# source 会语法错误，只提取所需键。
read_env_value() {
    sed -n "s/^$1=//p" .env | tail -n 1
}
if [ -f .env ]; then
    POSTGRES_DB="$(read_env_value POSTGRES_DB)"
    POSTGRES_USER="$(read_env_value POSTGRES_USER)"
    PROJECT_NAME="$(read_env_value COMPOSE_PROJECT_NAME)"
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
# 等待 PostgreSQL 就绪：首次初始化（建库、恢复基线卷）耗时不定，固定 sleep 会竞态失败。
attempts=0
until docker compose -f "${COMPOSE_FILE}" exec -T postgres \
        pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 30 ]; then
        echo "错误: PostgreSQL 在 ${attempts} 次探测（约 60 秒）后仍未就绪" >&2
        exit 1
    fi
    sleep 2
done

echo "[3/4] 重建数据库 ${POSTGRES_DB}..."
# dropdb/recreatedb 需要连接可用；容器内本地信任认证。
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    sh -c "dropdb --if-exists -U ${POSTGRES_USER} ${POSTGRES_DB} && createdb -U ${POSTGRES_USER} ${POSTGRES_DB}"
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    sh -c "pg_restore -U ${POSTGRES_USER} -d ${POSTGRES_DB} --no-owner --no-privileges" \
    < "${BACKUP_DIR}/postgres.dump"

echo "[4/4] 完成。现在可以 docker compose -f ${COMPOSE_FILE} up -d 启动全部服务。"
echo "提示：恢复后首次启动应用会执行 Flyway 基线校验；如跨版本恢复请先阅读发布说明。"
