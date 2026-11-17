#!/bin/sh
set -eu

/opt/omninest/validate-config.sh
/opt/omninest/render-config.sh
nginx -t

if [ "${1:-}" = "nginx" ]; then
    /opt/omninest/watch-certificates.sh &
fi

exec "$@"
