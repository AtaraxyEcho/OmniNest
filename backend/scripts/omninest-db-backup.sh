#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly ENV_FILE="${OMNINEST_BACKUP_ENV_FILE:-/etc/omninest/backup.env}"

fail() {
    printf '错误: %s\n' "$1" >&2
    exit 1
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

prune_backups() {
    local now index file modified age_days checksum_file
    local -a files=()
    now="$(date +%s)"
    mapfile -d '' files < <(
        find "$BACKUP_DIR" -maxdepth 1 -type f -name 'omninest-*.dump' -print0 | sort -z -r
    )
    for index in "${!files[@]}"; do
        file="${files[$index]}"
        modified="$(stat -c '%Y' "$file")"
        age_days=$(( (now - modified) / 86400 ))
        if (( index >= MAX_RETAINED || (index >= MIN_RETAINED && age_days > RETENTION_DAYS) )); then
            checksum_file="${file}.sha256"
            rm -f -- "$file" "$checksum_file"
            printf '已清理过期备份: %s\n' "$(basename "$file")"
        fi
    done
}

load_environment

: "${PGDATABASE:?PGDATABASE 未配置}"
: "${PGUSER:?PGUSER 未配置}"

PGHOST="${PGHOST:-/var/run/postgresql}"
PGPORT="${PGPORT:-5432}"
PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/omninest/postgresql}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
MIN_RETAINED="${MIN_RETAINED:-5}"
MAX_RETAINED="${MAX_RETAINED:-30}"
MIN_FREE_KIB="${MIN_FREE_KIB:-1048576}"
PG_DUMP_BIN="${PG_DUMP_BIN:-pg_dump}"
PG_RESTORE_BIN="${PG_RESTORE_BIN:-pg_restore}"
PG_CONTAINER="${PG_CONTAINER:-}"
PG_CONTAINER_SOCKET_DIR="${PG_CONTAINER_SOCKET_DIR:-/var/run/postgresql}"

[[ -z "${PGPASSWORD:-}" ]] || fail "禁止使用 PGPASSWORD，请改用权限为 0600 的 PGPASSFILE"
export PGHOST PGPORT PGDATABASE PGUSER PGCONNECT_TIMEOUT
if [[ -n "${PGPASSFILE:-}" ]]; then
    export PGPASSFILE
fi

[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || fail "RETENTION_DAYS 必须是非负整数"
[[ "$MIN_RETAINED" =~ ^[1-9][0-9]*$ ]] || fail "MIN_RETAINED 必须是正整数"
[[ "$MAX_RETAINED" =~ ^[1-9][0-9]*$ ]] || fail "MAX_RETAINED 必须是正整数"
[[ "$MIN_FREE_KIB" =~ ^[0-9]+$ ]] || fail "MIN_FREE_KIB 必须是非负整数"
(( MIN_RETAINED <= MAX_RETAINED )) || fail "MIN_RETAINED 不得大于 MAX_RETAINED"

if [[ -n "$PG_CONTAINER" ]]; then
    [[ "$PG_CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail "PG_CONTAINER 名称包含非法字符"
    require_command docker
    docker inspect "$PG_CONTAINER" >/dev/null 2>&1 || fail "PostgreSQL 容器不存在: $PG_CONTAINER"
    docker exec "$PG_CONTAINER" "$PG_DUMP_BIN" --version >/dev/null
    docker exec "$PG_CONTAINER" "$PG_RESTORE_BIN" --version >/dev/null
else
    require_command "$PG_DUMP_BIN"
    require_command "$PG_RESTORE_BIN"
fi
require_command sha256sum
require_command flock
require_command find
require_command sort
require_command stat

install -d -m 0700 "$BACKUP_DIR"
exec 9<"$BACKUP_DIR"
flock -n 9 || fail "已有备份或恢复任务正在执行"

available_kib="$(df -Pk "$BACKUP_DIR" | awk 'NR == 2 {print $4}')"
[[ "$available_kib" =~ ^[0-9]+$ ]] || fail "无法读取备份目录剩余空间"
(( available_kib >= MIN_FREE_KIB )) || fail "备份目录剩余空间低于安全阈值"

timestamp="$(date -u +'%Y%m%dT%H%M%SZ')"
host_label="$(hostname -s | tr -cd 'A-Za-z0-9._-')"
host_label="${host_label:-server}"
base_name="omninest-${timestamp}-${host_label}-${BASHPID}.dump"
final_path="${BACKUP_DIR}/${base_name}"
partial_path="${final_path}.partial"
checksum_path="${final_path}.sha256"
checksum_partial="${checksum_path}.partial"

cleanup() {
    rm -f -- "$partial_path" "$checksum_partial"
}
trap cleanup EXIT HUP INT TERM
rm -f -- "$partial_path" "$checksum_partial"

printf '开始备份数据库 %s 到 %s\n' "$PGDATABASE" "$final_path"
if [[ -n "$PG_CONTAINER" ]]; then
    docker exec -e PGCONNECT_TIMEOUT="$PGCONNECT_TIMEOUT" "$PG_CONTAINER" "$PG_DUMP_BIN" \
        --host="$PG_CONTAINER_SOCKET_DIR" \
        --username="$PGUSER" \
        --dbname="$PGDATABASE" \
        --format=custom \
        --compress=6 \
        --no-owner \
        --no-privileges >"$partial_path"
else
    PGCONNECT_TIMEOUT="$PGCONNECT_TIMEOUT" "$PG_DUMP_BIN" \
        --host="$PGHOST" \
        --port="$PGPORT" \
        --username="$PGUSER" \
        --dbname="$PGDATABASE" \
        --format=custom \
        --compress=6 \
        --no-owner \
        --no-privileges \
        --file="$partial_path"
fi

[[ -s "$partial_path" ]] || fail "pg_dump 未生成有效备份文件"
if [[ -n "$PG_CONTAINER" ]]; then
    docker exec -i "$PG_CONTAINER" "$PG_RESTORE_BIN" --list <"$partial_path" >/dev/null
else
    "$PG_RESTORE_BIN" --list "$partial_path" >/dev/null
fi
checksum="$(sha256sum "$partial_path" | awk '{print $1}')"
printf '%s  %s\n' "$checksum" "$base_name" >"$checksum_partial"
mv -- "$partial_path" "$final_path"
mv -- "$checksum_partial" "$checksum_path"
chmod 0600 "$final_path" "$checksum_path"

prune_backups
trap - EXIT HUP INT TERM
printf '数据库备份完成: %s\n' "$final_path"
