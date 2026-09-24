FROM debian:bookworm-slim AS web-builder

ARG FLUTTER_VERSION=3.44.8
ARG FLUTTER_SHA256=672089e001571a9fbb209a495c583580c0c6c73ef98999264ba07fa93ace332d
# 站点基准路径：根部署保持 "/"，反代子路径部署时形如 "/omninest/"。
ARG WEB_BASE_HREF=/

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --location --silent --show-error \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        --output /tmp/flutter.tar.xz \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum --check --strict \
    && tar --extract --xz --file /tmp/flutter.tar.xz --directory /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

WORKDIR /workspace/frontend

COPY frontend/pubspec.yaml frontend/pubspec.lock ./
COPY frontend/ ./
RUN flutter config --no-analytics --enable-web \
    && case "${WEB_BASE_HREF}" in \
           /) : ;; \
           /*/) : ;; \
           *) echo "WEB_BASE_HREF 必须是 / 或形如 /omninest/ 的绝对路径" >&2; exit 1 ;; \
       esac \
    && flutter pub get \
    && flutter build web --release --no-pub --base-href="${WEB_BASE_HREF}" \
    && rm -rf /staged \
    && mkdir -p "/staged${WEB_BASE_HREF}" \
    && cp -a /workspace/frontend/build/web/. "/staged${WEB_BASE_HREF}"

FROM nginx:1.28-alpine

RUN apk add --no-cache gettext

# 产物已按 WEB_BASE_HREF 摆好站点内目录：根部署落在 html/ 下，子路径部署落在
# html/<前缀>/ 下，Nginx 不需要为前缀另写 rewrite（前端为 hash 路由）。
COPY --from=web-builder /staged/ /usr/share/nginx/html/
COPY deploy/prod/nginx/templates/ /opt/omninest/templates/
COPY deploy/prod/nginx/validate-config.sh /opt/omninest/validate-config.sh
COPY deploy/prod/nginx/render-config.sh /opt/omninest/render-config.sh
COPY deploy/prod/nginx/watch-certificates.sh /opt/omninest/watch-certificates.sh
COPY deploy/prod/nginx/entrypoint.sh /opt/omninest/entrypoint.sh

RUN chmod 0755 /opt/omninest/*.sh \
    && rm -f /etc/nginx/conf.d/default.conf

ENTRYPOINT ["/opt/omninest/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
