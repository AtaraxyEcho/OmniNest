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
    sed -n "s/^$1=//p" .env | tail -n 1 | tr -d ''
}
if [ -f .env ]; then
    POSTGRES_DB="$(read_env_value POSTGRES_DB)"
    POSTGRES_USER="$(read_env_value POSTGRES_USER)"
    PROJECT_NAME="$(read_env_value COMPOSE_PROJECT_NAME)"
    CREDENTIAL_KEY="$(read_env_value OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY)"
fi
POSTGRES_DB="${POSTGRES_DB:-omninest}"
POSTGRES_USER="${POSTGRES_USER:-omninest}"
PROJECT_NAME="${PROJECT_NAME:-omninest}"

# 加密密钥指纹必须与备份时一致：密钥不同时外部存储凭据、OAuth 密钥与
# TOTP 秘钥无法解密，恢复出来的数据看似完整但关键功能全部失效。
BACKUP_KEY_SHA256="$(sed -n 's/^credential-key-sha256: //p' "${BACKUP_DIR}/MANIFEST.txt" 2>/dev/null | head -n 1)"
if [ -n "${BACKUP_KEY_SHA256}" ] && [ "${BACKUP_KEY_SHA256}" != "(未配置 OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY)" ]; then
    if [ -z "${CREDENTIAL_KEY:-}" ]; then
        echo "错误: 备份记录了指纹 ${BACKUP_KEY_SHA256}，但当前 .env 未配置 OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY" >&2
        exit 1
    fi
    CURRENT_KEY_SHA256="$(printf '%s' "${CREDENTIAL_KEY}" | sha256sum | cut -d' ' -f1)"
    if [ "${CURRENT_KEY_SHA256}" != "${BACKUP_KEY_SHA256}" ]; then
        echo "错误: 当前 OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY 与备份不一致" >&2
        echo "      备份指纹: ${BACKUP_KEY_SHA256}" >&2
        echo "      当前指纹: ${CURRENT_KEY_SHA256}" >&2
        echo "      使用错误密钥恢复会让外部存储凭据、OAuth 密钥与 TOTP 秘钥永久无法解密。" >&2
        exit 1
    fi
fi

# 直接挂载命名卷：docker compose down 之后容器已不存在，
# --volumes-from 会因找不到容器而在第一步失败。
restore_volume() {
    volume="$1"
    archive="$2"
    if [ ! -f "${BACKUP_DIR}/${archive}" ]; then
        echo "警告: 备份缺少 ${archive}，跳过 ${volume}" >&2
        return 0
    fi
    docker volume create "${PROJECT_NAME}_${volume}" >/dev/null
    docker run --rm \
        -v "${PROJECT_NAME}_${volume}:/data" \
        -v "$(cd "${BACKUP_DIR}" && pwd):/backup" alpine \
        sh -c "rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null || true; tar xzf /backup/${archive} -C /data"
}

echo "[1/6] 恢复 MinIO 数据卷..."
restore_volume omninest-minio minio-data.tar.gz

echo "[2/6] 恢复 rclone 配置与本地卷..."
restore_volume omninest-rclone rclone-config.tar.gz
restore_volume omninest-rclone-local rclone-local-data.tar.gz
restore_volume omninest-rclone-imports rclone-imports-data.tar.gz

echo "[3/6] 启动 PostgreSQL..."
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

echo "[4/6] 重建数据库 ${POSTGRES_DB}..."
# dropdb/recreatedb 需要连接可用；容器内本地信任认证。
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    sh -c "dropdb --if-exists -U ${POSTGRES_USER} ${POSTGRES_DB} && createdb -U ${POSTGRES_USER} ${POSTGRES_DB}"
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    sh -c "pg_restore -U ${POSTGRES_USER} -d ${POSTGRES_DB} --no-owner --no-privileges" \
    < "${BACKUP_DIR}/postgres.dump"

echo "[5/6] 校验备份清单..."
if [ -f "${BACKUP_DIR}/MANIFEST.txt" ]; then
    sed -n '1,8p' "${BACKUP_DIR}/MANIFEST.txt"
else
    echo "警告: 备份缺少 MANIFEST.txt（旧版本产物）" >&2
fi

echo "[6/6] 完成。现在可以 docker compose -f ${COMPOSE_FILE} up -d 启动全部服务。"
echo "提示：恢复后首次启动应用会执行 Flyway 基线校验；如跨版本恢复请先阅读发布说明。"
