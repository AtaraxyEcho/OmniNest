# OmniNest Backend

OmniNest Backend 是统一的服务端入口，负责 REST API、身份认证、权限校验、文件能力、影视/音乐/相册/阅读业务、后台任务和系统管理。它采用模块化单体结构，同一套代码按 API、Worker、Scheduler 运行角色承担不同职责，不将业务模块拆成相互独立的微服务。

根目录产品概览见 [../README.md](../README.md)，英文版见 [../README.en.md](../README.en.md)，Flutter 客户端见 [../frontend/README.md](../frontend/README.md)。

## 服务职责

- 为 Web、Android、Windows 客户端提供统一 REST API 与实时连接。
- 从 JWT `sub` 映射当前用户，并执行资源所有权、分享权限、角色和权限编码校验。
- 通过 File 模块统一处理内容 Provider、上传下载、Range 读取、版本、回收站和物理存储生命周期。
- 为 Movies、Music、Photos 和 Reader 提供媒体元数据、播放/阅读进度、导入和解析能力。
- 将索引、缩略图、内容解析、媒体探测、安全扫描等可持续任务落库后投递到 RabbitMQ，支持状态查询、重试和死信记录。
- 提供配置、通知、操作审计、会话、监控和管理接口。

## 日志目录

后端应用日志**统一写入模块根目录下的 `logs/`**，不要落在 `backend/` 源码根或其他随意路径：

| 项 | 说明 |
| --- | --- |
| 默认路径 | `backend/logs/omninest.log`（相对启动时的工作目录） |
| 环境变量 | `OMNINEST_LOG_PATH`（见 `backend/.env` / `.env.example`） |
| 容器部署 | Compose 可通过 `OMNINEST_LOG_PATH` 指到容器内固定路径 |

本地 Maven / 测试产生的 `*.log`、`boot-*.out/err` 等也应放到 `backend/logs/`。该目录已在 `.gitignore` 中忽略，不会提交到仓库。

## 技术基线

| 层次 | 技术 |
| --- | --- |
| 语言与构建 | Java 21、Maven |
| 应用框架 | Spring Boot 4.0.x、Spring Web MVC、Spring Security |
| 数据访问 | Spring Data JPA、Hibernate、Flyway、PostgreSQL |
| 后台任务 | Spring AMQP、RabbitMQ、Redis |
| 内容与媒体 | MinIO SDK、受控 Storage Provider、Apache Tika |
| 搜索 | Lucene 嵌入式索引 |
| 接口文档 | SpringDoc OpenAPI |

## 运行角色

| 角色 | 职责 |
| --- | --- |
| `api` | 对外提供 REST API、认证授权、文件和媒体访问、任务查询及实时连接 |
| `worker` | 消费 RabbitMQ 后台任务，执行索引、导入、解析、缩略图、媒体和安全处理 |
| `scheduler` | 执行清理、恢复、重试、保留策略和定时调度 |

通过 `OMNINEST_ROLE` 选择运行角色（api/worker/scheduler），Spring Profile（`OMNINEST_PROFILE`）只决定 dev/prod 配置集。开发环境可以使用 API 进程承载部分 Reader 漫画消费逻辑；生产环境按部署编排拆分运行角色，但仍使用同一个应用镜像。裸机直跑生产时必须设置 `OMNINEST_PROFILE=prod`——默认 dev 配置集会开放 Swagger 与 actuator 细节端点。

## 模块结构

| 模块 | 责任 |
| --- | --- |
| `omninest-common` | 公共响应、异常、基础模型和跨模块通用能力 |
| `omninest-infrastructure` | 数据库、缓存、消息、存储、搜索和运行时基础设施 |
| `omninest-system` | 用户、角色、权限、配置、通知、任务、审计和系统状态 |
| `omninest-file` | FileNode、内容 Provider、上传下载、版本、回收站和物理存储生命周期 |
| `omninest-media` | Movies、Music、Photos、Reader 和其他媒体领域服务与元数据 |
| `omninest-worker` | 后台消费者、任务执行与重试编排 |
| `omninest-app` | Spring Boot 启动入口、HTTP API、运行配置和迁移资源 |

## API 概览

所有业务 REST 接口使用 `/api/v1` 前缀，写接口返回业务对象或 `taskId`，错误响应包含稳定业务错误码。下面列出主要接口组，完整参数以 OpenAPI 为准。

| 接口组 | 典型路径 | 能力 |
| --- | --- | --- |
| 认证与安装 | `/api/v1/auth/*`、`/api/v1/setup/*` | 登录、注册、刷新 Token、安装状态和首个超级管理员初始化 |
| 当前用户 | `/api/v1/me`、`/api/v1/preferences/*` | 个人资料、密码、头像、会话和个人偏好 |
| 文件与搜索 | `/api/v1/files/*`、`/api/v1/search` | 文件列表、上传下载、预览、回收站、搜索和索引重建 |
| 媒体业务 | `/api/v1/photos/*`、`/api/v1/video/*`、`/api/v1/music/*`、`/api/v1/reader/*` | 相册、影视、音乐、书籍/漫画的内容访问和业务操作 |
| 后台任务 | `/api/v1/tasks/*` | 任务状态、重试、死信查询和失败任务处理 |
| 管理中心 | `/api/v1/admin/*` | 用户、角色权限、配置、日志、会话、监控、存储和媒体扫描 |
| 同步与天气 | `/api/v1/sync/*`、`/api/v1/weather/*` | 增量同步、同步游标和当前版本保留的天气能力 |

本地启动后可访问：

- OpenAPI JSON：`http://localhost:8080/api-docs`
- Swagger UI：`http://localhost:8080/swagger-ui.html`

## 角色与权限

内置角色：`SUPER_ADMIN`（全量）、`ADMIN`（用户/任务/媒体库管理，无系统配置写）、`MEMBER`（个人空间默认）、`GUEST`（有限只读）。注册默认 `MEMBER`。

| 能力域 | 权限码 | 说明 |
| --- | --- | --- |
| 个人文件 | `file:read` / `file:write` | 文件、分享、离线下载、外部存储 |
| 个人媒体 | `media:read` / `media:write` | 影视、音乐、阅读（本人及可见共享） |
| 服务器媒体库 | `media:library:manage` | 影视库来源、扫描授权、库级元数据 |
| 照片 | `photo:read` / `photo:write` / `photo:admin` | 个人相册 / 全站扫描与重生成 |
| 任务 | `task:read` / `task:admin` | 本人任务 / 全站与死信 |
| 系统 | `system:config:*` / `system:user:*` | 配置与用户管理 |

要点：

- 接口以权限码 `@PreAuthorize` 为主，不按角色名硬编码；自定义角色可持管理码进入 `/admin`。
- 本人任务：`GET /tasks` 全类型；影视进度：`GET /video/tasks` 仅影视任务类型白名单。
- 任务重试：本人 `POST /tasks/{id}/retry`（仅 `FAILED`）；死信 `POST /tasks/dlq/{id}/retry` 需 `system:config:manage`。
- 本人任务 DTO 默认不返回失败堆栈摘要；`result` 保留业务字段。

## 数据与存储方案

| 组件 | 保存或提供的内容 |
| --- | --- |
| PostgreSQL | 用户、角色权限、配置、任务、通知、媒体元数据、内容引用和派生状态 |
| MinIO | 默认托管的原始文件、海报、背景图、缩略图、字幕和其他派生资产；Bucket 默认私有 |
| Storage Provider | File 模块统一执行权限预检、流式读取、Range 读取、staging 和 Provider 能力判断 |
| `LOCAL_FILESYSTEM` | 管理员登记的只读影视来源；只保存受控 `mountKey`，不暴露宿主机绝对路径 |
| RabbitMQ | 需要跨请求执行、进度跟踪、失败重试、恢复或调度的后台任务 |
| Redis | 缓存、短期状态、限流和并发控制 |
| Lucene | 可重建的嵌入式搜索索引 |

业务模块不得直接操作 MinIO Client、Rclone、宿主机绝对路径或底层 `Path`。本地影视来源默认只读，不提供重命名、移动、删除、复制、分享、版本和离线下载语义；显式导入为受管内容后才具备托管存储能力。大型文件、媒体探测和派生输出必须使用流式或后台任务路径。

## 安装与配置

### 前置依赖

- JDK 21、Maven 3.9 或兼容版本。
- Docker Desktop 与 Docker Compose v2，用于启动开发依赖。
- PostgreSQL、Redis、RabbitMQ 和 MinIO；可直接使用 [开发编排](../deploy/README.md)。
- 若启用图像分析，需要同时配置并启动 [ai-sidecar](../deploy/ai-sidecar/README.md)。

### 创建本地配置

```bash
cd backend
cp .env.example .env
```

`application.yml` 通过 `optional:file:.env[.properties]` 加载当前工作目录下的 `.env`，因此使用该文件启动时应保持当前目录为 `backend`。完整变量模板以 [`backend/.env.example`](.env.example) 为准，真实凭据不得提交。

常用变量如下：

| 变量 | 用途 | 本地常用值 |
| --- | --- | --- |
| `OMNINEST_PROFILE` | Spring 配置环境 | `dev` |
| `OMNINEST_ROLE` | 进程角色 | `api` |
| `OMNINEST_SERVER_PORT` | HTTP 端口 | `8080` |
| `OMNINEST_DB_URL`、`OMNINEST_DB_USER`、`OMNINEST_DB_PASSWORD` | PostgreSQL 连接 | `localhost:5432` 上的开发数据库 |
| `OMNINEST_REDIS_HOST` | Redis 地址 | `localhost` |
| `OMNINEST_RABBITMQ_HOST`、`OMNINEST_RABBITMQ_USER`、`OMNINEST_RABBITMQ_PASSWORD` | RabbitMQ 连接 | `localhost` 与模板默认账号 |
| `OMNINEST_MINIO_ENDPOINT`、`OMNINEST_MINIO_ACCESS_KEY`、`OMNINEST_MINIO_SECRET_KEY` | MinIO 连接 | `http://localhost:9000` 与开发账号 |
| `OMNINEST_SECURITY_JWT_SECRET` | 本地 JWT 签名密钥 | 仅使用随机开发值 |
| `OMNINEST_LOCAL_MEDIA_ROOT` | 本地影视只读根目录 | 项目外受控目录 |
| `OMNINEST_PHOTO_AI_ENDPOINT`、`OMNINEST_AI_SIDECAR_SECRET` | 图像分析 Sidecar 地址与共享密钥 | 按本地编排配置 |

开发依赖从项目根目录启动：

```bash
cd ..
cp deploy/dev/.env.example deploy/dev/.env
docker compose --env-file deploy/dev/.env -f deploy/dev/docker-compose.yml up -d
cd backend
```

Compose 的环境文件只服务于 Compose 插值，不会自动注入后端裸进程；后端仍读取 `backend/.env`。

## 启动方式

开发 API 进程：

```bash
cd backend
mvn -pl omninest-app spring-boot:run -Dspring-boot.run.profiles=dev
```

构建应用及其模块：

```bash
mvn -q -pl omninest-app -am -DskipTests package
```

生产环境使用 [部署指南](../deploy/README.md) 和对应 Docker Compose 运行 API、Worker、Scheduler。不同运行角色共享同一个代码库和应用镜像，通过 `OMNINEST_ROLE` 区分启动职责。

### 静态分享页（webapp）

dev Profile 通过 `OMNINEST_WEBAPP_DIR`（默认 `./webapp`）托管静态资源，供 `/share/{token}` 转发到 `share.html`。

- **唯一运行时目录**：`backend/webapp/`（相对 `cd backend` 的工作目录）。
- **源文件**：`frontend/web/share.html`（gitignore 忽略 `**/webapp/`，需本地同步）。
- 同步示例：

  ```bash
  cp ../frontend/web/share.html webapp/share.html
  # 或完整 SPA
  cp -r ../frontend/build/web/* webapp/
  ```

- 生产由 Nginx 托管 Flutter Web，后端不必挂 webapp。

首次启动空数据库时，Flyway 执行当前基线迁移 `V001__init_schema.sql` 和 `V002__builtin_catalog.sql`。这是运行时初始化的一部分，首个超级管理员仍通过安装向导创建。

## 测试与验证

常规后端变更在 `backend` 目录执行：

```bash
mvn -q test
git diff --check
```

涉及数据库、权限、任务、存储、安全或消息投递时，应补充对应的单元测试或 Testcontainers 集成测试。需要 Docker 的集成测试必须确认 PostgreSQL、RabbitMQ、Redis 和 MinIO 可用；未执行的验证项应在交付说明中明确列出。

## 相关入口

- [根目录项目总览](../README.md)
- [前端开发指南](../frontend/README.md)
- [部署指南](../deploy/README.md)
- [Photos 图像分析侧车](../deploy/ai-sidecar/README.md)
- [英文后端指南](README.en.md)
