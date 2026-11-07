#!/bin/sh
# 在本机构建自建镜像后，将其转运到无法直连 Docker Hub / googleapis 的目标主机：
# docker save | gzip | ssh docker load。目标机已存在相同镜像时 load 幂等（层复用，秒级完成）。
#
# 用法: sh scripts/ship-images.sh <user>@<host> [--key KEY] [--tag TAG] [--minio] [--vision-sidecar] [--dry-run]
#   --key            SSH 私钥路径；缺省走 ssh-agent 或默认密钥
#   --tag            自建镜像标签；缺省读取 ../.env 的 OMNINEST_IMAGE_TAG，再退回 0.1.0
#   --minio          一并转运 MinIO 官方镜像（镜像加速源对部分 RELEASE 标签返回 403 时的绕行）
#   --vision-sidecar 一并转运图像分析侧车镜像（photo-ai profile 依赖它；本机不存在时可省略）
#   --dry-run        只校验并打印将转运的镜像，不实际传输
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

target=""
key=""
tag=""
include_minio=false
include_vision_sidecar=false
dry_run=false
while [ $# -gt 0 ]; do
    case "$1" in
        --key) key="${2:?--key 缺少参数}"; shift 2 ;;
        --tag) tag="${2:?--tag 缺少参数}"; shift 2 ;;
        --minio) include_minio=true; shift ;;
        --vision-sidecar) include_vision_sidecar=true; shift ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help)
            echo "用法: sh scripts/ship-images.sh <user>@<host> [--key KEY] [--tag TAG] [--minio] [--vision-sidecar] [--dry-run]"
            exit 0
            ;;
        -*)
            echo "未知选项: $1" >&2
            exit 2
            ;;
        *)
            if [ -n "$target" ]; then
                echo "只能指定一个目标主机" >&2
                exit 2
            fi
            target="$1"
            shift
            ;;
    esac
done
if [ -z "$target" ]; then
    echo "用法: sh scripts/ship-images.sh <user>@<host> [--key KEY] [--tag TAG] [--minio] [--vision-sidecar] [--dry-run]" >&2
    exit 2
fi

read_env_value() {
    # .env 可能在 Windows 上编辑过：CRLF 会让读出的值末尾带 \r，
    # 拼出的镜像名 docker 一定找不到。
    sed -n "s/^$1=//p" "$SCRIPT_DIR/../.env" 2>/dev/null | tail -n 1 | tr -d '\r'
}
if [ -z "$tag" ]; then
    tag="$(read_env_value OMNINEST_IMAGE_TAG)"
    tag="${tag:-0.1.0}"
fi

# 镜像名与 docker-compose.yml 的 ${OMNINEST_*_IMAGE:-默认值} 同口径：
# 管理员自定义仓库前缀后，硬编码名称会指向根本不存在的镜像。
backend_image="$(read_env_value OMNINEST_BACKEND_IMAGE)"
nginx_image="$(read_env_value OMNINEST_NGINX_IMAGE)"
netease_image="$(read_env_value OMNINEST_NETEASE_IMAGE)"
sidecar_image="$(read_env_value OMNINEST_VISION_SIDECAR_IMAGE)"
backend_image="${backend_image:-omninest/backend}"
nginx_image="${nginx_image:-omninest/nginx}"
netease_image="${netease_image:-omninest-netease-music-api}"
sidecar_image="${sidecar_image:-omninest-vision-sidecar}"

images="${backend_image}:${tag} ${nginx_image}:${tag} ${netease_image}:${tag}"
if [ "$include_vision_sidecar" = "true" ]; then
    images="$images ${sidecar_image}:${tag}"
elif docker image inspect "${sidecar_image}:${tag}" >/dev/null 2>&1; then
    # 显式开关优先；未指定时只要本机存在该镜像就一并转运，
    # 避免离线目标机启用 photo-ai profile 时才发现缺少侧车镜像。
    images="$images ${sidecar_image}:${tag}"
fi
if [ "$include_minio" = "true" ]; then
    minio_image="$(grep -oE 'minio/minio:[A-Za-z0-9._-]+' "$SCRIPT_DIR/../docker-compose.yml" | head -n 1)"
    if [ -z "$minio_image" ]; then
        echo "无法从 docker-compose.yml 解析 MinIO 镜像引用" >&2
        exit 1
    fi
    images="$images $minio_image"
fi

for image in $images; do
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "本机缺少镜像: $image（先在本机构建或拉取后再转运）" >&2
        exit 1
    fi
done

echo "转运目标: ${target}"
echo "镜像清单: $(echo $images)"
if [ "$dry_run" = "true" ]; then
    echo "dry-run 结束，未传输。"
    exit 0
fi

# POSIX sh 没有 pipefail：`docker save` 中途失败（磁盘满、守护进程异常）时，
# 管道右端仍可能以 0 结束并打印"转运完成"。用状态文件取回左端真实退出码。
status_file="${TMPDIR:-/tmp}/omninest-ship-images.$$.status"
rm -f "$status_file"
set +e
if [ -n "$key" ]; then
    { docker save $images; echo $? > "$status_file"; } \
        | gzip | ssh -i "$key" "$target" 'gunzip | docker load'
    transfer_status=$?
else
    { docker save $images; echo $? > "$status_file"; } \
        | gzip | ssh "$target" 'gunzip | docker load'
    transfer_status=$?
fi
set -e
save_status="$(cat "$status_file" 2>/dev/null || echo 1)"
rm -f "$status_file"
if [ "$save_status" != "0" ]; then
    echo "错误: docker save 失败（退出码 ${save_status}），目标机镜像不完整" >&2
    exit 1
fi
if [ "$transfer_status" != "0" ]; then
    echo "错误: 传输或目标机 docker load 失败（退出码 ${transfer_status}）" >&2
    exit 1
fi
echo "转运完成。"
