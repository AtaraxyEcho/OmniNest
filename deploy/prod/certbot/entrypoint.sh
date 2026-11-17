#!/bin/sh
set -eu

https_enabled="${OMNINEST_HTTPS_ENABLED:-false}"
public_host="${OMNINEST_PUBLIC_HOST:-localhost}"
http_port="${OMNINEST_PUBLIC_HTTP_PORT:-80}"
identifier_type="${CERTBOT_IDENTIFIER_TYPE:-domain}"
certificate_name="${CERTBOT_CERT_NAME:-omninest}"
email="${CERTBOT_EMAIL:-}"
staging="${CERTBOT_STAGING:-false}"
renew_interval="${CERTBOT_RENEW_INTERVAL_SECONDS:-43200}"
retry_interval="${CERTBOT_RETRY_INTERVAL_SECONDS:-900}"

validate_boolean() {
    name="$1"
    value="$2"
    case "$value" in
        true|false)
            ;;
        *)
            echo "${name} 只能是 true 或 false" >&2
            exit 1
            ;;
    esac
}

validate_interval() {
    name="$1"
    value="$2"
    case "$value" in
        ''|*[!0-9]*)
            echo "${name} 必须是正整数" >&2
            exit 1
            ;;
    esac
    if [ "$value" -lt 300 ]; then
        echo "${name} 不能小于 300 秒" >&2
        exit 1
    fi
}

validate_boolean OMNINEST_HTTPS_ENABLED "$https_enabled"
validate_boolean CERTBOT_STAGING "$staging"
validate_interval CERTBOT_RENEW_INTERVAL_SECONDS "$renew_interval"
validate_interval CERTBOT_RETRY_INTERVAL_SECONDS "$retry_interval"

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
if [ "$https_enabled" = "true" ] && [ "$http_port" != "80" ]; then
    echo "HTTPS 模式使用 HTTP-01 时，OMNINEST_PUBLIC_HTTP_PORT 必须为 80" >&2
    exit 1
fi

case "$identifier_type" in
    domain|ipv4)
        ;;
    *)
        echo "CERTBOT_IDENTIFIER_TYPE 只能是 domain 或 ipv4" >&2
        exit 1
        ;;
esac

case "$public_host" in
    ''|.*|*.|*[!A-Za-z0-9.-]*)
        echo "OMNINEST_PUBLIC_HOST 必须是有效域名或 IPv4 地址" >&2
        exit 1
        ;;
esac
case "$certificate_name" in
    ''|*[!A-Za-z0-9._-]*)
        echo "CERTBOT_CERT_NAME 包含非法字符" >&2
        exit 1
        ;;
esac
is_ipv4() {
    candidate="$1"
    case "$candidate" in
        ''|.*|*.|*[!0-9.]*)
            return 1
            ;;
    esac
    previous_ifs="$IFS"
    IFS='.'
    set -- $candidate
    IFS="$previous_ifs"
    [ "$#" -eq 4 ] || return 1
    for octet in "$@"; do
        case "$octet" in
            ''|*[!0-9]*)
                return 1
                ;;
        esac
        [ "${#octet}" -le 3 ] || return 1
        [ "$octet" -le 255 ] || return 1
    done
}

if [ "$identifier_type" = "ipv4" ] && ! is_ipv4 "$public_host"; then
    echo "IPv4 证书模式要求 OMNINEST_PUBLIC_HOST 使用有效 IPv4 地址" >&2
    exit 1
fi
if [ "$identifier_type" = "domain" ] && is_ipv4 "$public_host"; then
    echo "IPv4 地址必须使用 CERTBOT_IDENTIFIER_TYPE=ipv4" >&2
    exit 1
fi

certificate_directory="/etc/letsencrypt/live/${certificate_name}"

request_certificate() {
    set -- certonly \
        --webroot \
        --webroot-path /var/www/certbot \
        --cert-name "$certificate_name" \
        --agree-tos \
        --non-interactive \
        --keep-until-expiring

    if [ -n "$email" ]; then
        set -- "$@" --email "$email"
    else
        set -- "$@" --register-unsafely-without-email
    fi
    if [ "$staging" = "true" ]; then
        set -- "$@" --staging
    fi
    if [ "$identifier_type" = "ipv4" ]; then
        set -- "$@" --preferred-profile shortlived --ip-address "$public_host"
    else
        set -- "$@" --domains "$public_host"
    fi

    certbot "$@"
}

case "${1:-watch}" in
    request-once)
        request_certificate
        exit 0
        ;;
    renew-once)
        certbot renew \
            --cert-name "$certificate_name" \
            --webroot \
            --webroot-path /var/www/certbot
        exit 0
        ;;
    watch)
        ;;
    *)
        echo "仅支持 watch、request-once 或 renew-once" >&2
        exit 1
        ;;
esac

while true; do
    if [ "$https_enabled" != "true" ]; then
        sleep "$renew_interval"
        continue
    fi

    if [ ! -s "${certificate_directory}/fullchain.pem" ] || [ ! -s "${certificate_directory}/privkey.pem" ]; then
        if request_certificate; then
            sleep "$renew_interval"
        else
            sleep "$retry_interval"
        fi
        continue
    fi

    if certbot renew \
        --cert-name "$certificate_name" \
        --webroot \
        --webroot-path /var/www/certbot \
        --quiet; then
        sleep "$renew_interval"
    else
        echo "Certbot 续期失败，将在 ${retry_interval} 秒后重试" >&2
        sleep "$retry_interval"
    fi
done
