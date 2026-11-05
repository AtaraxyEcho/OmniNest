#!/bin/sh
# OmniNest 生产数据恢复：将 backup.sh 的产物恢复到当前部署。
# 用法：sh scripts/restore.sh <备份目录>
# 兼容新版加密产物（*.enc）与旧版明文产物（postgres.dump / minio-data.tar.gz）。
# 前置：先 docker compose down 停止全部服务，恢复后 up -d。
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

BACKUP_DIR="${1:?用法: restore.sh <备份目录>}"
COMPOSE_FILE="docker-compose.yml"

ENCRYPTED_BACKUP=false
if [ -f "${BACKUP_DIR}/postgres.dump.enc" ] && [ -f "${BACKUP_DIR}/minio-data.tar.gz.enc" ]; then
    ENCRYPTED_BACKUP=true
elif [ ! -f "${BACKUP_DIR}/postgres.dump" ] || [ ! -f "${BACKUP_DIR}/minio-data.tar.gz" ]; then
    echo "错误: ${BACKUP_DIR} 缺少 postgres.dump(.enc) 或 minio-data.tar.gz(.enc)" >&2
    exit 1
fi

# MANIFEST 记录加密密钥指纹。缺失时无法确认当前 .env 的密钥能否解密数据，
# 恢复后会出现"数据在但外部存储/OAuth/TOTP 全部解不开"的静默故障，因此直接中止。
if [ ! -f "${BACKUP_DIR}/MANIFEST.txt" ]; then
    echo "错误: 备份缺少 MANIFEST.txt，无法校验加密密钥指纹；请使用 backup.sh 生成的完整产物" >&2
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

if [ "${ENCRYPTED_BACKUP}" = "true" ]; then
    if [ -z "${BACKUP_PASSPHRASE}" ]; then
        echo "错误: 加密备份恢复需要配置 OMNINEST_BACKUP_ENCRYPTION_KEY 或 OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY" >&2
        exit 1
    fi
    if ! command -v openssl >/dev/null 2>&1; then
        echo "错误: 宿主机缺少 openssl 命令，无法解密备份" >&2
        exit 1
    fi
    EXPECTED_BACKUP_KEY_SHA256="$(sed -n 's/^backup-key-sha256: //p' "${BACKUP_DIR}/MANIFEST.txt" | head -n 1)"
    CURRENT_BACKUP_KEY_SHA256="$(printf '%s' "${BACKUP_PASSPHRASE}" | sha256sum | cut -d' ' -f1)"
    if [ -z "${EXPECTED_BACKUP_KEY_SHA256}" ]; then
        echo "错误: 加密备份的 MANIFEST 缺少 backup-key-sha256，无法校验解密口令" >&2
        exit 1
    fi
    if [ "${EXPECTED_BACKUP_KEY_SHA256}" != "${CURRENT_BACKUP_KEY_SHA256}" ]; then
        echo "错误: 当前备份解密口令与备份清单不一致，中止恢复以免破坏现有数据" >&2
        exit 1
    fi
    export BACKUP_PASSPHRASE
fi

# 加密密钥指纹必须与备份时一致：密钥不同时外部存储凭据、OAuth 密钥与
# TOTP 秘钥无法解密，恢复出来的数据看似完整但关键功能全部失效。
BACKUP_KEY_SHA256="$(sed -n 's/^credential-key-sha256: //p' "${BACKUP_DIR}/MANIFEST.txt" | head -n 1)"
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
    if [ "${ENCRYPTED_BACKUP}" = "true" ]; then
        enc_archive="${archive}.enc"
        if [ ! -f "${BACKUP_DIR}/${enc_archive}" ]; then
            echo "警告: 备份缺少 ${enc_archive}，跳过 ${volume}" >&2
            return 0
        fi
        docker volume create "${PROJECT_NAME}_${volume}" >/dev/null
        # 解密流直接交给容器内 tar：宿主机不落明文中间文件。
        openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
            -pass env:BACKUP_PASSPHRASE -in "${BACKUP_DIR}/${enc_archive}" \
            | docker run --rm -i -v "${PROJECT_NAME}_${volume}:/data" alpine \
                sh -c 'rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null || true; tar xzf - -C /data'
        return 0
    fi
    if [ ! -f "${BACKUP_DIR}/${archive}" ]; then
        echo "警告: 备份缺少 ${archive}，跳过 ${volume}" >&2
        return 0
    fi
    docker volume create "${PROJECT_NAME}_${volume}" >/dev/null
    docker run --rm \
        -v "${PROJECT_NAME}_${volume}:/data" \
        -v "$(host_pwd "${BACKUP_DIR}"):/backup:ro" alpine \
        sh -c 'rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null || true; tar xzf "/backup/$1" -C /data' -- "${archive}"
}

echo "[1/7] 恢复 MinIO 数据卷..."
restore_volume omninest-minio minio-data.tar.gz

echo "[2/7] 恢复 rclone 配置与本地卷..."
restore_volume omninest-rclone rclone-config.tar.gz
restore_volume omninest-rclone-local rclone-local-data.tar.gz
restore_volume omninest-rclone-imports rclone-imports-data.tar.gz

# 旧备份包不含 lucene-search.tar.gz.enc，restore_volume 会告警跳过，
# 恢复后按启动提示重建索引即可，不需要迁移脚本。
echo "[3/7] 恢复搜索索引卷..."
restore_volume omninest-search lucene-search.tar.gz

echo "[4/7] 启动 PostgreSQL..."
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

echo "[5/7] 重建数据库 ${POSTGRES_DB}..."
# dropdb/recreatedb 需要连接可用；容器内本地信任认证。
# .env 的库名/用户名可能含空格或分号，统一用位置参数传入，禁止拼进 sh -c 脚本。
docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    sh -c 'dropdb --if-exists -U "$1" "$2" && createdb -U "$1" "$2"' -- "${POSTGRES_USER}" "${POSTGRES_DB}"
if [ "${ENCRYPTED_BACKUP}" = "true" ]; then
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
        -pass env:BACKUP_PASSPHRASE -in "${BACKUP_DIR}/postgres.dump.enc" \
        | docker compose -f "${COMPOSE_FILE}" exec -T postgres \
            pg_restore -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --no-owner --no-privileges
else
    docker compose -f "${COMPOSE_FILE}" exec -T postgres \
        pg_restore -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --no-owner --no-privileges \
        < "${BACKUP_DIR}/postgres.dump"
fi

echo "[6/7] 校验备份清单..."
sed -n '1,9p' "${BACKUP_DIR}/MANIFEST.txt"

echo "[7/7] 完成。现在可以 docker compose -f ${COMPOSE_FILE} up -d 启动全部服务。"
echo "提示：恢复后首次启动应用会执行 Flyway 基线校验；如跨版本恢复请先阅读发布说明。"
# 索引卷随库一起恢复；只有旧备份包（不含 lucene-search）才需要重建。
# 索引里的文档以 fileObjectId 为键，节点标识与标题都实时取自数据库，
# 因此短时间的索引落后只会漏结果，不会返回已删除或打不开的文件。
if [ ! -f "${BACKUP_DIR}/lucene-search.tar.gz.enc" ] && [ ! -f "${BACKUP_DIR}/lucene-search.tar.gz" ]; then
    echo "注意：本备份不含 omninest-search 索引卷。"
    echo "      启动后请以管理员调用 POST /api/v1/search/rebuild（子路径部署加 Web 前缀）重建全站索引，"
    echo "      并按返回的 taskId 轮询 /api/v1/tasks/{taskId} 确认完成后再对外提供搜索。"
fi
