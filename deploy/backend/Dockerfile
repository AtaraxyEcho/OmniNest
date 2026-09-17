FROM eclipse-temurin:21-jre

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY omninest-app/target/omninest-app-*.jar app.jar

# 镜像默认生产 profile；开发对照构建可用 --build-arg OMNINEST_PROFILE=dev 覆盖。
ARG OMNINEST_PROFILE=prod
ENV OMNINEST_PROFILE=${OMNINEST_PROFILE} \
    OMNINEST_ROLE=api \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=70.0"
EXPOSE 8080

# JAVA_OPTS 可由 Compose 按角色覆盖，堆上限随容器内存而不是宿主机。
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -Duser.timezone=Asia/Shanghai -jar /app/app.jar"]
