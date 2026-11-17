#!/bin/sh
# OmniNest 生产数据备份：PostgreSQL 逻辑备份 + MinIO/rclone 命名卷打包，全程流式加密。
# 用法：在 deploy/prod 目录执行 sh scripts/backup.sh [备份目录]
# 建议 crontab 每日运行；产物为 omninest-<时间戳>/ 目录。
#
# 加密口令优先读 OMNINEST_BACKUP_ENCRYPTION_KEY，未配置时回退到
# OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY。没有口令时拒绝生成明文备份。
set -eu

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
    BACKUP_ENCRYPTION_KEY="$(read_env_value OMNINEST_BACKUP_ENCRYPTION_KEY)"
fi
POSTGRES_DB="${POSTGRES_DB:-omninest}"
POSTGRES_USER="${POSTGRES_USER:-omninest}"
PROJECT_NAME="${PROJECT_NAME:-omninest}"
BACKUP_PASSPHRASE="${BACKUP_ENCRYPTION_KEY:-${CREDENTIAL_KEY:-}}"

if [ -z "${BACKUP_PASSPHRASE}" ]; then
    echo "错误: 未配置 OMNINEST_BACKUP_ENCRYPTION_KEY 或 OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY，拒绝生成明文备份" >&2
    exit 1
fi
# 加密在宿主机管道执行：官方 alpine 镜像只有 busybox，不含 openssl。
if ! command -v openssl >/dev/null 2>&1; then
    echo "错误: 宿主机缺少 openssl 命令，无法执行流式加密备份" >&2
    exit 1
fi
export BACKUP_PASSPHRASE

# 备份包含全部用户数据与凭据哈希，创建即收紧权限，避免多用户主机上被其他账户读取
umask 077
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"
# 中断或失败时清掉半成品，避免下次被误认为完整产物。
trap 'rm -f "${BACKUP_DIR}"/*.tmp "${BACKUP_DIR}"/*.status 2>/dev/null || true' EXIT

require_volume() {
    if ! docker volume inspect "${PROJECT_NAME}_$1" >/dev/null 2>&1; then
        echo "错误: 命名卷 ${PROJECT_NAME}_$1 不存在" >&2
        exit 1
    fi
}

# 把生产者命令的标准输出经 openssl 流式加密到目标文件，磁盘上不落明文。
# POSIX sh 没有 pipefail：用状态文件取生产者的真实退出码，失败时删除半成品。
encrypt_to_file() {
    target="$1"
    shift
    tmp="${target}.tmp"
    status="${target}.status"
    rm -f "${tmp}" "${status}"
    { "$@"; echo $? > "${status}"; } \
        | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
            -pass env:BACKUP_PASSPHRASE > "${tmp}"
    producer_status="$(cat "${status}" 2>/dev/null || echo 1)"
    rm -f "${status}"
    if [ "${producer_status}" != "0" ]; then
        rm -f "${tmp}"
        echo "错误: 备份数据流生成失败（退出码 ${producer_status}），已删除半成品" >&2
        exit 1
    fi
    mv "${tmp}" "${target}"
    chmod 600 "${target}" 2>/dev/null || true
}

backup_volume() {
    volume="$1"
    archive="$2"
    require_volume "${volume}"
    # 只读挂载数据卷；tar 输出直接进宿主机 openssl，容器内不写任何备份文件。
    encrypt_to_file "${BACKUP_DIR}/${archive}.enc" \
        docker run --rm -v "${PROJECT_NAME}_${volume}:/data:ro" alpine \
        sh -c 'tar czf - -C /data .'
}

echo "[1/6] PostgreSQL 逻辑备份并流式加密 (${POSTGRES_DB})..."
encrypt_to_file "${BACKUP_DIR}/postgres.dump.enc" \
    docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Fc

# MinIO 与 rclone 使用命名卷直接挂载，不依赖运行中的容器名；
# compose down 之后 MinIO 容器不存在时同样可备份。
echo "[2/6] MinIO 数据卷打包加密 (${PROJECT_NAME}_omninest-minio)..."
backup_volume omninest-minio minio-data.tar.gz

echo "[3/6] rclone 配置与本地卷打包加密..."
backup_volume omninest-rclone rclone-config.tar.gz
backup_volume omninest-rclone-local rclone-local-data.tar.gz
backup_volume omninest-rclone-imports rclone-imports-data.tar.gz

echo "[4/6] 生成 SHA-256 校验和..."
(cd "${BACKUP_DIR}" && sha256sum postgres.dump.enc minio-data.tar.gz.enc \
    rclone-config.tar.gz.enc rclone-local-data.tar.gz.enc rclone-imports-data.tar.gz.enc \
    > SHA256SUMS)
chmod 600 "${BACKUP_DIR}/SHA256SUMS"

BACKUP_KEY_SHA256="$(printf '%s' "${BACKUP_PASSPHRASE}" | sha256sum | cut -d' ' -f1)"
CREDENTIAL_KEY_SHA256=""
if [ -n "${CREDENTIAL_KEY:-}" ]; then
    CREDENTIAL_KEY_SHA256="$(printf '%s' "${CREDENTIAL_KEY}" | sha256sum | cut -d' ' -f1)"
fi

echo "[5/6] 写入加密与密钥指纹清单..."
{
    echo "omninest backup ${STAMP}"
    echo "postgres: ${POSTGRES_DB} (custom format dump, encrypted)"
    echo "minio: ${PROJECT_NAME}_omninest-minio volume tarball (encrypted)"
    echo "rclone: ${PROJECT_NAME}_omninest-rclone / -local / -imports volume tarballs (encrypted)"
    echo "encryption: aes-256-cbc-pbkdf2-600000"
    echo "integrity: sha256sum -c SHA256SUMS"
    echo "backup-key-sha256: ${BACKUP_KEY_SHA256}"
    if [ -n "${CREDENTIAL_KEY_SHA256}" ]; then
        echo "credential-key-sha256: ${CREDENTIAL_KEY_SHA256}"
    else
        echo "credential-key-sha256: (未配置 OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY)"
    fi
} > "${BACKUP_DIR}/MANIFEST.txt"
chmod 600 "${BACKUP_DIR}/MANIFEST.txt"

echo "[6/6] 完成。备份目录: ${BACKUP_DIR}"
echo "注意: 恢复时必须提供同一口令；credential 密钥不同会导致外部存储/OAuth/TOTP 无法解密。"
echo "注意：MinIO 为运行中快照，恢复时以数据库为准校验对象一致性。"
