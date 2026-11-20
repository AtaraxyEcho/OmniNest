FROM eclipse-temurin:25-jre

# curl 供容器 healthcheck 使用；ffmpeg 供探测/转码。
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# 非 root 运行；预建并授权应用需写入的目录（命名卷首次挂载继承镜像内属主）。
RUN groupadd --system omninest && \
    useradd --system --gid omninest --home-dir /app --shell /usr/sbin/nologin omninest && \
    mkdir -p /app/logs /app/aot \
        /var/lib/omninest/geonames \
        /tmp/omninest-probe /tmp/omninest-processing/transcode \
        /mnt/local /mnt/imports /mnt/local-media && \
    chown -R omninest:omninest /app /var/lib/omninest /tmp/omninest-probe \
        /tmp/omninest-processing /mnt

WORKDIR /app
COPY --chown=omninest:omninest omninest-app/target/omninest-app-*.jar app.jar

# 展开为普通 classpath：AOT cache 无法归档嵌套 jar，直接对 fat jar 建缓存只剩三分之一收益。
# 展开后立即算 classpath 指纹，entrypoint 用它匹配同版本的 cache。
RUN java -Djarmode=tools -jar /app/app.jar extract --destination /app/application && \
    rm -f /app/app.jar && \
    test -f /app/application/app.jar && \
    sha256sum /app/application/app.jar /app/application/lib/*.jar | sha256sum | cut -c1-16 \
        > /app/application/.classpath-fingerprint && \
    chown -R omninest:omninest /app/application

# 镜像默认生产 profile；开发对照构建可用 --build-arg OMNINEST_PROFILE=dev 覆盖。
ARG OMNINEST_PROFILE=prod
ENV OMNINEST_PROFILE=${OMNINEST_PROFILE} \
    OMNINEST_ROLE=api \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=70.0 -XX:+UseCompactObjectHeaders"
EXPOSE 8080

USER omninest

# JAVA_OPTS 可由 Compose 按角色覆盖，堆上限随容器内存而不是宿主机。
# sun.net.inetaddr.ttl 必须作为 JVM 启动参数：InetAddressCachePolicy 在首次解析
# 主机名时就锁定策略，业务代码里再改 Security 属性不保证生效，SSRF 校验后的
# 二次解析窗口随之失去缓存收敛。
# 缓存按 classpath 指纹命名（train-aot-cache.sh 生成），镜像或依赖变化后自动不匹配并回退。
ENTRYPOINT ["sh", "-c", "FP=$(cat /app/application/.classpath-fingerprint); C=$(ls /app/aot/omninest-$FP.aot 2>/dev/null); [ -n \"$C\" ] || echo \"[aot] 未找到匹配当前镜像的缓存，普通启动\" >&2; exec java $JAVA_OPTS ${C:+-XX:AOTCache=$C} -Dsun.net.inetaddr.ttl=60 -Duser.timezone=Asia/Shanghai -jar /app/application/app.jar"]
