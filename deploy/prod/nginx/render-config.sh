#!/bin/sh
set -eu

https_enabled="${OMNINEST_HTTPS_ENABLED:-false}"
public_host="${OMNINEST_PUBLIC_HOST:-localhost}"
https_port="${OMNINEST_PUBLIC_HTTPS_PORT:-443}"
certificate_name="${CERTBOT_CERT_NAME:-omninest}"
web_base_href="${OMNINEST_WEB_BASE_HREF:-/}"

case "$https_enabled" in
    true|false)
        ;;
    *)
        echo "OMNINEST_HTTPS_ENABLED 只能是 true 或 false" >&2
        exit 1
        ;;
esac

case "$web_base_href" in
    /*/) : ;;
    *)
        echo "OMNINEST_WEB_BASE_HREF 必须形如 / 或 /omninest/" >&2
        exit 1
        ;;
esac
if printf '%s' "$web_base_href" | grep -Eq '(^|/)\.\.(/|$)|\s'; then
    echo "OMNINEST_WEB_BASE_HREF 不得包含 .. 或空白字符" >&2
    exit 1
fi

if ! printf '%s' "$public_host" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'; then
    echo "OMNINEST_PUBLIC_HOST 必须是有效域名或 IPv4 地址" >&2
    exit 1
fi

if ! printf '%s' "$certificate_name" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
    echo "CERTBOT_CERT_NAME 包含非法字符" >&2
    exit 1
fi

case "$https_port" in
    ''|*[!0-9]*)
        echo "OMNINEST_PUBLIC_HTTPS_PORT 必须是有效端口" >&2
        exit 1
        ;;
esac
if [ "$https_port" -lt 1 ] || [ "$https_port" -gt 65535 ]; then
    echo "OMNINEST_PUBLIC_HTTPS_PORT 必须位于 1 到 65535" >&2
    exit 1
fi

if [ "$https_port" = "443" ]; then
    https_authority="$public_host"
else
    https_authority="${public_host}:${https_port}"
fi

certificate_directory="/etc/letsencrypt/live/${certificate_name}"
if [ "$https_enabled" = "false" ]; then
    template="/opt/omninest/templates/http.conf.template"
elif [ -s "${certificate_directory}/fullchain.pem" ] && [ -s "${certificate_directory}/privkey.pem" ]; then
    template="/opt/omninest/templates/https.conf.template"
else
    template="/opt/omninest/templates/https-bootstrap.conf.template"
fi

export OMNINEST_PUBLIC_HOST="$public_host"
export OMNINEST_HTTPS_REDIRECT_AUTHORITY="$https_authority"
export CERTBOT_CERT_NAME="$certificate_name"
export OMNINEST_WEB_BASE_PATH="$web_base_href"

envsubst '${OMNINEST_PUBLIC_HOST} ${OMNINEST_HTTPS_REDIRECT_AUTHORITY} ${CERTBOT_CERT_NAME} ${OMNINEST_WEB_BASE_PATH}' \
    < "$template" \
    > /etc/nginx/conf.d/default.conf
