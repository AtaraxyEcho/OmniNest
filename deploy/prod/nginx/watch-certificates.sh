#!/bin/sh
set -eu

interval="${CERTBOT_RELOAD_INTERVAL_SECONDS:-15}"
case "$interval" in
    ''|*[!0-9]*)
        echo "CERTBOT_RELOAD_INTERVAL_SECONDS 必须是正整数" >&2
        exit 1
        ;;
esac
if [ "$interval" -lt 5 ]; then
    echo "CERTBOT_RELOAD_INTERVAL_SECONDS 不能小于 5 秒" >&2
    exit 1
fi

certificate_name="${CERTBOT_CERT_NAME:-omninest}"
certificate_directory="/etc/letsencrypt/live/${certificate_name}"

certificate_state() {
    if [ "${OMNINEST_HTTPS_ENABLED:-false}" != "true" ]; then
        printf '%s' 'http'
        return
    fi
    if [ ! -s "${certificate_directory}/fullchain.pem" ] || [ ! -s "${certificate_directory}/privkey.pem" ]; then
        printf '%s' 'missing'
        return
    fi
    sha256sum "${certificate_directory}/fullchain.pem" "${certificate_directory}/privkey.pem"
}

previous_state="$(certificate_state)"
while sleep "$interval"; do
    current_state="$(certificate_state)"
    if [ "$current_state" = "$previous_state" ]; then
        continue
    fi
    if /opt/omninest/render-config.sh && nginx -t; then
        nginx -s reload
        previous_state="$current_state"
    fi
done
