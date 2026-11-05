# OmniNest Frontend — AGENTS.md

> **Scope**: `frontend/`（叠加于根目录 `/AGENTS.md` 之上；适用于所有 Flutter Web/Android/Desktop 源码、资源、ARB 与前端测试）

## 1. 目录分层与状态管理拓扑

Flutter 客户端采用 **feature-first 四层架构**，统一使用 **Riverpod** 管理状态（严禁引入 BLoC、GetX 或 Provider）：

```text
lib/
  ├── app/                   全局路由（GoRouter）、主题与设计 Token（theme/）、应用级启动引导
  ├── core/                  网络拦截器（Dio/ApiClient/SessionGate）、离线加密（OfflinePayloadCipher）、安全存储与平台 Adapter
  ├── l10n/                  多语言 ARB 资源与生成的本地化类（所有正式用户可见文案必须入 ARB）
  └── features/<module>/     按业务域垂直切分（files / video / music / photos / reader / sync / auth / admin 等）
        ├── domain/          纯业务模型、枚举与 Repository 接口（严禁依赖 Flutter UI、Dio 或底层存储）
        ├── data/            DTO、API 客户端、Drift/SQLite 本地缓存与 Repository 实现（Map/JSON 在此层立即转为强类型模型）
        ├── application/     Riverpod Notifier / Controller、长流程状态机、轮询、防抖与离线同步编排（状态必须不可变）
        └── presentation/    页面（Page/Screen）、纯展示组件（Widget）、路由跳转与交互反馈（只消费状态与派发动作）
```

## 2. 前端可执行验证命令

以下命令在 `frontend/` 目录下直接执行（若当前在仓库根目录，先 `cd frontend`）：

```bash
# 1. 运行单个 Widget 或单元测试（日常开发迭代首选）
flutter test test/<path_to_test>.dart

# 2. 运行全部前端架构棘轮测试（修改分层、状态、主题、动效、路由、错误提示后必跑）
flutter test test/architecture/

# 3. 格式检查与静态分析（提交前必跑，必须 0 warning / 0 format diff）
dart format --output=none --set-exit-if-changed . && flutter analyze
```

## 3. 前端架构棘轮红线（触发即挂 CI）

以下规则由 `frontend/test/architecture/` 下的自动化棘轮测试强制守护：

| 触发域 | 强制约束（DO / DO NOT） | 守卫测试文件 |
| :--- | :--- | :--- |
| **文件行数与导入规范** | Dart 源文件超过 **800 行**必须规划拆分，超过 **1,200 行**必须拆分（未登记文件超限直接红灯）；项目内统一使用 `package:omninest/...` 绝对导入，**严禁跨目录相对导入**；**严禁使用未门控的 `print` 或 `debugPrint`**。 | `dart_source_size_test.dart`、`file_size_ratchet_test.dart`、`no_ungated_debug_print_test.dart` |
| **四层依赖与平台能力隔离** | `presentation` 层**严禁直接调用 Dio、drift DAO、SQLite、MinIO、Rclone、底层平台 API 或直接调用文件选择器（`FilePicker`）**，文件选择与平台差异必须经 `application` / Adapter 封装；跨模块导航与路由声明必须符合模块路由与移动端 Shell 分支契约。 | `feature_dependency_boundary_test.dart`、`core_dependency_boundary_test.dart`、`presentation_file_pick_ratchet_test.dart`、`module_route_navigation_ratchet_test.dart`、`mobile_shell_branch_declaration_test.dart` |
| **Riverpod 异步状态与加载指示器** | 异步操作跨越 `await` 后发布状态前，必须校验 Notifier/挂载生命周期，严禁向已销毁的 Provider 回写状态；刷新/重载数据时必须遵循统一加载指示器门禁，**严禁违规使用 `skipLoadingOnReload`** 掩盖闪烁。 | `async_state_publish_ratchet_test.dart`、`riverpod_async_watch_ratchet_test.dart`、`no_skip_loading_on_reload_test.dart`、`loading_indicator_ratchet_test.dart` |
| **视觉 Token、禁紫色令与亮暗色对齐** | **严禁在任何主题、色板、渐变或组件中使用紫色系色值**；颜色、字号、间距、严重程度语义色与移动端 BottomSheet 必须消费统一 Design Token，严禁散落硬编码色值或字号，且亮色/暗色模式必须严格对齐。 | `theme_purple_ban_test.dart`、`design_token_gate_test.dart`、`font_size_lint_test.dart`、`light_mode_parity_test.dart`、`files_severity_role_consumption_test.dart`、`mobile_sheet_semantics_ratchet_test.dart` |
| **动效 Token 与时长门禁** | 动画时长（`Duration`）与曲线（`Curve`）必须绑定统一 Motion Token，**严禁在业务组件中硬编码未登记的 `Duration(milliseconds: ...)`**。 | `motion_duration_ratchet_test.dart`、`motion_token_wiring_ratchet_test.dart` |
| **错误本地化与子路径 URL 解析** | 所有展示给用户的错误原因与失败提示必须经本地化映射进入 ARB，严禁直接向 UI 裸露原始异常字符串或英文状态码；视频、音乐、封面等后端下发的相对资源地址，**必须统一调用 `resolveServerApiUrl(..., options.baseUrl)` 解析**，严禁用 `.origin` 拼接导致子路径部署（`/omninest/`）下 404。 | `error_localization_ratchet_test.dart`、`failure_reason_ratchet_test.dart`、`deploy_env_template_contract_test.dart` |

## 4. Widget 生命周期、异步安全与竞态防护

- **跨越异步边界的 `mounted` 铁律**：
  - 凡跨越 `await`、Future、Timer、Stream、Dio 请求、文件选择/读取、Dialog、BottomSheet、Listener 或 post-frame 回调后，继续访问 `BuildContext`、`ref`、`setState`、Navigator、ScaffoldMessenger、Theme、MediaQuery、Localizations 前，**必须先执行 `if (!mounted) return;`**（若连续两次 `await`，每次 `await` 后均须检查）。
- **`ConsumerState.ref` 与资源释放规则**：
  - `dispose()` 中**严禁调用 `ref.read`、`ref.watch`、`ref.refresh` 或 `ref.invalidate`**。Widget 自建资源（`AnimationController`、`TextEditingController`、`ScrollController`、`FocusNode`、`Timer`、`StreamSubscription`、`CancelToken`）遵循“谁创建谁释放”，保存在 State 字段中直接释放。
  - 上传、下载、导入、任务轮询、同步、WebSocket 和长 Timer **严禁放在 Widget State 中**，必须由 `application` / Repository 持有，并通过 `ref.onDispose` 释放。页面关闭不等于取消后端已创建的 `taskId` 任务。
- **build 纯净性与路由幂等**：
  - `build()` 与 `LayoutBuilder` 内严禁发起网络请求、修改状态、启动 Timer、导航或弹窗；必要后置动作使用 post-frame 回调并再次检查 `mounted`。
  - 路由退出必须单一幂等，严禁在手势清理、Overlay 卸载或动画回调中重复 `pop`；`GlobalKey` 严禁绑定频繁变动的尺寸或瞬时状态。
- **竞态与防抖**：
  - 搜索、分页、章节切换、媒体详情切换必须使用 `CancelToken`、请求代数（generation）或会话快照校验，防止慢速旧响应覆盖新状态或跨账号串味。
  - 上传、删除、移动、重命名、导入等写操作必须在 `application` 层具备执行锁与幂等保护，不得仅靠 UI 按钮置灰防重。

## 5. 网络、认证、离线加密与大文件性能

- **认证网关与登出时序（`auth_offline_cleanup_test.dart`）**：
  - 退出登录必须严格保持“先调用 `sessionGate.markCleared()` 并吊销服务端会话 -> 再清理本地 Token 与用户状态 -> 最后清理离线缓存与密钥”的契约顺序；`ApiClient.onRequest` 严禁越权调用 `sessionGate.markActive()` 复活已关闭的会话网关。
- **离线边界与 `enc:v1:` 加密契约（`reader_sync_queue_payload_encryption_test.dart`）**：
  - **Web 端不承诺离线**：严禁将 Token 或离线主密钥存入 `localStorage` 或 `sessionStorage`（Web 内存密钥使用进程内单例并在登出时 `fillRange(0)` 擦除），不引入 service worker 资源预缓存。
  - **Android / Desktop 离线加密**：本地缓存的阅读器章节正文、书签、笔记与批注（含内容与标题）以及离线同步队列载荷，必须经 `OfflinePayloadCipher` 加密，且同步队列 payload 必须保持 `enc:v1:` 整包密文前缀契约；`ReaderDataManager.create*` 仅负责入队落库，不得在方法内直接触发隐式 `flush()` 破坏本地未同步抵消逻辑。
- **UI Isolate 性能与触控规范**：
  - 严禁在 UI isolate 同步执行大文件全量读取、SHA-256 计算、解压、大 JSON 解析或大图解码；大文件必须按统一配置阈值走 Stream、分片上传与可恢复会话，严禁按文件总大小分配内存；长列表必须使用 Sliver/Builder 虚拟化并优先加载缩略图。
  - 移动端触控下限分层：四空间主切换与返回/关闭逃生控件不低于 48dp；次级控件沿用设计稿的 35–45dp，禁止为凑 48dp 机械放大次级控件。
