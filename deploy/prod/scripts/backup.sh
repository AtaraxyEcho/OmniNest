#!/bin/sh
# OmniNest 生产数据备份：PostgreSQL 逻辑备份 + MinIO/rclone 命名卷打包。
# 用法：在 deploy/prod 目录执行 sh scripts/backup.sh [备份目录]
# 建议 crontab 每日运行；产物为 omninest-<时间戳>/ 目录。
set -eu

# 解析备份目录的宿主机路径：Git Bash 下 pwd 返回 /d/...，Docker Desktop 无法解析；
# 优先使用 pwd -W 的 Windows 盘符路径，Linux 环境自动回退到 pwd。
host_pwd() {
    cd "$1"
    if pwd -W >/dev/null 2>&1; then
        pwd -W
    else
        pwd
    fi
}

BACKUP_ROOT="${1:-./backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/omninest-${STAMP}"
COMPOSE_FILE="docker-compose.yml"

# 数据库与对象存储凭据从 .env 读取（与 Compose 一致）。
# .env 是 Compose 的属性文件而非 shell 脚本（值可能含括号/空格，模板的
# MusicBrainz User-Agent 即如此），整体 source 会语法错误，只提取所需键。
read_env_value() {
    sed -n "s/^$1=//p" .env | tail -n 1 | tr -d '
'
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

# 备份包含全部用户数据与凭据哈希，创建即收紧权限，避免多用户主机上被其他账户读取
umask 077
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

require_volume() {
    if ! docker volume inspect "${PROJECT_NAME}_$1" >/dev/null 2>&1; then
        echo "错误: 命名卷 ${PROJECT_NAME}_$1 不存在" >&2
        exit 1
    fi
}

backup_volume() {
    volume="$1"
    archive="$2"
    require_volume "${volume}"
    docker run --rm \
        -v "${PROJECT_NAME}_${volume}:/data" \
        -v "$(host_pwd "${BACKUP_DIR}"):/backup" alpine \
        sh -c "umask 077 && tar czf /backup/${archive} -C /data ."
    chmod 600 "${BACKUP_DIR}/${archive}" 2>/dev/null || true
}

echo "[1/6] PostgreSQL 逻辑备份 (${POSTGRES_DB})..."
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Fc \
    > "${BACKUP_DIR}/postgres.dump"

# MinIO 与 rclone 使用命名卷直接挂载，不依赖运行中的容器名；
# compose down 之后 MinIO 容器不存在时同样可备份。
echo "[2/6] MinIO 数据卷打包 (${PROJECT_NAME}_omninest-minio)..."
backup_volume omninest-minio minio-data.tar.gz

echo "[3/6] rclone 配置与本地卷打包..."
backup_volume omninest-rclone rclone-config.tar.gz
backup_volume omninest-rclone-local rclone-local-data.tar.gz
backup_volume omninest-rclone-imports rclone-imports-data.tar.gz

echo "[4/6] 生成 SHA-256 校验和..."
(cd "${BACKUP_DIR}" && sha256sum postgres.dump minio-data.tar.gz \
    rclone-config.tar.gz rclone-local-data.tar.gz rclone-imports-data.tar.gz > SHA256SUMS)
chmod 600 "${BACKUP_DIR}/SHA256SUMS"

echo "[5/6] 记录加密密钥指纹..."
CREDENTIAL_KEY_SHA256=""
if [ -n "${CREDENTIAL_KEY:-}" ]; then
    CREDENTIAL_KEY_SHA256="$(printf '%s' "${CREDENTIAL_KEY}" | sha256sum | cut -d' ' -f1)"
fi

echo "[6/6] 写入清单..."
{
    echo "omninest backup ${STAMP}"
    echo "postgres: ${POSTGRES_DB} (custom format dump)"
    echo "minio: ${PROJECT_NAME}_omninest-minio volume tarball"
    echo "rclone: ${PROJECT_NAME}_omninest-rclone / -local / -imports volume tarballs"
    echo "integrity: sha256sum -c SHA256SUMS"
    if [ -n "${CREDENTIAL_KEY_SHA256}" ]; then
        echo "credential-key-sha256: ${CREDENTIAL_KEY_SHA256}"
        echo "注意: 恢复时必须使用同一 OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY，"
        echo "      否则外部存储凭据、OAuth 密钥与 TOTP 秘钥无法解密。请另行安全保管 .env。"
    else
        echo "credential-key-sha256: (未配置 OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY)"
    fi
    du -sh "${BACKUP_DIR}"/* 2>/dev/null || true
} > "${BACKUP_DIR}/MANIFEST.txt"

echo "备份完成: ${BACKUP_DIR}"
echo "注意：MinIO 为运行中快照，恢复时以数据库为准校验对象一致性。"
