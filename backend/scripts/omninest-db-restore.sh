#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly ENV_FILE="${OMNINEST_BACKUP_ENV_FILE:-/etc/omninest/backup.env}"

fail() {
    printf '错误: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf '用法: %s [--verify-only] [--yes] [--target-db 数据库名] 备份文件\n' "$0"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "缺少命令: $1"
}

load_environment() {
    [[ -f "$ENV_FILE" ]] || fail "配置文件不存在: $ENV_FILE"
    local mode owner current_uid
    mode="$(stat -c '%a' "$ENV_FILE")"
    owner="$(stat -c '%u' "$ENV_FILE")"
    current_uid="$(id -u)"
    (( (8#$mode & 8#077) == 0 )) || fail "配置文件不得向组或其他用户开放权限"
    [[ "$owner" == "0" || "$owner" == "$current_uid" ]] || fail "配置文件所有者不合法"

    # 配置文件仅允许由服务器运维账户维护。
    source "$ENV_FILE"
}

verify_only=false
confirmed=false
target_database=""
dump_argument=""

while (( $# > 0 )); do
    case "$1" in
        --verify-only)
            verify_only=true
            shift
            ;;
        --yes)
            confirmed=true
            shift
            ;;
        --target-db)
            (( $# >= 2 )) || fail "--target-db 缺少参数"
            target_database="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --*)
            fail "不支持的参数: $1"
            ;;
        *)
            [[ -z "$dump_argument" ]] || fail "只能指定一个备份文件"
            dump_argument="$1"
            shift
            ;;
    esac
done

[[ -n "$dump_argument" ]] || {
    usage
    exit 2
}

load_environment

: "${PGDATABASE:?PGDATABASE 未配置}"
: "${PGUSER:?PGUSER 未配置}"

PGHOST="${PGHOST:-/var/run/postgresql}"
PGPORT="${PGPORT:-5432}"
PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/omninest/postgresql}"
PG_RESTORE_BIN="${PG_RESTORE_BIN:-pg_restore}"
PSQL_BIN="${PSQL_BIN:-psql}"
PG_CONTAINER="${PG_CONTAINER:-}"
PG_CONTAINER_SOCKET_DIR="${PG_CONTAINER_SOCKET_DIR:-/var/run/postgresql}"
ALLOW_EXTERNAL="${OMNINEST_RESTORE_ALLOW_EXTERNAL:-false}"
target_database="${target_database:-$PGDATABASE}"

[[ -z "${PGPASSWORD:-}" ]] || fail "禁止使用 PGPASSWORD，请改用权限为 0600 的 PGPASSFILE"
export PGHOST PGPORT PGDATABASE PGUSER PGCONNECT_TIMEOUT
if [[ -n "${PGPASSFILE:-}" ]]; then
    export PGPASSFILE
fi

[[ "$target_database" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || fail "目标数据库名包含非法字符"
if [[ -n "$PG_CONTAINER" ]]; then
    [[ "$PG_CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail "PG_CONTAINER 名称包含非法字符"
    require_command docker
    docker inspect "$PG_CONTAINER" >/dev/null 2>&1 || fail "PostgreSQL 容器不存在: $PG_CONTAINER"
    docker exec "$PG_CONTAINER" "$PG_RESTORE_BIN" --version >/dev/null
    docker exec "$PG_CONTAINER" "$PSQL_BIN" --version >/dev/null
else
    require_command "$PG_RESTORE_BIN"
fi
require_command sha256sum
require_command flock
require_command realpath
require_command stat

[[ -d "$BACKUP_DIR" && -r "$BACKUP_DIR" ]] || fail "备份目录不存在或不可读"
exec 9<"$BACKUP_DIR"
flock -n 9 || fail "已有备份或恢复任务正在执行"

backup_root="$(realpath -m "$BACKUP_DIR")"
[[ ! -L "$dump_argument" ]] || fail "不允许通过符号链接恢复"
dump_path="$(realpath -e "$dump_argument")"
if [[ "$ALLOW_EXTERNAL" != "true" && "$dump_path" != "$backup_root"/* ]]; then
    fail "备份文件必须位于 BACKUP_DIR 中"
fi
[[ -f "$dump_path" ]] || fail "备份文件不是普通文件"

checksum_path="${dump_path}.sha256"
[[ -f "$checksum_path" ]] || fail "缺少 SHA-256 校验文件"
[[ ! -L "$checksum_path" ]] || fail "不允许通过符号链接读取校验文件"
expected_checksum="$(awk 'NR == 1 {print $1}' "$checksum_path")"
[[ "$expected_checksum" =~ ^[0-9a-fA-F]{64}$ ]] || fail "SHA-256 校验文件格式不正确"
actual_checksum="$(sha256sum "$dump_path" | awk '{print $1}')"
[[ "$actual_checksum" == "$expected_checksum" ]] || fail "备份文件 SHA-256 校验失败"
if [[ -n "$PG_CONTAINER" ]]; then
    docker exec -i "$PG_CONTAINER" "$PG_RESTORE_BIN" --list <"$dump_path" >/dev/null
else
    "$PG_RESTORE_BIN" --list "$dump_path" >/dev/null
fi
printf '备份文件校验通过: %s\n' "$dump_path"

if [[ "$verify_only" == "true" ]]; then
    exit 0
fi

[[ "$confirmed" == "true" ]] || fail "恢复必须显式传入 --yes"
[[ "${OMNINEST_APPLICATION_STOPPED:-}" == "YES" ]] || fail "必须确认 OmniNest API、Worker 与 Scheduler 已停止"
[[ "${OMNINEST_RESTORE_CONFIRM:-}" == "RESTORE:${target_database}" ]] || \
    fail "必须设置 OMNINEST_RESTORE_CONFIRM=RESTORE:${target_database}"

if [[ -n "$PG_CONTAINER" ]]; then
    active_connections="$(docker exec -e PGCONNECT_TIMEOUT="$PGCONNECT_TIMEOUT" "$PG_CONTAINER" "$PSQL_BIN" \
        --host="$PG_CONTAINER_SOCKET_DIR" \
        --username="$PGUSER" \
        --dbname=postgres \
        --tuples-only \
        --no-align \
        --command="SELECT count(*) FROM pg_stat_activity WHERE datname = '${target_database}' AND pid <> pg_backend_pid();")"
else
    require_command "$PSQL_BIN"
    active_connections="$(PGCONNECT_TIMEOUT="$PGCONNECT_TIMEOUT" "$PSQL_BIN" \
        --host="$PGHOST" \
        --port="$PGPORT" \
        --username="$PGUSER" \
        --dbname=postgres \
        --tuples-only \
        --no-align \
        --command="SELECT count(*) FROM pg_stat_activity WHERE datname = '${target_database}' AND pid <> pg_backend_pid();")"
fi
active_connections="${active_connections//[[:space:]]/}"
[[ "$active_connections" =~ ^[0-9]+$ ]] || fail "无法读取目标数据库活动连接数"
(( active_connections == 0 )) || fail "目标数据库仍有活动连接，拒绝恢复"

printf '开始恢复数据库 %s，当前数据将被替换\n' "$target_database"
if [[ -n "$PG_CONTAINER" ]]; then
    docker exec -i -e PGCONNECT_TIMEOUT="$PGCONNECT_TIMEOUT" "$PG_CONTAINER" "$PG_RESTORE_BIN" \
        --host="$PG_CONTAINER_SOCKET_DIR" \
        --username="$PGUSER" \
        --dbname="$target_database" \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        --single-transaction \
        --exit-on-error <"$dump_path"
else
    PGCONNECT_TIMEOUT="$PGCONNECT_TIMEOUT" "$PG_RESTORE_BIN" \
        --host="$PGHOST" \
        --port="$PGPORT" \
        --username="$PGUSER" \
        --dbname="$target_database" \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        --single-transaction \
        --exit-on-error \
        "$dump_path"
fi
printf '数据库恢复完成: %s\n' "$target_database"
