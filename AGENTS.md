# OmniNest — Root AGENTS.md

> **Scope**: `/`（仓库全局基线；修改子目录时由工具自动叠加 `/backend/AGENTS.md` 或 `/frontend/AGENTS.md`，就近规则优先）

## 1. 项目定位与事实优先级

OmniNest 是自托管的个人与家庭数字媒体中心（文件、影视、音乐、相册、阅读、同步、离线与系统管理）。后端采用 Spring Boot 4.1.1 + Java 25 模块化单体架构（单镜像通过 `OMNINEST_ROLE=api|worker|scheduler` 区分运行角色），前端使用 Flutter 统一构建 Web、Android 与 Desktop 客户端，图像分析由独立 Python Sidecar（RapidOCR + MobileCLIP2 / 可选 RAM++）提供。

设计与实现冲突时，按以下优先级裁决（发现真实冲突须先向用户说明取舍与影响，严禁静默改向）：

1. 用户当前任务指令
2. 当前目录与根级 `AGENTS.md` 及自动化架构棘轮测试（`backend/.../architecture/*Test.java` 与 `frontend/test/architecture/*_test.dart`）
3. 项目最新实施方案、模块专项设计文档、总体设计文档
4. 现有代码实现

## 2. 仓库拓扑与分层规范路由

```text
/AGENTS.md               全局定位、Git 规范、跨栈部署/网关契约、全局安全红线
backend/                 Spring Boot 多模块后端 -> 详见 /backend/AGENTS.md
frontend/                Flutter 跨平台客户端   -> 详见 /frontend/AGENTS.md
deploy/                  dev/prod Docker Compose、Nginx 模板、备份恢复脚本与 .env 模板
deploy/vision-sidecar/   Python 图像分析侧车服务与容器定义
```

在仓库根目录执行跨栈架构棘轮快速验证：

```bash
# 后端架构棘轮与迁移基线快速校验（无需改动工作目录）
mvn -f backend/pom.xml test -pl omninest-app -am -Dtest="*Architecture*Test,*Boundary*Test,*Registry*Test,*Wiring*Test,*Consistency*Test,FlywayMigrationLayoutTest" -Dsurefire.failIfNoSpecifiedTests=false

# 前端架构棘轮与部署模板契约快速校验（子 shell 切目录，不改动当前工作目录）
( cd frontend && flutter test test/architecture/ )
```

- **前端命令用子 shell 切目录**：`flutter test` 没有 `--directory` 参数（写了会直接报 `Could not find an option named "--directory"`），且必须在含 `pubspec.yaml` 的目录下运行。
- **架构棘轮命令的 `-am` 与 `failIfNoSpecifiedTests` 不能省**：只写 `-pl omninest-app` 时会用本地仓库里的旧 SNAPSHOT 编译测试，被依赖模块改了方法签名就报「找不到适合的方法」，与被审代码无关；`-am` 让 reactor 用当前源码重建依赖，配套的 `-Dsurefire.failIfNoSpecifiedTests=false` 用于忽略上游模块「没有匹配用例」这一正常情况。看到「测试编译失败但源码明显一致」时先怀疑缺 `-am`，不要改源码迁就。

- **唯一 Git 仓库与工具桥接**：根目录是唯一 Git 仓库（严禁创建嵌套 `.git` 或 submodule）；同时也是唯一 AI 规则源（严禁另建独立内容的 `.cursorrules` 或 `CLAUDE.md`，如需兼容旧版工具仅允许软链接或单行 `@AGENTS.md` 引用）。
- **按需提交原则**：仅在完成代码修改任务且用户未要求暂缓提交时，在根仓库创建 commit（默认不 push）；纯代码审查、方案设计或排障咨询任务严禁擅自创建 commit。Windows 环境优先使用 Git Bash。

## 3. 跨栈部署、网关与配置同步契约

修改 `deploy/`、`.env` 模板、Docker Compose 或 Nginx 网关配置时，必须满足以下跨栈棘轮契约：

| 触发场景 | 强制契约（DO / DO NOT） | 权威守卫测试 |
| :--- | :--- | :--- |
| **修改 `.env` 模板或 `docker-compose*.yml`** | `deploy/prod` 与 `deploy/dev` 下 `docker-compose*.yml` 引用的每个变量必须在同目录 `.env.example` 与 `.env.en.example` 中登记；中英文模板键集合必须 100% 一致，且同一文件内严禁重复声明同一个键。 | `deploy_env_template_contract_test.dart` |
| **修改 Nginx 模板或 `render-config.sh`** | `deploy/prod/nginx/templates/*.conf.template` 中所有 `${UPPER_CASE}` 变量必须列入 `render-config.sh` 的 `envsubst` 白名单；所有指向 `api` 或 `ws` 的 `location` 路径必须以 `${OMNINEST_WEB_BASE_PATH}` 开头（严禁前置正则 `^` 破坏前缀断言），且含 `proxy_pass` 的平级块必须完整保留 `rewrite ^${OMNINEST_WEB_BASE_PATH}(api/.*)$ /$1 break;` 与转发头。 | `deploy_env_template_contract_test.dart`、`SecurityHeaderPolicyConsistencyTest.java` |
| **修改备份与恢复脚本 (`backup.sh` / `restore.sh`)** | 容器内仅执行 `tar` / `pg_dump` 流式输出，加密统一在宿主机管道通过 `openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt -pass env:BACKUP_PASSPHRASE` 执行（`alpine` 裸镜像无 `openssl`；严禁使用命令行明文密码参数）；`sh -c` 执行外部路径时必须通过位置参数 `-- "$1"` 传递，严禁字符串拼接。 | `ComposeNetworkTopologyTest.java` |

## 4. 全局安全、注释与技术栈禁令

- **代码注释与编码**：所有源文件使用 UTF-8；注释使用客观中文，围绕“为什么这样设计（Why）”撰写，禁止尾行注释、情绪化表达或复述代码的模板注释。
- **敏感信息零泄露**：严禁将密钥、密码、Token、KEK、外部存储凭据写入代码或提交版本控制；日志必须使用参数占位符，严禁打印凭据、完整敏感路径或带签名的原始访问 URL。
- **禁止擅自引入重型技术栈**：严禁默认引入 Elasticsearch/OpenSearch、FUSE/rclone mount、Spring Cloud、React/Vue、原生 Android/Desktop 独立客户端或未批准的 AI 大模型依赖；禁止通过关闭 lint、删除或弱化现有测试断言、空 `catch` 吞异常来掩盖问题。
- **交付报告要求**：任务完成后必须清晰说明修改点、涉及文件、实际执行过的验证命令及结果、未执行的验证及原因、以及剩余风险，严禁将未执行的验证描述为已通过。