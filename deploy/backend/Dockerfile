FROM eclipse-temurin:21-jre

# curl 供容器 healthcheck 使用；ffmpeg 供探测/转码。
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# 非 root 运行；预建并授权应用需写入的目录（命名卷首次挂载继承镜像内属主）。
RUN groupadd --system omninest && \
    useradd --system --gid omninest --home-dir /app --shell /usr/sbin/nologin omninest && \
    mkdir -p /app/logs /var/lib/omninest/lucene /var/lib/omninest/lucene-photo \
        /mnt/local /mnt/imports /mnt/local-media /downloads && \
    chown -R omninest:omninest /app /var/lib/omninest /mnt /downloads

WORKDIR /app
COPY --chown=omninest:omninest omninest-app/target/omninest-app-*.jar app.jar

# 镜像默认生产 profile；开发对照构建可用 --build-arg OMNINEST_PROFILE=dev 覆盖。
ARG OMNINEST_PROFILE=prod
ENV OMNINEST_PROFILE=${OMNINEST_PROFILE} \
    OMNINEST_ROLE=api \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=70.0"
EXPOSE 8080

USER omninest

# JAVA_OPTS 可由 Compose 按角色覆盖，堆上限随容器内存而不是宿主机。
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -Duser.timezone=Asia/Shanghai -jar /app/app.jar"]
