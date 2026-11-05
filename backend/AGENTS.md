# OmniNest Backend — AGENTS.md

> **Scope**: `backend/`（叠加于根目录 `/AGENTS.md` 之上；适用于所有 Java 源码、Maven 配置、Flyway 迁移脚本与后端测试）

## 1. 模块拓扑与依赖方向

后端采用 Spring Boot 4.1.1 + Java 25 模块化单体架构，单镜像通过 `OMNINEST_ROLE=api|worker|scheduler`（配置键 `omninest.runtime.role`）与 `SPRING_PROFILES_ACTIVE=dev|prod` 区分运行职责：

```text
omninest-common          纯领域契约、端口接口、通用异常与工具（严禁依赖 Spring/Jakarta/MinIO/RabbitMQ/Jackson2）
  ├── omninest-infrastructure  基础设施实现（MinIO/S3、Redis、RabbitMQ、Security、SSRF、ClamAV、Rclone、AI Sidecar）
  └── omninest-system          系统管理核心（用户/认证/RBAC、配额账本、配置中心、任务中心、审计、实时同步/通知）
        └── omninest-file            统一文件树、多 Provider 内容定位、可恢复上传会话、外部导入、共享空间、Lucene 文件搜索
              └── omninest-media           影视（Video）、音乐（Music）、相册（Photos）、阅读器（Reader）、壁纸（Backdrop）、天气
                    └── omninest-worker          后台异步消费者（*Consumer）与恢复调度器（*RecoveryScheduler）
                          └── omninest-app             启动入口、全局配置、Flyway 迁移脚本与全量架构棘轮测试
```

## 2. 后端可执行验证命令

以下命令在 `backend/` 目录下直接执行（若当前在仓库根目录，将 `mvn` 替换为 `mvn -f backend/pom.xml`）：

```bash
# 1. 运行单个单元测试类（日常修改迭代首选，秒级反馈）
mvn test -pl <module-name> -Dtest=<TestClassName>

# 2. 运行全部后端架构棘轮与边界测试（修改依赖、行数、事务、SQL、出网、配置后必跑）
mvn test -pl omninest-app -Dtest="*Architecture*Test,*Boundary*Test,*Registry*Test,*Wiring*Test,*Consistency*Test,FlywayMigrationLayoutTest"

# 3. 运行指定模块的完整单元测试套件
mvn test -pl omninest-file

# 4. 运行基于 Testcontainers 的真实 PostgreSQL 迁移与账本集成测试（需 Docker 环境）
mvn test -pl omninest-app -Dtest="*MigrationTest,SharedSpaceLedgerIT,AuditQueryContractIT"
```

## 3. 后端架构棘轮红线（触发即挂 CI）

以下规则由 `omninest-app/src/test/java/com/omninest/app/architecture/` 下的静态分析测试强制执行：

| 触发域 | 强制约束（DO / DO NOT） | 守卫测试文件 |
| :--- | :--- | :--- |
| **类行数与职责上限** | 普通生产 Java 类软上限 **800 行**（未在 `ALLOWED_SOFT_OVERSIZED_SOURCES` 白名单登记超 800 行即红灯），硬上限 **1,200 行**（修改已贴近 1,200 行的类时必须同步精简或拆分）；`omninest-worker` 下 `*Consumer.java` 硬上限 **150 行**，只做消息编排与幂等分发，复杂逻辑必须下沉至 Service。 | `ModuleDependencyBoundaryTest.java` |
| **跨模块与基础设施隔离** | `controller` 仅可调用本模块 Service；严禁跨模块直接调用 `repository`（既有 JPQL JOIN `FileNode` 除外）；业务模块（`system`/`file`/`media`/`worker`）**严禁直接 import 基础设施实现类**（`SsrfSafeUrlValidator`、`TrustedProxyClientIpResolver`、`AesGcmCredentialCipher`、`RedisUtil`、`RedisTokenBucketRateLimiter`、`RedisRuntimeConfigCache`、`RcloneRcClient`、`AiSidecarClient`、`*Properties`），必须仅依赖 `omninest-common` 端口接口；严禁使用 Jackson 2 运行时（`com.fasterxml.jackson.core/databind`），统一使用 `tools.jackson` 与 `JsonSupport`。 | `ModuleDependencyBoundaryTest.java` |
| **事务与远程 IO 边界** | **`@Transactional` 只允许标在 Service 方法或类上，严禁标在 Controller 或 Worker `*Consumer.java` 上**；**严禁在任何 `@Transactional` 方法内调用 `ObjectStorageClient`（MinIO）或 `RcloneGateway` 远程 IO**，避免网络阻塞占满 HikariCP 连接池；事务内触发缓存驱逐、MQ 广播或 `REQUIRES_NEW` 子事务通知（如配额预警）必须注册到 `TransactionSynchronization.afterCommit()` / `afterCompletion(STATUS_COMMITTED)`。 | `ArchitectureInvariantsTest.java`、`ModuleDependencyBoundaryTest.java` |
| **SQL 与 `pg_trgm` 索引保护** | Repository JPQL 模糊查询**严禁写 `lower(coalesce(col, '')) like ...`**（会导致 `gin_trgm_ops` 索引失效退化为全表扫描），必须写 `lower(col) like lower(concat('%', :escapedQuery, '%')) escape '\\'` 并使用 `LikePatterns.escapeSpecials`；严禁字符串拼接 SQL/JPQL；动态排序字段必须经白名单校验；批量更新/删除必须使用批量语句（如 `StorageQuotaService.batchUpdateQuota` 严禁退化为逐行查询更新）。 | `ArchitectureInvariantsTest.java` |
| **Lucene 单写进程隔离** | 只有文件正文索引一个 Lucene 卷（相册检索已收敛到 PostgreSQL）。API 与 Worker 共挂同一索引卷，**API 请求线程严禁直接调用 `fileSearchIndexService` 的写/删/清空方法**（不在 `FILE_INDEX_WRITER_SOURCES` 白名单内调用即红灯），必须通过 Outbox 投递 `FILE_INDEX_SYNC`（仅跨空间移动与转存）或 `TEXT_EXTRACTION`（正文解析）交由 Worker 单写侧执行。索引文档键是 `fileObjectId`，重命名、移动目录、复制、软删除与还原都不需要写索引。 | `ModuleDependencyBoundaryTest.java` |
| **出网执行体与 SSRF 闸门** | 任何新增使用 `HttpClient`、`Socket`、`ProcessBuilder`、`RestTemplate`、`RestClient`、`RcloneGateway` 或 `JavaMailSenderImpl` 的类，必须在 `REGISTERED_OUTBOUND_SOURCES` 中登记；外部请求必须禁用自动重定向（`HttpClient.Redirect.NEVER`），通过 `SafeUrlValidator` / `OutboundEndpointRules` 逐跳校验协议与解析后的公网 IP。 | `OutboundExecutorRegistryTest.java` |
| **Flyway 迁移基线契约** | `db/migration` 下仅允许存在 `V001__init_schema.sql`（表/索引/约束）与 `V002__builtin_catalog.sql`（内置角色/权限/通知/配置），**严禁新增 `V003`**；`V001` 严禁出现 `INSERT INTO` 或任何外键语法（`FOREIGN KEY`/`REFERENCES`/`ON DELETE`/`ON UPDATE`）。修改约束或内置目录时，必须同步更新迁移测试中的基线断言。 | `FlywayMigrationLayoutTest.java`、`BuiltinCatalogFlywayMigrationTest.java`、`JsonPayloadCapacityFlywayMigrationTest.java` |

## 4. 存储、权限与后台任务核心规范

- **多 Provider 内容访问与本地路径边界（`MediaPathBoundaryTest` / `ContentAccessPrincipalBoundaryTest`）**：
  - `Video`、`Music`、`Photos`、`Reader` 业务模块只持有 `fileNodeId` 与能力结果，严禁直接操作 `Path`、MinIO Client、Rclone 或 bucket/objectKey（`Files.createTempFile` 自有临时文件除外），必须通过 `File` 模块统一接口读取内容。
  - `LOCAL_FILESYSTEM` 来源只读，仅允许管理员按白名单 `mountKey` 挂载，访问前必须归一化路径并拒绝 `..`、符号链接、junction、盘符、UNC 与根目录逃逸；严禁向数据库、API 或前端暴露宿主机绝对路径。
  - 内容访问身份 `RequestPrincipal` 只能由 `CurrentUserContext.requirePrincipal()` 或已验证凭证 `RequestPrincipal.credential(AccessGrant)` 构造（新增调用点须登记至 `ContentAccessPrincipalBoundaryTest`），严禁将资源的 `ownerUserId` 伪装成请求主体。
- **任务中心、Outbox 与恢复调度器**：
  - 跨请求耗时任务必须先在事务内写 `sys_tasks` 记录并写入 `sys_task_dispatches`（Outbox），严禁在未提交事务内直发 RabbitMQ。
  - Worker 恢复调度器（`*RecoveryScheduler`）必须通过任务中心租约与卡死回收接口重投任务；处理完成后必须调用 `FilePostProcessingTaskTracker` 或 `TaskRecordService` 更新任务状态，防止死循环重投。
- **Java 编码与单测兼容性底线**：
  - 所有类型必须在文件顶部显式 import，**严禁通配符 import（`.*`），严禁在代码中用完全限定类名（FQCN）绕过 import**（仅同一文件内同名类冲突除外）。
  - JPA Entity 禁用 `@Data`，显式实现不含关联字段的 `equals`/`hashCode`/`toString`。
  - 优先使用构造器注入；**若现有单元测试直接调用了某类的特定参数个数构造函数，新增依赖字段时必须保留原包级构造函数重载**，确保既有单测零改动通过。
  - 新增 Maven 依赖前必须遵守根 `pom.xml` 的 `maven-enforcer-plugin`（`requireUpperBoundDeps`、`banDuplicatePomDependencyVersions`）与 Java 25 基线，优先使用 JDK 25 标准库能力。
