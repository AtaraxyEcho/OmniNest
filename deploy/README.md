# OmniNest 部署

部署配置按运行环境分开维护：

- `dev/` 只启动本地开发依赖，后端和 Flutter 由开发工具直接运行。
- `prod/` 启动 Nginx、API、Worker、Scheduler、Certbot 和生产依赖。
- 每个环境内的组件目录保存对应镜像定义或运行脚本，打开目录即可查看全部 Docker 配置。

组件镜像定义统一放在 deploy 根目录：`ai-sidecar/`（含侧车源码）、`backend/`、
`netease-api/`；nginx、certbot 等生产专属组件位于 `prod/`。dev/prod Compose 以
项目 `backend/` 源码目录与上述镜像定义目录作为构建上下文。
backend 镜像的公共构建逻辑只有一份；backend 的默认 Profile 等环境差异通过构建参数或运行时环境变量注入，不在镜像定义中分叉。

## 开发环境

开发编排只启动 OmniNest 的本地依赖。后端使用 Maven 或 IDE 运行，Flutter 使用对应开发工具运行。

从 `deploy` 目录执行：

```bash
cd dev
cp .env.example .env
docker compose up -d
```

后端裸进程变量从 `backend/.env` 读取，模板位于 `backend/.env.example`。Compose 的
`.env` 不会自动注入后端裸进程。各 `.env.example` 模板（本目录 `dev/`、`prod/` 与
`backend/`）均提供英文版 `.env.en.example`，变量一致，仅注释语言不同。

镜像定义统一位于 deploy 根目录的 `ai-sidecar/`、`backend/`、`netease-api/`。
开发编排默认只构建图像分析侧车和网易云 API，后端仍由 Maven 或 IDE 运行；图像分析侧车
继续使用 `ai-sidecar/` 作为源码构建上下文。

### ClamAV 可选开关

ClamAV 是可选服务，通过 `.env` 的 `COMPOSE_PROFILES=clamav` 控制：
保留该行时 `docker compose up -d` 会启动 ClamAV 并启用病毒扫描；注释掉该行则
不启动容器。两套模式必须与后端同步：

- 带病毒扫描（默认）：`COMPOSE_PROFILES=clamav`，且 `backend/.env` 保持
  `OMNINEST_CLAMAV_ENABLED=true`。
- 不带病毒扫描：注释 `COMPOSE_PROFILES=clamav`，并把 `backend/.env` 改为
  `OMNINEST_CLAMAV_ENABLED=false`，可释放约 1 GB 级内存。

容器与后端开关必须一致：容器未启动而后端仍启用扫描时，安全检查按 fail-closed
处理，上传会因“ClamAV 安全扫描不可用”被拒绝。

## 生产环境

生产编排使用同一 backend 镜像启动 API、Worker 和 Scheduler。Nginx 构建并
托管 Flutter Web，统一代理 API、WebSocket 和 MinIO。网易云 API 与图片分析侧车
只在 Compose 内部网络提供服务，不直接暴露宿主机端口。

`prod/nginx/`、`prod/certbot/` 包含生产专属的镜像定义与脚本；backend、netease-api
与图像分析侧车的镜像定义统一位于 deploy 根目录。Compose 从项目源码构建镜像，不复制业务源码到部署目录。

### 资源要求与安全扫描

**日志路径**：后端应用日志默认写在容器内 `logs/omninest.log`（`OMNINEST_LOG_PATH`，相对 `/app`）。本地开发对应 `backend/logs/`；测试与构建日志请写入各模块自己的 `logs/`，勿放在源码根目录。

| 场景 | 建议 |
|------|------|
| **4C4G 个人自托管（默认）** | 不启用 ClamAV / photo-ai；`.env` 保持 `OMNINEST_CLAMAV_ENABLED=false` |
| **公网生产 / 4C8G+** | `COMPOSE_PROFILES=clamav` 且 `OMNINEST_CLAMAV_ENABLED=true`；可按需 `photo-ai` |

关闭病毒扫描时必须同时：不启动 clamav 容器、后端 `OMNINEST_CLAMAV_ENABLED=false`，
并确认配置中心 `clamav.enabled` 为 false（安装向导后若仍为 true 会在配置中心覆盖环境变量，需在管理端或 SQL 改写）：

```sql
UPDATE omni.config_entries SET config_value = 'false' WHERE config_key = 'clamav.enabled';
```

容器与后端开关必须一致：容器未启动而后端仍启用扫描时，安全检查按 fail-closed
处理，上传会因“ClamAV 安全扫描不可用”被拒绝。

**4C4G 建议内存边界（约，Spring Boot 4 + Hibernate 7 实测）**：Postgres 768M、
API/Worker 各 768M（堆 ≤320M，**不要设置 MaxMetaspaceSize**）、Scheduler 512M
（堆 ≤192M）、Rabbit/MinIO 各约 320M、Redis ≤192M、其余辅件合计约 400M。
不要同时开启 ClamAV（约 1.5G）或 InsightFace 侧车（约 768M+）。

**首次启动建议串行**：先 `docker compose up -d backend-api`，待
`/api/v1/setup/status` 返回 200 后再启动 worker、scheduler，避免三角色同时
类加载触发 cgroup OOM。小内存机上不要在 Compose 默认 JAVA_OPTS 里设置过小的
`MaxMetaspaceSize`（Boot4 启动期 Metaspace 峰值明显高于 Boot3）。

**单实例覆盖**见下文「4C4G 单实例」：只起 API + 内嵌 worker 时，API 建议
`mem_limit` 约 896m、堆 ≤384m；仍不要设置过小的 `MaxMetaspaceSize`。

Photos 图像分析侧车使用 CPU 推理，无需 GPU；仅在 `COMPOSE_PROFILES=photo-ai`
时启动。模型首次启动自动下载，预留最多 10 分钟启动窗口。

### 构建与启动

以下命令在 `deploy/prod` 目录执行。backend 镜像使用已经由 Maven 生成的应用 JAR：

```bash
cd ../../backend
mvn -q -pl omninest-app -am -DskipTests package

cd ../deploy/prod
cp .env.example .env
docker compose build
docker compose up -d
```

生产部署前必须重点修改 `.env` 中的数据库、RabbitMQ、MinIO、Rclone、JWT、
图片分析侧车凭据，以及公开地址。模板保留默认值用于单机 HTTP 验证，不会通过
Compose 的 required 语法阻止启动。

### 4C4G 单实例（可选覆盖）

默认仍是 **三角色**（API / Worker / Scheduler 各一进程），适合多人使用与故障隔离。

内存紧张的个人自托管（4C4G）可叠加 `docker-compose.single.yml`：同一镜像只跑
一个 `backend-api`，并设置 `OMNINEST_RUNTIME_EMBEDDED_WORKER_ENABLED=true` 在 API
进程内嵌 worker；独立 worker/scheduler 不会启动。

```bash
cd deploy/prod
docker compose -f docker-compose.yml -f docker-compose.single.yml up -d
# 恢复三角色
docker compose -f docker-compose.yml up -d
```

| 形态 | Java 进程 | 适用 |
|------|-----------|------|
| 默认三角色 | 3 | 多用户、后台任务较重 |
| single.yml 单实例 | 1 | 4C4G 个人、任务很少 |

单实例时 API 需同时承担后台任务，override 默认将 API `mem_limit` 提到约 896m
（可用 `BACKEND_API_MEM_LIMIT_SINGLE` 覆盖）。重扫描/转码仍建议三角色或升配。

VM 实测（仅 OmniNest、关闭 ClamAV）：三角色 available 约 1.2Gi；单实例 available
约 2.0Gi，探针 `/api/v1/setup/status`、`/health`、`/actuator/health` 均为 200。

### Docker 部署下的 ClamAV 主机

配置中心键 `clamav.host`（默认 `localhost`）**优先于** 环境变量
`OMNINEST_CLAMAV_HOST`。在 Compose 中扫描服务名为 `clamav` 时，必须在首次
安装后于管理端或 SQL 将配置改为服务名，否则上传会因「扫描不可用」被隔离
（fail-closed）：

```sql
UPDATE omni.config_entries SET config_value = 'clamav' WHERE config_key = 'clamav.host';
```

并清除运行时缓存（如 `omninest:config:clamav.host`）或重启 API/Worker。

### 离线下载与 Aria2 路径（Docker）

后端 `OMNINEST_ARIA2_DOWNLOAD_ROOT` 必须是 **Aria2 容器内路径**（如 `/downloads`，
对应 dev 编排挂载 `../../.omninest/aria2:/downloads`）。在 **Windows 宿主机** 上若
Java `Path` 把 `/downloads` 归一成 `D:\\downloads`，Aria2 会因权限/路径不存在失败
（日志：`Failed to make the directory D:\\downloads\\...`）。Linux/macOS 宿主机无此
问题；Windows 上离线下载与 Docker Aria2 组合需额外映射或改用 Linux 部署路径。

### Cloudflare 管理 HTTPS（无 certbot）

`certbot` 服务挂在 Compose profile **`certbot`** 下，**默认不启动**。

| 场景 | 启动方式 |
|---|---|
| Cloudflare / 其他外部证书 | `docker compose up -d`（不要设 `COMPOSE_PROFILES=certbot`） |
| Let's Encrypt Webroot | `.env` 设 `COMPOSE_PROFILES=certbot` 后 `up -d` |

#### Cloudflare 除「关 certbot」外还需调整

1. **域名与回源**  
   - `OMNINEST_PUBLIC_HOST=<你的域名>`（nginx `server_name`）  
   - DNS 指到源站；Flexible 只回源 80，Full/Full strict 回源 443  

2. **SSL 模式**  
   - **Flexible**：`OMNINEST_HTTPS_ENABLED=false`，源站仅 HTTP  
   - **Full / Full (strict)**：`OMNINEST_HTTPS_ENABLED=true`，并在 Cloudflare 下载 **Origin Certificate**，按固定路径挂到 nginx（与 Let's Encrypt 布局一致）：  
     ```
     ./certs/fullchain.pem → /etc/letsencrypt/live/${CERTBOT_CERT_NAME}/fullchain.pem
     ./certs/privkey.pem   → /etc/letsencrypt/live/${CERTBOT_CERT_NAME}/privkey.pem
     ```
     可用 `docker-compose.override.yml` 只加这两条 `nginx.volumes`，不必整份复制 compose。  
     Full (strict) 更安全；Flexible 仅适合临时/内网演示。

3. **应用侧公开地址**  
   - `OMNINEST_MINIO_PUBLIC_ENDPOINT`：客户端可达的 MinIO 地址（常用 `https://<域名或 CDN>:9000` 或经 CF 代理的域名）  
   - `OMNINEST_SECURITY_ALLOWED_ORIGINS`：`https://<域名>`  
   - 需要分享/外链时同步核对 `OMNINEST_SETUP_WEB_BASE_URL`  

4. **Cloudflare 面板**  
   - 开启 **WebSocket**（`/ws` 实时同步）  
   - 上传大文件注意 CF 上传体积与超时  
   - 若只挂 CF 不开源站 443，保持 Flexible + 仅 80 回源即可  

5. **配置中心**  
   - 安装后核对 `clamav.host=clamav`（见上文），与证书方式无关但影响上传扫描。

示例：`docker-compose.override.yml`（Full / Full strict 挂 Origin 证书，文件可放 `deploy/prod/certs/`）：

```yaml
services:
  nginx:
    volumes:
      - ./certs/fullchain.pem:/etc/letsencrypt/live/${CERTBOT_CERT_NAME:-omninest}/fullchain.pem:ro
      - ./certs/privkey.pem:/etc/letsencrypt/live/${CERTBOT_CERT_NAME:-omninest}/privkey.pem:ro
```

### 公开入口和 HTTPS

`OMNINEST_HTTPS_ENABLED=false` 时，Nginx 在配置的 HTTP 端口提供 Web/API，在 9000
端口代理 MinIO。Spring Boot 和 MinIO 只通过 Docker 内部网络通信；后端调试端口
仅绑定 `127.0.0.1`。

启用当前 Certbot Webroot/HTTP-01 方案时，宿主机 HTTP 入口必须使用 TCP 80，不能将
`OMNINEST_PUBLIC_HTTP_PORT` 改为其他端口。若 80 已被其他服务占用，应让现有公网
Nginx 负责 80/443，并将 ACME 挑战和反向代理按共存方案接入；不要仅修改这个变量
绕过校验。

启用域名 HTTPS 前设置：

```dotenv
OMNINEST_HTTPS_ENABLED=true
OMNINEST_PUBLIC_HOST=omni.example.com
CERTBOT_IDENTIFIER_TYPE=domain
CERTBOT_CERT_NAME=omninest-domain
CERTBOT_EMAIL=admin@example.com
OMNINEST_SECURITY_ALLOWED_ORIGINS=https://omni.example.com
OMNINEST_SETUP_WEB_BASE_URL=https://omni.example.com
OMNINEST_MINIO_PUBLIC_ENDPOINT=https://omni.example.com:9000
```

域名的 A 记录必须指向部署服务器，80、443 和 9000 端口必须可达。Nginx 在证书
尚未签发时只提供 ACME 验证和健康检查，其他请求返回 503；Certbot 签发成功后，
Nginx 会检测证书变化并自动切换到 TLS。Spring Boot 不直接加载证书。

公网 IPv4 证书使用：

```dotenv
OMNINEST_HTTPS_ENABLED=true
OMNINEST_PUBLIC_HOST=203.0.113.10
CERTBOT_IDENTIFIER_TYPE=ipv4
CERTBOT_CERT_NAME=omninest-ip
OMNINEST_SECURITY_ALLOWED_ORIGINS=https://203.0.113.10
OMNINEST_SETUP_WEB_BASE_URL=https://203.0.113.10
OMNINEST_MINIO_PUBLIC_ENDPOINT=https://203.0.113.10:9000
```

IPv4 模式使用 Certbot 5.4 的 `shortlived` Profile，证书有效期很短，因此 Certbot
默认每 12 小时检查续期。该模式只适合能通过公网 ACME 校验的 IPv4，不适用于
`192.168.0.0/16` 等私有地址。正式部署优先使用域名证书。

需要先验证 ACME 流程时可设置 `CERTBOT_STAGING=true`。测试证书不受客户端信任，
切换正式证书时应改用新的 `CERTBOT_CERT_NAME`，避免继续沿用 Staging 的续期配置。

查看签发状态：

```bash
docker compose logs --follow nginx certbot
```

### 从 IPv4 切换到域名

先添加域名 A 记录，然后在旧 IP 入口仍运行时预签域名证书：

```bash
docker compose run --rm \
  -e OMNINEST_PUBLIC_HOST=omni.example.com \
  -e CERTBOT_IDENTIFIER_TYPE=domain \
  -e CERTBOT_CERT_NAME=omninest-domain \
  certbot request-once
```

确认 `omninest-domain` 已签发后，再更新 `.env` 中的公开主机、证书名、CORS、Setup
URL 和 MinIO 公开地址，并执行：

```bash
docker compose up -d --force-recreate nginx certbot backend-api backend-worker backend-scheduler
```

旧 IP 证书仍保留在 Certbot 命名卷中，不会阻塞回滚。短期签名 URL 等待自然过期，
数据库不需要迁移。域名稳定前不启用 HSTS Preload。

### 数据卷与网络

本地影视目录以只读方式同时挂载给 backend 三种运行角色。Rclone、Aria2 和
Lucene 使用命名卷在容器间共享所需内容；PostgreSQL、Redis、RabbitMQ 和 MinIO
数据分别使用独立命名卷。

Nginx 使用固定内部地址作为后端可信代理身份。`OMNINEST_DOCKER_DYNAMIC_IP_RANGE`
必须位于 `OMNINEST_DOCKER_SUBNET` 内，并且不能包含 `OMNINEST_NGINX_INTERNAL_IP`；
默认动态地址池为 `172.30.0.128/25`，因此不会与默认 Nginx 地址 `172.30.0.10` 冲突。

## 备份与恢复

生产数据的备份恢复由脚本承载（在 `deploy/prod` 目录执行）：

```bash
# 备份：PostgreSQL 逻辑备份（custom 格式）+ MinIO 数据卷打包
sh scripts/backup.sh              # 产物在 ./backups/omninest-<时间戳>/
# 恢复：先 docker compose down 停止全部服务，再执行
sh scripts/restore.sh ./backups/omninest-<时间戳>
```

要点：

- 建议宿主 crontab 每日执行 `backup.sh`，并将备份目录同步到异地存储。
- MinIO 卷为运行中快照（crash-consistent）；恢复后以数据库记录为准核对
  派生资产，缺失的缩略图等可重建资产会由系统自动补齐。
- Redis、RabbitMQ、Lucene 索引均为可重建数据，不在备份范围。
- 跨版本恢复前先阅读根仓库发布说明，确认 Flyway 基线兼容。

## 运维备忘

- **ClamAV 扫描时限口径**：代码默认 10s / yml 护栏 120s 仅是回退，权威值是配置中心
  `clamav.timeout-millis`（基线 2,000,000ms 活性护栏）；调整时以后者为准。
- **Prometheus 抓取**：`/actuator/prometheus` 需要 `TOKEN_ACCESS` 权限的 JWT，
  抓取器需带登录令牌访问；该端点不经 Nginx 转发，仅内网可达。
- **裸机部署 profile**：直跑 jar 的生产部署必须设置 `OMNINEST_PROFILE=prod`。
- **RabbitMQ 旧队列清理**：2026-09 队列改名前部署过的环境会残留旧
  `omninest.tasks.*` 交换机/队列。优先在管理界面（127.0.0.1:15672）逐个删除旧条目；
  仅在确认无保留价值时才考虑 `rabbitmqctl` 重置——重置会清空**全部**队列、
  用户与 vhost 定义，属于破坏性操作，必须在停机窗口执行。
- **Aria2 端口**：6888 tcp/udp 是 BT/DHT 监听口（功能必需、默认映射到宿主机），
  公网部署建议用防火墙限制来源网段。
- **备份脚本**：见上文「备份与恢复」章节，宿主 crontab 每日执行。

