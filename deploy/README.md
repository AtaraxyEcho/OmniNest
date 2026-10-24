# OmniNest 部署

部署配置按运行环境分开维护：

- `dev/` 只启动本地开发依赖，后端和 Flutter 由开发工具直接运行。
- `prod/` 启动 Nginx、API、Worker、Scheduler、Certbot 和生产依赖。
- 每个环境内的组件目录保存对应镜像定义或运行脚本，打开目录即可查看全部 Docker 配置。

组件镜像定义统一放在 deploy 根目录：`vision-sidecar/`（含侧车源码）、`backend/`、
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

镜像定义统一位于 deploy 根目录的 `vision-sidecar/`、`backend/`、`netease-api/`。
开发编排默认只构建图像分析侧车和网易云 API，后端仍由 Maven 或 IDE 运行；图像分析侧车
继续使用 `vision-sidecar/` 作为源码构建上下文。

### 基线重写后重建开发库

项目未发布期间，`backend/omninest-app/src/main/resources/db/migration/V001__init_schema.sql` 与
`V002__builtin_catalog.sql` 是唯一基线：结构变更直接改这两份文件，不新增递增迁移。
只要文件内容与已建库时不一致，后端启动就会被 Flyway 拒绝（`validate-on-migrate` 默认为真，
报 `Migration checksum mismatch for migration version 001`，并列出库内与本地两个校验和）。

不要用 `flyway repair` 绕过：repair 只改写历史表里的校验和，不会补上基线新增的列与内置目录行，
结果是启动成功、第一次读写该字段时再报缺列，比启动失败更难定位。开发库直接重建：

```bash
# 先停后端进程。历史表 flyway_schema_history 与业务表同处 omni 模式，整模式级联删除一并清掉。
docker exec omninest-postgres psql -U omninest -d omninest -c 'DROP SCHEMA omni CASCADE;'
```

随后起后端，Flyway 会按当前基线重建 `omni` 模式、内置目录与默认配置。Redis、RabbitMQ 与
Lucene 索引本就是可重建数据，不随库清理。生产环境在未发布阶段同样按基线重建；一旦进入
已发布且环境执行过迁移的阶段，基线不可改写，必须改用递增迁移（见根目录 `AGENTS.md`）。

若必须保留已有开发数据，可先备份，再执行 `deploy/db/upgrade-baseline-20261024.sql`
补齐本次基线新增的列、时间戳类型与默认值，最后用 Flyway `repair` 对齐校验和。
**repair 不能单独使用**：它只改历史表校验和，不补结构；只在结构已经补齐后执行。

重建只清数据库，MinIO 卷里的对象字节仍在：新库没有任何 `file_objects` 行，桶内**全部**对象
都会被原件桶孤儿审计判成无主字节。重设基线之后不得开启
`omninest.storage.user-file-orphan-scan.delete-enabled`，否则等价于清空用户文件。

若确需保留开发库数据，必须先手工执行本次基线涉及的全部结构 DDL，再修正
`omni.flyway_schema_history` 中对应版本的校验和；只 repair 校验和、不补齐列、索引或删除表
仍被禁止。图像分析链路从 `StandardAnalyzer` 切换到 `SmartChineseAnalyzer` 后，旧照片索引
不能可靠命中中文 `aiLabels` 与 `ocrText` 字段；后端升级启动后还需调用管理端“重建搜索索引”一次。

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

**子路径部署**：默认挂在站点根。若必须由反代挂在子路径（如 `https://nas.example.com/omninest/`），构建镜像前设
`OMNINEST_WEB_BASE_HREF=/omninest/`（值必须以 `/` 开头并以 `/` 结尾，否则构建失败）。镜像会按该 base-href 构建
Flutter Web，并把产物摆到 `html/<前缀>/` 下；Canvaskit 与 SQLite WASM/Worker 都按页面基准解析，前端使用 hash
路由，子路径下的深链不需要服务端 rewrite。镜像内置的 nginx 模板同样读取该变量：入口与 Service Worker 的
no-cache/安全响应头、SPA 回退路径都按同一前缀生成；变量为 `/` 时与根部署完全一致。

同一前缀会带进接口地址：Web 端从页面 `<base href>` 推导，API 变成 `https://nas.example.com/omninest/api/v1`、
WS 变成 `https://nas.example.com/omninest/ws`；显式设置 `OMNINEST_API_BASE_URL`/`OMNINEST_WS_BASE_URL` 或管理端
服务器配置时以配置为准，桌面端从 API 地址反推前缀，分享链接基址也按「前缀 + api/v1」剥离。因此代理需要
**静态资源原样保留前缀、接口剥掉前缀**转发给后端（后端 `context-path` 保持 `/`，桌面与 Android 直连不受影响）：

```nginx
location /omninest/api/ { proxy_pass http://127.0.0.1:8080/api/; }   # 剥掉 /omninest
location /omninest/ws {
  proxy_pass http://127.0.0.1:8080/ws;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
}
location /omninest/ {
  root /usr/share/nginx/html;
  try_files $uri /omninest/index.html;
}
```

回退只写 `$uri`，不要再加 `$uri/`：构建产物里存在 `css/`、`js/`、`assets/`、`canvaskit/` 等真实目录，`$uri/` 会优先命中目录索引，而 `autoindex` 关闭时这类请求直接 403，不再回到主文档。`deploy/prod/nginx/templates` 同时把 `flutter_bootstrap.js` 与 `version.json` 设为 `no-cache`——它们决定客户端加载哪一份构建产物，缓存住就会在发版后继续跑旧版。

若反代本来就在站点根暴露 `/api/v1` 与 `/ws`，则把 API/WS 地址显式配成根路径即可，不必让接口跟前缀。

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
不要同时开启 ClamAV（约 1.5G）或图像分析侧车（lightweight 约 200M，RAM++ 需 2.5G+）。

**首次启动建议串行**：先 `docker compose up -d backend-api`，待
`/api/v1/setup/status` 返回 200 后再启动 worker、scheduler，避免三角色同时
类加载触发 cgroup OOM。小内存机上不要在 Compose 默认 JAVA_OPTS 里设置过小的
`MaxMetaspaceSize`（Boot4 启动期 Metaspace 峰值明显高于 Boot3）。

**单实例覆盖**见下文「4C4G 单实例」：只起 API + 内嵌 worker 时，API 建议
`mem_limit` 约 896m、堆 ≤384m；仍不要设置过小的 `MaxMetaspaceSize`。

Photos 图像分析侧车使用 CPU 推理，无需 GPU；仅在 `COMPOSE_PROFILES=photo-ai`
时启动。RapidOCR 模型随镜像内置，视觉档的 `mobileclip2_s0_vision_fp32.onnx` 与
`policy_text_embeds.npz` 不会自动下载，必须按 `vision-sidecar/DEPLOYMENT.md` 预先放入
`omninest-ai-models` 卷。侧车就绪后还要在配置中心把 `photo.ai.enabled` 置为 `true`：
基线内置值为 `false`，图像分析在管理员显式开启前不会对任何照片执行。

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

**Profile 服务必须显式选中**：`certbot`、`clamav`、`photo-ai` 挂在 Compose profile 下。
profile 是所有 Compose 子命令共同的筛选条件——`up -d` 没带上某个已启用的 profile 时，
该服务既不创建也不重建，已存在的容器会保留它当初加入的网络，静默停在当前声明的拓扑之外；
而它仍挂在旧网络上时，Compose 也不会删除那张网络。优先在 `.env` 用
`COMPOSE_PROFILES=certbot,clamav,photo-ai` 按实际启用的组合声明（该变量对每个子命令都生效，
比逐条命令补 `--profile` 更不容易漏），执行前用 `docker compose config --services`
核对本次真正会操作到的服务清单。

### 出网执行体的网络分区

两张网的成员表（prod 与 dev 同形状）：

| 网络 | 成员 | internal | 为什么 |
| :-- | :-- | :-- | :-- |
| `egress` | `rclone`，prod 还含 backend 三种运行角色 | 否 | 它必须出公网（外部存储读写），但不能碰数据面 |
| `default` | 其余全部服务 | 否 | 数据面与宿主回环发布 |

独立 ffmpeg 容器已移除：探测、转码与抽帧都在 backend 容器本地执行，
媒体内容内嵌的远程引用由强制 demuxer 与 `protocol_whitelist` 收口，
不再依赖一张 internal 网兜底。探测与转码临时目录分别挂到
`omninest-probe-cache` / `omninest-transcode-cache` 命名卷，避免数 GB 视频写满 OverlayFS。

`internal: true` 与发布端口互斥（internal 网络上的容器发布端口不生效，`Ports` 为空、宿主连不上），
所以 `egress` 故意不设 `internal`；只挂 internal 网的服务一旦加上 `ports:` 会静默失效，
`ComposeNetworkTopologyTest` 对这条有专门断言。

网络分区不依赖 `OMNINEST_DOCKER_SUBNET` 的取值，但改动子网时必须同步
`OMNINEST_DOCKER_DYNAMIC_IP_RANGE` 与 nginx 固定地址；`OMNINEST_EGRESS_SUBNET`
不得与宿主局域网重叠。成员表由 `ComposeNetworkTopologyTest` 逐字钉住，
新增服务时该测试会要求同时决定它进哪张网。

应用后核对容器实际所在网络，不依赖 compose 文件推断：

```bash
docker compose ps --format '{{.Name}}' | xargs -r docker inspect --format '{{.Name}} {{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
```

### 4C4G 单实例（可选覆盖）

默认仍是 **三角色**（API / Worker / Scheduler 各一进程），适合多人使用与故障隔离。

内存紧张的个人自托管（4C4G）可叠加 `docker-compose.single.yml`：同一镜像只跑
一个 `backend-api`，并设置 `OMNINEST_RUNTIME_EMBEDDED_WORKER_ENABLED=true` 与
`OMNINEST_RUNTIME_EMBEDDED_SCHEDULER_ENABLED=true` 在 API 进程内嵌 worker 与
调度器；独立 worker/scheduler 不会启动。

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

### 受限网络部署（镜像转运）

目标主机无法直连 Docker Hub / storage.googleapis.com 时（国内服务器常见），自建镜像
与部分官方镜像在目标机拉不下来，改用「有网工作机构建 + SSH 转运」：

1. **在工作机构建镜像**。需要代理时给 docker build 挂上代理环境（BuildKit 会自动
   转发到构建容器内；Docker Desktop 下代理地址写 `http://host.docker.internal:<端口>`
   而非 127.0.0.1）。nginx 镜像内的 Flutter 工具链下载约 1GB，务必使用 Dockerfile 内
   已有的 retry/断点续传参数重试，勿删。

   ```bash
   cd ../../backend && mvn -q -pl omninest-app -am -DskipTests package && cd ../deploy/prod
   docker compose build
   ```

2. **转运到目标机**。`scripts/ship-images.sh` 打包三个自建镜像经
   `docker save | gzip | ssh docker load` 注入；目标机已有相同镜像时幂等（层复用，
   秒级完成）。镜像加速源对 MinIO 的部分 RELEASE 标签返回 403 时加 `--minio` 一并转运：

   ```bash
   sh scripts/ship-images.sh root@<目标机> --key ~/.ssh/id_rsa --minio
   # 先核对清单不传输
   sh scripts/ship-images.sh root@<目标机> --dry-run
   ```

3. **目标机只需从镜像加速源拉基础镜像**（postgres / redis / rabbitmq / minio /
   ffmpeg / rclone / certbot），并在 `deploy/prod` 目标机侧执行 `up -d`。
   目标机 Docker 需配置 `registry-mirrors`（daemon.json）。

**项目名隔离**：同一台主机复用过 OmniNest 部署时，旧项目会残留 `omninest_*` 数据卷和
固定网段 `172.30.0.0/24` 的网络，与新部署直接撞名（卷被复用导致旧凭据生效、网络子网
冲突拒绝创建）。干净做法是在目标机 `.env` 追加一行独立项目名，`up`、`exec` 与
`scripts/backup.sh` / `restore.sh` 随之全部一致：

```bash
echo "COMPOSE_PROJECT_NAME=omninest-test" >> .env
```

不想保留旧数据时再显式 `docker volume rm` / `docker network rm` 清理残留。

### MinIO 社区版 EOL 与版本钉扎

MinIO 社区版仓库已于 2026-04 归档只读，官方社区文档重定向至 AiStor 企业版。最后一个
版本 `RELEASE.2025-10-15T17-29-55Z`（修复 Service Accounts / STS 会话策略绕过 CVE）
不再提供预构建容器镜像，官方要求克隆源码自行构建。OmniNest 仅使用单 root 凭据 +
S3 API + 预签名 URL，不使用 STS 与 Service Accounts，该 CVE 不影响当前用法。

Compose 钉扎的 `RELEASE.2025-04-22T22-12-26Z` 是本项目部署环境实测可得的最后一个
预构建镜像（2026-10 验证：Docker Hub 直连、daocloud / rainbond / 1ms.run /
dockerproxy / atomhub 镜像源与 quay.io 均无法取得更新版本；部分源对 minio/minio
整仓库 403，转运走 `scripts/ship-images.sh --minio`）。后续两个方向择机决策：按官方
指引源码自建终版镜像，或评估迁移到其他 S3 兼容存储。MinIO 数据卷只支持向前升级、
不支持降级，任何版本变更前必须先执行 `scripts/backup.sh`。

### Docker 部署下的 ClamAV 主机

配置中心键 `clamav.host`（默认 `localhost`）**优先于** 环境变量
`OMNINEST_CLAMAV_HOST`。在 Compose 中扫描服务名为 `clamav` 时，必须在首次
安装后于管理端或 SQL 将配置改为服务名，否则上传会因「扫描不可用」被隔离
（fail-closed）：

```sql
UPDATE omni.config_entries SET config_value = 'clamav' WHERE config_key = 'clamav.host';
```

并清除运行时缓存（如 `omninest:config:clamav.host`）或重启 API/Worker。

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

本地影视目录以只读方式同时挂载给 backend 三种运行角色。Rclone 和
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

- `backup.sh` 产物附带 `SHA256SUMS` 校验和；`restore.sh` 恢复前自动校验，不匹配
  直接中止，无校验文件的旧版本备份在告警后继续。
- 建议宿主 crontab 每日执行 `backup.sh`，并将备份目录同步到异地存储。
- MinIO 卷为运行中快照（crash-consistent）；恢复后以数据库记录为准核对
  派生资产，缺失的缩略图等可重建资产会由系统自动补齐。
- Redis、RabbitMQ、Lucene 索引均为可重建数据，不在备份范围。
- 跨版本恢复前先阅读根仓库发布说明，确认 Flyway 基线兼容。

## 密钥轮换

生产 `.env` 中的密钥不得使用示例值（`CHANGE_ME_*` / `change-me-*` / `minioadmin` / `omninest` /
`secret` 等）。`deploy/prod` Compose 对缺失变量直接失败，后端 `prod` Profile 由
`JwtSecretValidator` 与 `ProductionSecretsValidator` 拒绝空白或文档示例默认值。

| 密钥 | 环境变量 | 轮换步骤 |
|------|----------|----------|
| JWT 签名密钥 | `OMNINEST_SECURITY_JWT_SECRET` | 生成 ≥32 字节随机值（如 `openssl rand -base64 48`）→ 写入 `.env` → 重启 api/worker/scheduler。旧 access/refresh 令牌立即失效，客户端需重新登录；两步验证备份码的摘要由该密钥派生的 HMAC 计算，轮换后旧备份码失效，需在管理台用户页对该用户执行「重置两步验证」后重新开启。 |
| 凭据加密 KEK | `OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY` | `openssl rand -base64 32` → 写入 `.env` → 重启后端。已加密的外部存储凭据需按密钥版本流程重加密后再切换；未配置时保存加密凭据会直接报错。两步验证 TOTP 秘钥也用该 KEK 落库，直接换密钥会使已注册的两步验证不可用，同样在管理台用户页重置后重新开启（等价端点 `DELETE /api/v1/admin/users/{userId}/2fa`）。 |
| 首次安装令牌 | `OMNINEST_SETUP_TOKEN` | 安装完成后保持 `OMNINEST_SETUP_ENABLED=false`；若需再次安装，生成新 ≥32 字节令牌并同步写入 `.env` 后重启。 |
| PostgreSQL | `POSTGRES_PASSWORD` | 在 PG 内 `ALTER USER` 后更新 `.env` 与应用连接串，重启后端与 postgres。 |
| RabbitMQ | `RABBITMQ_DEFAULT_PASS` | 管理台或 `rabbitmqctl change_password` 后更新 `.env`，重启 rabbitmq 与后端。 |
| Redis | `REDIS_PASSWORD` | 更新 redis 配置与 `.env`，重启 redis 与后端。 |
| MinIO | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` | 更新 MinIO 凭据与 `.env`，重启 minio 与后端。 |
| Rclone RC | `RCLONE_RC_PASS` | 更新 `.env` 后重启 rclone 与后端；口令仅经环境注入，不写入 command 行。 |
| Vision Sidecar | `OMNINEST_AI_SIDECAR_SECRET` | 更新 `.env` 后重启 vision-sidecar 与后端（启用 photo-ai 时）。 |

轮换后请确认：`docker compose config` 不再出现示例默认值；`ps`/`docker inspect` 中不残留旧口令明文。

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
- **离线下载队列清理**：2026-10-18 起离线下载功能与 Aria2 容器整体移除，已在跑的
  broker 不会自动删除 `omni.task.offline-download`。确认无积压消息后手工执行
  `docker exec omninest-rabbitmq rabbitmqctl delete_queue omni.task.offline-download`；
  只删这一条队列，不要按前缀批量清理，避免误删 DLX 邻居。
- **入口协议**：公网部署**必须**设置 `OMNINEST_HTTPS_ENABLED=true`（compose 已强制显式设置）；
  保持 false 时登录密码、JWT 与刷新 Cookie 全部明文传输。
- **MinIO 发布面**：托管桶保持私有，下载只签发短期签名 URL；经 Nginx 发布时不开放
  桶的匿名读，客户端仅通过 `OMNINEST_MINIO_PUBLIC_ENDPOINT` 访问。
- **对象存储孤儿审计**：派生桶与原件桶各有一个扫描器（`DerivedAssetOrphanScanner`、
  `UserFileOrphanScanner`），只在 Scheduler 角色跑，判据都是"对象键没有 `file_objects` 行"，
  原件桶额外排除在途入库记录持有的目标键。年龄宽限不同：派生桶 24h（可重建），原件桶 30d
  （不可重建，须大于过期会话 7d 与隔离保留期 7d 之和再加余量）。两个桶的
  `delete-enabled` 都默认 false，先出报表再决定开删。
- **原件桶审计的已知缺口**：分片上传的字节只落在隔离桶，原件桶不会出现未完成分片；
  隔离桶侧的存储兜底需要对象存储端口暴露"列举未完成分片上传"，当前未暴露，
  依赖 `FileCleanupService` 按会话行取消与 `FileQuarantineReaperScheduler` 按保留期删除。
- **备份脚本**：见上文「备份与恢复」章节，宿主 crontab 每日执行。

