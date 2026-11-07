#!/bin/sh
set -eu

if [ "${OMNINEST_HTTPS_ENABLED:-false}" != "true" ]; then
    exit 0
fi

public_host="${OMNINEST_PUBLIC_HOST:-localhost}"
http_port="${OMNINEST_PUBLIC_HTTP_PORT:-80}"
https_port="${OMNINEST_PUBLIC_HTTPS_PORT:-443}"
minio_port="${OMNINEST_PUBLIC_MINIO_PORT:-9000}"
allowed_origins="${OMNINEST_SECURITY_ALLOWED_ORIGINS:-}"
setup_web_base_url="${OMNINEST_SETUP_WEB_BASE_URL:-}"
minio_public_endpoint="${OMNINEST_MINIO_PUBLIC_ENDPOINT:-}"
web_base_href="${OMNINEST_WEB_BASE_HREF:-/}"

# 站点子路径前缀：根部署为空串，子路径部署为去掉尾部斜杠的 "/omninest"。
case "$web_base_href" in
    /)
        web_base_path=""
        ;;
    /*/)
        web_base_path="${web_base_href%/}"
        ;;
    *)
        echo "OMNINEST_WEB_BASE_HREF 必须是 / 或形如 /omninest/ 的绝对路径" >&2
        exit 1
        ;;
esac

case "$http_port" in
    ''|*[!0-9]*)
        echo "OMNINEST_PUBLIC_HTTP_PORT 必须是有效端口" >&2
        exit 1
        ;;
esac
if [ "$http_port" -lt 1 ] || [ "$http_port" -gt 65535 ]; then
    echo "OMNINEST_PUBLIC_HTTP_PORT 必须位于 1 到 65535" >&2
    exit 1
fi
if [ "$http_port" != "80" ]; then
    echo "HTTPS 模式使用 HTTP-01 时，OMNINEST_PUBLIC_HTTP_PORT 必须为 80" >&2
    exit 1
fi

if [ "$https_port" = "443" ]; then
    public_origin="https://${public_host}"
else
    public_origin="https://${public_host}:${https_port}"
fi
minio_origin="https://${public_host}:${minio_port}"

origin_configured=false
previous_ifs="$IFS"
IFS=','
for origin in $allowed_origins; do
    trimmed_origin="$(printf '%s' "$origin" | tr -d '[:space:]')"
    if [ "$trimmed_origin" = "$public_origin" ]; then
        origin_configured=true
        break
    fi
done
IFS="$previous_ifs"

if [ "$origin_configured" != "true" ]; then
    echo "HTTPS 模式要求 OMNINEST_SECURITY_ALLOWED_ORIGINS 包含 ${public_origin}" >&2
    exit 1
fi
# 安装向导、网盘 OAuth 回调与分享链接都是「基础地址 + /#/...」拼出来的，
# 子路径部署时基础地址必须带上站点前缀，否则重定向会跳回根路径。
expected_setup_base_url="${public_origin}${web_base_path}"
actual_setup_base_url="$(printf '%s' "$setup_web_base_url" | sed 's:/*$::')"
if [ "$actual_setup_base_url" != "$expected_setup_base_url" ]; then
    echo "HTTPS 模式要求 OMNINEST_SETUP_WEB_BASE_URL=${expected_setup_base_url}" >&2
    exit 1
fi
if [ "$minio_public_endpoint" != "$minio_origin" ]; then
    echo "HTTPS 模式要求 OMNINEST_MINIO_PUBLIC_ENDPOINT=${minio_origin}" >&2
    exit 1
fi
