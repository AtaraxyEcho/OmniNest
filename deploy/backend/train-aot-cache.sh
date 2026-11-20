#!/bin/sh
# 生成 JDK 25 AOT cache（JEP 514/515），供三个角色共用。
#
#   ./deploy/backend/train-aot-cache.sh [prod|single]
#
# 需 PostgreSQL/Redis/RabbitMQ/MinIO 在线。缓存按 classpath 指纹命名，镜像变化后
# 自动不匹配并回退普通启动，重跑本脚本即可恢复。
# 必须复用运行时 JAVA_OPTS：缓存与 UseCompactObjectHeaders、GC 等 flag 绑定。
set -eu

MODE=${1:-prod}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PROD_DIR="$ROOT/deploy/prod"

case "$MODE" in
  prod)
    COMPOSE_ARGS="-f $PROD_DIR/docker-compose.yml"
    ;;
  single)
    COMPOSE_ARGS="-f $PROD_DIR/docker-compose.yml -f $PROD_DIR/docker-compose.single.yml"
    ;;
  *)
    echo "用法: $0 [prod|single]" >&2
    exit 2
    ;;
esac

echo "==> 启动依赖服务并等待健康"
docker compose $COMPOSE_ARGS up -d --wait postgres redis rabbitmq minio

echo "==> 读取镜像 classpath 指纹"
FP=$(docker compose $COMPOSE_ARGS run --rm --no-deps --entrypoint cat \
      backend-api /app/application/.classpath-fingerprint | tr -d '\r\n')
if [ -z "$FP" ]; then
    echo "无法读取 classpath 指纹，镜像可能不是当前版本" >&2
    exit 1
fi
CACHE="/app/aot/omninest-$FP.aot"
echo "    $CACHE"

echo "==> 训练运行（refresh 完成即退出，不写业务数据）"
docker compose $COMPOSE_ARGS run --rm --no-deps \
  -e OMNINEST_ROLE=api \
  backend-api \
  sh -c 'exec java $JAVA_OPTS \
    -XX:AOTCacheOutput="$1" \
    -Dspring.context.exit=onRefresh \
    -Dsun.net.inetaddr.ttl=60 -Duser.timezone=Asia/Shanghai \
    -jar /app/application/app.jar' _ "$CACHE"

echo "==> 校验缓存产物"
docker compose $COMPOSE_ARGS run --rm --no-deps backend-api ls -lh /app/aot/

cat <<EOF

完成。重启后端以加载缓存：
  docker compose $COMPOSE_ARGS up -d --force-recreate backend-api backend-worker backend-scheduler

旧版本的 omninest-*.aot 不会自动清理，按需删除。
EOF
