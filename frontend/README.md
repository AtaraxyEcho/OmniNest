# OmniNest Frontend

OmniNest Frontend 是基于 Flutter 的统一客户端。

**当前推荐并完成验证的平台：Web、Android、Windows。**

**iOS / macOS**：工程内已有对应目录与适配代码，但**未做与上述三端同级的全量测试**，**不推荐**在生产或日常依赖中使用；如需使用请自行完整验证。

各平台共享同一套产品信息架构和业务状态，根据窗口尺寸、触控、鼠标和键盘输入调整布局与交互密度。

**演示素材**：本仓库文档中的界面示意图与演示素材**均为 CC0 / 公有领域**资源（见根目录免责声明）。导入与截图请使用同类资源（例如 `D:\Development\Resource\CC0`），**请勿**使用受版权保护的内容。

根目录产品概览见 [../README.md](../README.md)，英文版见 [../README.en.md](../README.en.md)，后端服务、API 和存储边界见 [../backend/README.md](../backend/README.md)。

## 日志目录

前端构建、测试与调试输出**统一放到模块根目录 `frontend/logs/`**，不要散落在 `frontend/` 源码根：

```bash
# 示例：测试与构建日志
flutter test --reporter compact 2>&1 | tee logs/flutter-test.log
flutter build web --dart-define-from-file=env/dev.json 2>&1 | tee logs/flutter-build-web.log
```

`frontend/logs/` 已在 `.gitignore` 中忽略，不会提交到仓库。运行时调试仍优先使用 IDE 控制台；若需落盘请写到 `logs/`。

## 应用职责

- 提供 Portal、File Manager、Photos、Movies、Music、Reader、Admin、Profile 和 Setup 等用户界面。
- 通过 Riverpod application 状态连接后端 API、后台任务、通知和实时同步。
- 负责导航、响应式布局、主题、国际化、加载/空状态/错误反馈以及桌面和移动端输入适配。
- 通过受控的 Repository 和平台 Adapter 使用文件选择、媒体播放、安全存储等能力。
- 让上传、导入、解析、删除、轮询和同步等长流程与页面生命周期解耦；页面关闭后，已提交的后端任务继续由服务端处理。

## 页面与信息架构

| 页面或路由 | 主要内容 |
| --- | --- |
| `/setup`、`/login` | 首次安装向导、登录和会话建立 |
| `/portal` | 动态背景、最近内容、通知、搜索和模块入口 |
| `/files` | 文件目录、上传下载、预览、回收站和生命周期操作 |
| `/photos` | 相册、时间线、图片详情、元数据、图像分析和分享 |
| `/video` | Movies 影视库、影片详情、播放、字幕和进度 |
| `/music` | 本地/外部音乐、搜索、队列、歌词、封面和播放控制 |
| `/reader` | 书籍/漫画书库、导入、目录、阅读、书签、批注和进度 |
| `/admin/*` | 用户、角色权限、配置、任务、日志、会话和监控 |
| `/profile` | 个人资料、主题、账号安全和个人偏好 |
| `/settings` | 兼容入口，重定向到个人中心的对应设置区域 |

桌面端和 Web 以左侧导航与顶部工具栏为主，Android 使用紧凑导航和触控友好控件，但模块名称、权限边界和主要任务路径保持一致。`/photos/slideshow` 和公开分享路径属于 Photos 的辅助页面，Reader 的章节、漫画页面和文件导入路径由 Reader 内部路由继续承载。

## 与后端交互

前端调用链保持以下方向：

```text
presentation
    -> application / Riverpod Notifier
    -> data / Repository / Dio
    -> Spring Boot API
```

- HTTP API 默认使用 `/api/v1`；WebSocket 默认使用 `/ws`。
- 认证、Token 刷新、`X-Request-Id`、错误映射和必要的幂等重试由 Dio 网络层统一处理。
- 上传、导入、解析、扫描和删除等长流程通过后端 `taskId` 查询状态，页面只订阅状态并展示进度、成功或失败原因。
- presentation 不直接访问 Dio、drift DAO、SQLite、MinIO、Rclone 或宿主机文件系统；文件内容访问必须经过后端 File 模块。
- 请求竞态通过取消请求、request id、generation 或 Provider 生命周期处理，旧响应不得覆盖当前页面状态。

## 技术与目录分层

- Riverpod 负责业务状态，go_router 负责路由，Dio 负责 HTTP，drift 负责本地结构化缓存，`flutter_secure_storage` 负责敏感凭据。
- 功能目录采用 `domain`、`data`、`application`、`presentation` 分层。
- `domain` 放实体、值对象、Repository 抽象和领域规则，不依赖 Flutter 或网络实现。
- `data` 放 DTO、API Client、缓存、Repository 实现和持久化适配。
- `application` 放 Notifier、Controller、Use Case 编排和页面业务状态。
- `presentation` 只负责展示、用户输入、状态订阅、导航和 UI 反馈。
- 项目内 Dart 导入统一使用 `package:omninest/...`；这是 OmniNest 的目录一致性规则，不代表 Effective Dart 的通用导入建议。

## 安装与环境配置

### 前置依赖

- Flutter stable。当前项目验证基线为 Flutter 3.44.8、Dart 3.12.2。
- Chrome 用于 Web；Android Studio 和 Android SDK 用于 Android；Windows/macOS 对应桌面工具链用于桌面运行和构建。
- 后端必须先启动并可被当前设备访问，默认 API 为 `http://localhost:8080/api/v1`，WebSocket 为 `ws://localhost:8080/ws`。

### 获取依赖

```bash
cd frontend
flutter pub get
```

### 创建本地配置

```bash
test -f env/dev.json || cp env/dev.example.json env/dev.json
```

`env/dev.json` 是编译期配置文件，应用不会自动读取它。启动或构建时必须显式使用 `--dart-define-from-file=env/dev.json`，或者分别传入 `--dart-define`。文件中的地址含义如下：

```json
{
  "OMNINEST_API_BASE_URL": "http://localhost:8080/api/v1",
  "OMNINEST_WS_BASE_URL": "ws://localhost:8080/ws",
  "OMNINEST_WEB_BASE_URL": "http://localhost:3000"
}
```

Web 在没有传入地址时会使用当前浏览器 origin 推导同源 API 和 WebSocket；Android、Windows 和 macOS 没有浏览器 origin，未配置时会回退到 `localhost`。因此真机、局域网设备或其他电脑访问时，必须把配置中的主机改为设备能够访问的后端域名或 IP，且后端 CORS/HTTPS 配置要同时允许该来源。

## 本地启动

先按 [部署指南](../deploy/README.md) 启动依赖，并在另一个终端按 [../backend/README.md](../backend/README.md) 启动后端。然后在 `frontend` 目录执行：

```bash
flutter devices
flutter run -d chrome --web-port=3000 --dart-define-from-file=env/dev.json
```

其他目标平台：

```bash
flutter run -d windows --dart-define-from-file=env/dev.json
flutter run -d <device-id> --dart-define-from-file=env/dev.json
```

其中 `<device-id>` 可以替换为 `flutter devices` 输出的 Android 或其他设备 ID。桌面端和移动端使用同一份业务配置时，仍需确认后端地址对该设备可达。

## 构建流程

### Web

```bash
flutter build web --release
```

当前 Web 应用在未传入编译期地址时使用浏览器当前 origin，因此生产 Nginx 镜像可以直接使用 [deploy/prod/nginx/Dockerfile](../deploy/prod/nginx/Dockerfile) 构建并通过同源反向代理访问 API、WebSocket 和 MinIO。若手动将 Web 与后端部署在不同 origin，构建时显式传入地址：

```bash
flutter build web --release \
  --dart-define=OMNINEST_API_BASE_URL=https://example.com/api/v1 \
  --dart-define=OMNINEST_WS_BASE_URL=wss://example.com/ws \
  --dart-define=OMNINEST_WEB_BASE_URL=https://example.com
```

### Android、Windows 和 macOS

```bash
flutter build apk --release --dart-define-from-file=env/dev.json
flutter build appbundle --release --dart-define-from-file=env/dev.json
flutter build windows --release --dart-define-from-file=env/dev.json
flutter build macos --release --dart-define-from-file=env/dev.json
```

`apk` 和 `appbundle` 用于 Android，`windows` 只能在 Windows 工具链上构建，`macos` 只能在 macOS 工具链上构建。当前仓库生成 Flutter 平台构建产物，未默认集成 Inno Setup、MSIX 或 macOS DMG/PKG 安装包流水线；终端分发需要另行处理平台签名、安装包和更新策略。

## 开发规范

- 使用 Riverpod 管理业务状态，Widget 的 `setState` 只用于短生命周期的 hover、展开、临时选择和局部动画。
- `build()`、`LayoutBuilder` 和 `dispose()` 不执行网络请求、状态写入、导航、弹窗或后台任务创建。
- 跨越 `await`、Timer、Stream、Dialog、平台回调和 post-frame 回调后，访问 `context`、`ref`、`setState`、Navigator 或 ScaffoldMessenger 前必须确认 `mounted`；dispose 中不得通过 `ref` 查找 Provider。
- Widget 创建的 Controller、FocusNode、Timer、StreamSubscription、Listener 和 CancelToken 由创建者负责释放；Provider 创建的资源由 Provider 生命周期管理。
- 路由、Overlay、文本选择和 GlobalKey 操作必须避免重复 pop、Navigator 锁定、重复 GlobalKey 和 deactivated Element。
- 长流程需要可取消、可重试、可恢复或可查询状态时，放在 application/Repository/Service；页面销毁不应让已提交的后端任务失去状态管理。
- 页面文案进入 ARB，主题和颜色使用共享设计 Token；所有可点击图标提供 tooltip 或 semanticLabel。
- 大型列表使用 builder、Sliver、分页和缩略图，避免一次性创建大量 Widget 或解码大量原图。

## 测试与验证

在 `frontend` 目录执行：

```bash
dart format lib test
flutter analyze
flutter test
git diff --check
```

涉及导入、上传、删除、阅读器、播放器、路由、文本选择或窗口尺寸时，应补充 Widget、集成或响应式回归测试，至少覆盖页面中途退出、连续点击、请求竞态、主题切换和反复进入退出。无法执行的测试必须在交付说明中列出原因，不得将未执行描述为通过。

## 相关入口

- [根目录项目总览](../README.md)
- [后端开发指南](../backend/README.md)
- [部署指南](../deploy/README.md)
- [英文前端指南](README.en.md)
