# AGENTS.md

本文件适用于 `D:\Development\Project Collection\OmniNest`。后续 Agent 在本项目修改代码、文档、迁移脚本、配置或测试时，必须优先遵循本文件。

本文件是整个项目唯一的 Agent 规范入口。不得在 `frontend/`、`backend/`、`ai-sidecar/` 或其他子目录创建额外的 `AGENTS.md`；模块专项约束应写入集中维护的项目文档，并由本文件引用，避免同一任务因目录层级产生冲突规则。

## 项目与事实来源

OmniNest 是自托管的个人数字生活中心，涵盖文件、影视、音乐、相册、阅读、同步、离线和系统管理。系统采用模块化单体：Spring Boot 提供 API、Worker 和 Scheduler 运行角色，Flutter 统一 Web、Android 与 Desktop 客户端。

设计与实现冲突时按以下优先级取舍：

```text
用户最新指令
>
AGENTS.md
>
项目文档中最新实施方案与验收记录
>
模块专项设计文档
>
总体设计文档
>
现有代码
```

根目录设计文档是项目事实来源，不得因普通实现任务随意重写。发现真实冲突时必须说明取舍和影响，不得静默改变方向。

开始实现前必须阅读相关模块现有代码和最新实施记录；公开仓库中的实现不得依赖只有本机资料才能解释的隐含约束。

## 仓库与提交

```text
backend/           Spring Boot API、Worker、Scheduler、Flyway 与后端测试
frontend/          Flutter Web、Android、Desktop 与前端测试
deploy/            dev/prod Docker Compose、环境模板与共享镜像定义
deploy/ai-sidecar/ 图片分析侧车服务、模型适配与容器定义
```

- 项目根目录是唯一 Git 仓库，统一追踪后端、前端、图片分析侧车和部署配置。
- 不得在 `backend/`、`frontend/`、`ai-sidecar/` 或其他子目录创建嵌套 `.git`、Git submodule 或独立仓库；调整仓库边界前必须获得用户明确同意。
- 每项任务完成后必须在根仓库创建 commit，默认不 push；用户明确要求推送时再推送到当前根仓库远端。
- Windows 环境执行仓库命令时优先使用 Git Bash；不要因方便混用 PowerShell 与 Git Bash 进行跨 shell 的文件删除或移动。

## 通用工作方式

- 改动必须小而集中，沿用当前模块边界、命名和已有抽象；不得为单一 Bug 引入大型框架。
- 修复一类明确缺陷时，应在当前模块范围内排查同类调用点，并补足高风险回归测试。
- 新增或改变业务能力时同步考虑 API、权限、异常、任务事件、数据一致性、前端反馈、测试与过程文档。
- 所有源文件使用 UTF-8。代码和配置注释使用客观中文，禁止尾行注释、情绪化评论和无意义叙述。
- 禁止空 `catch`、吞异常、`e.printStackTrace()`、`System.out`、`System.err`，以及在 `finally` 中 `return`。
- 日志使用参数占位符；不得输出 Token、密码、KEK、Access Key、Secret Key、外部存储凭据、分享密码、完整敏感路径或原始访问 URL。

## 存储架构与媒体边界

系统不再把 MinIO 视为唯一内容来源。当前架构是“原始内容多 Provider + MinIO 托管和派生资产 + 本地临时缓存”。

- MinIO 是用户上传、永久托管文件以及海报、背景图、缩略图、字幕等派生资产的默认存储。
- File 模块拥有内容定位、Provider 选择、权限预检、流式读取、Range 读取和受控 staging 能力。
- Video 首期允许管理员登记 `LOCAL_FILESYSTEM` 只读影视库来源；扫描建立 FileNode、内容引用和影视元数据，不复制大型原影片到 MinIO。
- LOCAL 来源只读，不具备 FileManager 重命名、移动、删除、复制、分享、版本、备份和离线下载语义。用户显式永久导入后才转为 MinIO 托管能力。
- Video、Music、Photos、Reader 等业务模块只持有业务 ID 和能力结果，不得直接使用 `Path`、MinIO Client、Rclone Gateway、bucket/object key 或客户端传入的绝对路径。例外：业务服务内通过 `Files.createTempFile` 创建的自有临时文件与 Lucene 本地索引目录不在此限。
- 业务模块必须通过 File 模块的统一内容访问接口读取内容，并按 Provider 能力决定是否允许 Range、写入、分享、版本、备份和跨节点访问。
- 本地来源只能由管理员通过部署白名单的 `mountKey` 创建。数据库、API 和客户端不得保存或暴露宿主机绝对路径。
- LOCAL 来源必须拒绝 `..`、绝对路径、盘符、UNC、NUL、控制字符、符号链接、junction、reparse point 和根目录逃逸；访问前再次验证规范化真实路径位于允许根目录内。
- 转码、探测和临时派生输出使用独立本地缓存目录，不能挤占 PostgreSQL、MinIO 数据目录或系统盘；转码默认关闭。

## 后端架构与 Java 规范

- 后端保持模块化单体和单镜像多运行角色，通过 `SPRING_PROFILES_ACTIVE` 或 `OMNINEST_ROLE=api|worker|scheduler` 区分角色；不得默认拆分微服务。
- `controller` 只能调用本模块 service 或明确暴露的 application service；`repository` 不得跨模块调用（业务仓储 JPQL 中 JOIN File 模块实体的既有写法属既有约定，予以豁免）；跨模块协作优先使用 service 接口或领域事件；`common` 不依赖业务模块。
- Worker Consumer 只负责消息编排、幂等检查和任务状态转换，复杂业务必须在 Service 中实现。
- REST 统一前缀为 `/api/v1`，分页使用 `page`、`size`、`sort`，响应使用 `ApiResponse` 和稳定错误码。写接口返回业务对象或 `taskId`，批量操作返回逐项结果，并同步 SpringDoc 注解。
- Java 使用 Java 21、Maven、Spring Boot、Spring Security、JPA/Hibernate、Flyway、AMQP、Redis、Lucene、Tika、MinIO SDK 与 SpringDoc。关键依赖无法兼容时必须说明临时版本策略与升级路径。
- 对外 API、重要业务类型、复杂约束和非直观行为需要中文 Javadoc；不要为显而易见的私有成员堆砌模板化注释。
- JPA Entity 不默认使用 Lombok `@Data`。优先按需使用 `@Getter`、`@Setter`、`@NoArgsConstructor` 等注解；`equals`、`hashCode`、`toString` 必须依据实体标识、可变字段和懒加载边界显式设计，默认不得包含关联字段或关联集合。
- 所有类型必须在文件头部显式 import，禁止通配符 import，也不得以完全限定类名（FQCN）绕过正常 import。仅当同一文件确实需要区分两个同名类型时，允许正常 import 其中一个类型，并在无法避免的最小声明或表达式位置使用另一个类型的 FQCN；必须在代码审查说明中记录冲突原因，禁止将 FQCN 扩散到无关字段、方法、泛型或业务逻辑。
- 优先构造器注入与 `@RequiredArgsConstructor`，禁止 `@Autowired`、`@Resource` 字段注入。重写方法必须使用 `@Override`；`@Transactional` 只用于 Service 或明确 application service，禁止用于 Controller。
- 使用 4 空格缩进，单行不超过 120 字符；条件和循环必须使用大括号；超过三层的 `if/else` 应通过早期返回或提取方法降低嵌套。
- 禁止原生集合；集合必须声明泛型。当前代码创建且拥有关闭责任的 `AutoCloseable` 资源必须优先使用 try-with-resources；由 Spring、容器、框架或调用方托管生命周期的资源不得擅自关闭。

## 数据库、迁移与任务

- PostgreSQL 保存业务元数据、任务、通知、权限、配置、内容引用和派生状态；原始字节由受控内容 Provider 保存，Lucene 索引和缩略图等属于可重建派生数据。
- schema 为 `omni`，表和字段使用小写蛇形。业务表不额外添加 `omni_` 前缀。主键为 `id uuid primary key`，公共时间字段为 `created_at`、`updated_at`，重要业务表使用 `version` 乐观锁。
- 禁止声明数据库外键；迁移不得包含 `REFERENCES`、`FOREIGN KEY`、`ON DELETE` 或 `ON UPDATE`。关联、级联与一致性由应用层服务维护。
- 当前数据库基线由 `V001__init_schema.sql` 和 `V002__builtin_catalog.sql` 构成。当前项目未进入历史迁移不可变阶段时，结构修改必须同步重写 V001，内置角色、权限、字典和默认配置修改必须同步重写 V002；不得自行新增 V003。进入已发布且已有环境执行过迁移的阶段后，历史迁移不可改写，新增变更必须采用递增迁移，并先更新本规则与发布说明。
- 业务代码查询优先使用 Specification、Criteria API、QueryDSL 或类型安全方式。禁止字符串拼接 SQL/JPQL；简单固定查询可使用 `@Query`。避免 N+1，批量更新和删除使用 bulk operation。
- 动态排序字段必须白名单。禁止 `SELECT *`、存储过程和触发器承载业务逻辑。
- 需要跨请求执行、进度跟踪、失败重试、恢复、调度或后台持续运行的耗时业务任务，必须先在数据库创建任务记录并在事务提交后投递 RabbitMQ。局部、短时且不需要上述能力的异步操作不得机械地引入消息队列。默认重试为 1 分钟、5 分钟、15 分钟，最多 3 次；不可重试业务错误直接失败；DLQ 保存 payload、错误摘要、堆栈摘要、最后执行机器和任务上下文。
- RabbitMQ 保持 `omni.task`、`omni.event`、`omni.config`、`omni.notification`、`omni.dlx` 交换机。配置热更新使用 fanout 与应用内配置注册表，不默认引入 Spring Cloud。

## 安全与访问控制

- 身份来自本地 HS256 JWT 的 `sub` 到 `auth_users` 映射，后端不得信任客户端传入的 `userId`。
- 授权使用 `auth_roles`、`auth_permissions`、`auth_user_roles`、`auth_role_permissions`。JWT 写入 roles 与 permissions claims，接口使用 Authority 和权限编码校验。
- 超级管理员只在数据库不存在 `SUPER_ADMIN` 时通过初始化流程写入；此后认证与授权完全依赖数据库。
- 文件访问必须校验所有权、空间权限、分享权限或管理员权限。托管 MinIO bucket 必须私有，下载使用短期签名 URL。
- MIME 判断必须结合魔数。所有逻辑路径必须 normalize 并校验允许前缀。
- 离线下载、字幕下载、元数据刮削、URL 预览和外部资源抓取必须完成协议白名单、DNS 后 IP 校验、内网/loopback/link-local/metadata 拒绝，并在重定向后重新校验。
- 登录、注册、分享访问和高成本任务使用 Redis + Lua 限流；Redis 不可用时按风险 fail-closed 或使用极小本地限额。
- 文件安全扫描应使用受控 ClamAV 服务或等价实现；扫描失败、威胁、隔离和放行必须是可区分状态，不能将“无法完成”误标为“检测到威胁”。

## Flutter 分层、状态与样式

- Flutter 是 Web、Android、Desktop 的唯一主客户端。业务状态统一使用 Riverpod，禁止混用 BLoC、GetX、Provider 管理业务状态。
- feature-first 分层固定为 `domain`、`data`、`application`、`presentation`：domain 不依赖 Flutter/Dio；data 放 DTO、API、缓存和 Repository 实现；application 放 Notifier、Controller 与流程编排；presentation 仅消费状态、处理用户输入、导航和 UI 反馈。
- presentation 禁止直接调用 Dio、drift DAO、SQLite、MinIO、Rclone 或底层平台 API。平台差异通过 adapter 暴露，业务模块不得散落平台分支。
- application 状态必须不可变。更新 List、Map、Set 时创建新集合，不得原地修改已发布状态。
- Widget 私有且短生命周期的 hover、展开、临时选择、局部动画可用 `setState`；登录、列表、导入、任务、同步、阅读进度、播放状态和分页业务状态必须由 application 层管理。
- OmniNest 项目内 Dart 导入统一使用 `package:omninest/...`，禁止跨目录相对导入。这是本项目为 feature-first 大型目录结构设定的一致性规则，不将其表述为 Effective Dart 的通用导入建议。文件名小写下划线，类型 UpperCamelCase，成员 lowerCamelCase，私有成员以下划线；使用单引号、尾随逗号、`dart format` 和 `analysis_options.yaml`。
- 正式用户可见文案必须进入 ARB。主题、颜色、文本、密度和常用控件样式集中在 `app/theme` 或共享组件；不得在页面散落重复颜色常量。
- 所有可点击图标提供 tooltip 或 semanticLabel。桌面/Web 使用左侧导航和顶部工具栏，Android 使用对应的紧凑导航，但三端保持同一信息架构。
- 大型列表使用 builder、Sliver、分页和虚拟化；禁止以 `SingleChildScrollView + Column` 一次性构建大量动态项。缩略图优先于原图。
- Dart 文件超过 800 行必须规划拆分，超过 1200 行必须拆分。单个 Widget 同时承担多项网络流程、轮询、导航和业务编排时，即使未超过行数也必须拆分。

## Flutter 生命周期与异步安全

### 异步边界

以下均视为异步边界：`await`、Future、Timer、Stream、Dio 请求、文件选择、文件读取、Dialog、BottomSheet、平台回调、Listener 和 post-frame 回调。

跨越异步边界后，继续访问 `BuildContext`、`ref`、`setState`、Navigator、ScaffoldMessenger、Theme、MediaQuery、Localizations 或任何 Element 相关对象之前，必须先确认 `mounted`。

```dart
final l10n = AppLocalizations.of(context);
await operation();
if (!mounted) {
  return;
}
await ref.read(readerCenterControllerProvider.notifier).refresh();
if (!mounted) {
  return;
}
showReaderSnackBar(context, l10n.readerImportSuccess(fileName));
```

- `ConsumerState.ref` 依赖当前 Widget Element。Widget 即将或已经 deactivated、unmounted、dispose 后，禁止调用 `ref.read`、`ref.watch`、`ref.listen`、`ref.refresh` 或 `ref.invalidate`。`ref.watch` 只用于 build 或 Provider 计算；UI 事件中的 `ref.read` 必须位于确认 mounted 的同步片段内。
- `dispose()` 中禁止通过 `ref` 查找或刷新 Provider。需要释放的 Widget 资源保存为字段后直接释放；Provider 自己创建的资源由 `ref.onDispose` 释放。
- 对于长流程，不能仅靠“提前保存 Notifier”规避生命周期问题。上传、下载、导入、任务轮询、扫描、同步、重试、WebSocket、SSE 和长 Timer 必须由 application/Repository/Service 持有，Widget 只发起动作和展示状态。Provider/Notifier 自己持有的异步资源必须使用其生命周期机制（如 `ref.onDispose`，可用时使用 `ref.mounted`）停止回写和释放资源。
- 已拿到后端 `taskId` 后，页面关闭不等于后台任务取消。取消必须通过明确的业务 API 和任务状态机处理。
- 所有 Widget 自建资源遵循“谁创建谁释放”：AnimationController、TextEditingController、ScrollController、PageController、TabController、FocusNode、Timer、StreamSubscription、Listener、CancelToken 和平台监听器必须在拥有者结束时取消或 dispose。不得释放父组件传入或 Provider 管理的资源。
- Future 必须 `await`、返回给调用方，或明确 `unawaited`。fire-and-forget 必须处理错误与幂等，不得无意丢弃异常。

### 竞态、轮询与重复提交

- 搜索、分页、章节切换、书籍切换、媒体详情切换、地图刷新等必须通过 CancelToken、request id、generation、版本或 Provider 生命周期防止旧响应覆盖新状态。
- 上传、删除、移动、重命名、保存、导入、创建目录、创建后台任务必须在 application 层具有执行状态和幂等策略，不能只依赖按钮禁用样式。
- 轮询必须有结束条件、超时、合理间隔、取消机制、失败策略与并发保护；长期轮询禁止保留在 Widget State。
- 页面离开、资源切换或 Provider autoDispose 时，应取消当前请求或使旧结果失效；不得让 stale response 回写当前页面。

### build、路由与选择交互

- `build()` 必须无业务副作用。禁止在 build 内发网络请求、写状态、启动 Timer、注册长期 Listener、导航、弹 Dialog/BottomSheet 或创建后台任务。
- 禁止在 LayoutBuilder、build、dispose、元素停用或 Navigator 锁定阶段同步调用会触发树重建或路由变化的方法。必要操作使用 post-frame 回调，并在回调中再次检查 `mounted`。
- 路由退出只能有一个幂等入口。不要在选择区域、Overlay、动画或手势清理过程中重复 `pop`，避免 Duplicate GlobalKey、Navigator lock、deactivated Element 与 GoRouter 生命周期断言。
- 路由、Overlay、文本选择、FocusNode 和 GlobalKey 操作必须遵守 Flutter Widget 生命周期；不得在复杂手势或清理流程中同步销毁仍在处理事件的树。本机存在 Flutter 稳定性专项文档时，应同时执行其中的回归检查。
- `GlobalKey` 只能在同一时刻对应一个 Widget；不得把瞬时尺寸或频繁变动状态写入会导致整棵子树反复重挂载的 Key。
- 出现 `setState() called after dispose()`、`Looking up a deactivated widget's ancestor is unsafe`、`Using ref when a widget is about to or has been unmounted is unsafe`、`Duplicate GlobalKey`、`Navigator _debugLocked` 或生命周期相关 `Bad state` 时，必须修复根因，禁止 catch 后忽略。

## 网络、离线与性能

- Dio 拦截器统一处理 Bearer Token、串行刷新、`X-Request-Id`、错误映射和幂等请求重试。后端错误统一映射为 `AppException`。
- Web 不把 Token 放入 localStorage；Android/Desktop 使用安全存储。离线敏感缓存使用加密存储或等价方案。
- 离线允许浏览已缓存内容、播放/阅读已下载内容、暂存进度、笔记和书签；上传、删除、重命名和移动默认要求在线，除非单独实现离线写队列。
- 不得在 UI isolate 同步执行大文件全量读取、哈希、批量扫描、大 JSON 解析、大图解码、压缩解压或长循环。使用异步 IO、流式分块、Isolate、独立 Worker 或后端 task。
- 大文件不得整体加载到内存。达到项目配置的大文件阈值后，必须使用 Stream、分片、multipart、可恢复会话、预签名分片 URL 或分块哈希；阈值通过统一配置定义，禁止在业务代码散落硬编码文件大小边界。任何实现不得按文件总大小申请同等内存。

## 测试、验证与交付

- 后端按风险使用 JUnit 5、Mockito 与 Testcontainers。重点覆盖权限隔离、JWT、分享、SSRF、限流、事务提交后投递、任务重试/DLQ、文件路径边界和 Provider 能力差异。
- 前端按风险使用单元、Widget、Golden 与必要的集成测试。涉及异步 Widget、导入、上传、下载、轮询、路由、选择、Provider autoDispose 时，必须覆盖任务未完成即退出页面、Timer/Stream 活跃时退出、请求 A/B 竞态、连续点击和反复进入退出。
- Flutter 代码修改至少执行对应 Widget/单元测试、`dart format`、`flutter analyze`；后端代码修改至少执行相关 Maven 测试；数据库变化额外校验 V001/V002。
- 无法执行验证时，最终回复必须逐项说明未执行命令、阻塞原因、已完成的静态检查和剩余风险。不得将未执行验证描述为通过。
- 禁止通过关闭 lint、删除测试、吞异常、全局变量、滥用 keepAlive、永久保活所有 Provider 或裸 Map 来掩盖问题。DTO/JSON 边界可使用受限的 `Map<String, dynamic>`，但必须在 data 层尽快转换为明确模型，不得将其扩散到 domain、application 状态或 presentation 业务逻辑。

## 禁止默认引入

- 不默认引入 Elasticsearch、FUSE/rclone mount、Spring Cloud、React/Vue、原生 Android/Desktop 主客户端、Whisper、Rasa 或其他与当前范围不符的大型框架。
- 搜索默认 Lucene，PostgreSQL 全文搜索仅作为降级；转码可选且默认关闭；外部存储优先 Rclone RC 或受控 Storage Adapter。
- AI 当前仅保留已接入的照片 AI Sidecar 能力。新增模型、服务或大体积依赖前必须评估部署体积、内存、模型缓存、安全和回退路径。
- 不得将密钥、密码、Token、外部 API Key、KEK、MinIO Secret 或生产数据库凭据写入代码或提交版本控制。

## 最终回复要求

完成任务后，最终回复必须说明主要修改、实际文件、执行过的验证及结果、未执行验证及原因、真实剩余风险，以及受影响仓库的 commit hash 与提交信息。不得使用“应该没问题”“理论上正常”等模糊表述替代验证结论。
