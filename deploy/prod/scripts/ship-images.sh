#!/bin/sh
# 在本机构建自建镜像后，将其转运到无法直连 Docker Hub / googleapis 的目标主机：
# docker save | gzip | ssh docker load。目标机已存在相同镜像时 load 幂等（层复用，秒级完成）。
#
# 用法: sh scripts/ship-images.sh <user>@<host> [--key KEY] [--tag TAG] [--minio] [--dry-run]
#   --key      SSH 私钥路径；缺省走 ssh-agent 或默认密钥
#   --tag      自建镜像标签；缺省读取 ../.env 的 OMNINEST_IMAGE_TAG，再退回 0.1.0
#   --minio    一并转运 MinIO 官方镜像（镜像加速源对部分 RELEASE 标签返回 403 时的绕行）
#   --dry-run  只校验并打印将转运的镜像，不实际传输
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

target=""
key=""
tag=""
include_minio=false
dry_run=false
while [ $# -gt 0 ]; do
    case "$1" in
        --key) key="${2:?--key 缺少参数}"; shift 2 ;;
        --tag) tag="${2:?--tag 缺少参数}"; shift 2 ;;
        --minio) include_minio=true; shift ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help)
            echo "用法: sh scripts/ship-images.sh <user>@<host> [--key KEY] [--tag TAG] [--minio] [--dry-run]"
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
    echo "用法: sh scripts/ship-images.sh <user>@<host> [--key KEY] [--tag TAG] [--minio] [--dry-run]" >&2
    exit 2
fi

read_env_value() {
    sed -n "s/^$1=//p" "$SCRIPT_DIR/../.env" 2>/dev/null | tail -n 1
}
if [ -z "$tag" ]; then
    tag="$(read_env_value OMNINEST_IMAGE_TAG)"
    tag="${tag:-0.1.0}"
fi

images="omninest/backend:${tag} omninest/nginx:${tag} omninest-netease-music-api:${tag}"
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

if [ -n "$key" ]; then
    docker save $images | gzip | ssh -i "$key" "$target" 'gunzip | docker load'
else
    docker save $images | gzip | ssh "$target" 'gunzip | docker load'
fi
echo "转运完成。"
