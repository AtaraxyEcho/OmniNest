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
# .env 是 Compose 的属性文件而非 shell 脚本（值可能含括号/空格，模板的
# MusicBrainz User-Agent 即如此），整体 source 会语法错误，只提取所需键。
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

# 备份包含全部用户数据与凭据哈希，创建即收紧权限，避免多用户主机上被其他账户读取
umask 077
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

echo "[1/4] PostgreSQL 逻辑备份 (${POSTGRES_DB})..."
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Fc \
    > "${BACKUP_DIR}/postgres.dump"

echo "[2/4] MinIO 数据卷打包 (omninest-minio)..."
docker run --rm --volumes-from "${PROJECT_NAME}-minio-1" \
    -v "$(cd "${BACKUP_DIR}" && pwd):/backup" alpine \
    sh -c "umask 077 && tar czf /backup/minio-data.tar.gz -C /data ."
chmod 600 "${BACKUP_DIR}/minio-data.tar.gz" 2>/dev/null || true

echo "[3/4] 生成 SHA-256 校验和..."
(cd "${BACKUP_DIR}" && sha256sum postgres.dump minio-data.tar.gz > SHA256SUMS)
chmod 600 "${BACKUP_DIR}/SHA256SUMS"

echo "[4/4] 写入清单..."
{
    echo "omninest backup ${STAMP}"
    echo "postgres: ${POSTGRES_DB} (custom format dump)"
    echo "minio: omninest-minio volume tarball"
    echo "integrity: sha256sum -c SHA256SUMS"
    du -sh "${BACKUP_DIR}"/* 2>/dev/null || true
} > "${BACKUP_DIR}/MANIFEST.txt"

echo "备份完成: ${BACKUP_DIR}"
echo "注意：MinIO 为运行中快照，恢复时以数据库为准校验对象一致性。"
