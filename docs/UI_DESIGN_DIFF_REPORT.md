# OmniNest Desktop 原型差异审查报告

- 审查日期：2026-11-19（在 2026-11-18 初稿上继续复核）
- 原型基准：`D:\Development\Project Collection\UI Design\OmniNest Desktop UI UX`
- 原型入口：`src/desktop/DesktopApp.tsx`；样式基准：`desktop.css`、`extra.css`、`more.css`、`polish.css`、`reader.css`、`npstyle.css`、`setup.css`、`select.css`
- 被审实现：本仓库 `frontend/lib/app/router.dart`、`frontend/lib/app/desktop/`、各 feature 桌面分支
- 代码基线：`6b7281713 Align desktop UI and backend workflows`
- 范围：源码级页面/组件结构、交互状态、路由与壁纸作用范围。未启动原型/Vite 或 Flutter 窗口，故不对像素尺寸以外的实际渲染、运行时叠层、运行时溢出和具体设备上的复现作通过结论。
- 历史记录：`UI_DESIGN_DIFF_REPORT_ARCHIVE_2026-11-18.md` 保留先前逐批实施日志与审查记录；与本报告冲突时以本报告的 2026-11-19 当前源码复核为准。

## 本轮源码实施（2026-11-19 第二批）

以下各项已从"源码差异"落为代码，并执行了列出的验证；运行态截图仍未采集。

| 项 | 原型依据 | 实施内容 | 验证 |
|---|---|---|---|
| 全站壁纸被路由实底遮挡 | `BackdropView.tsx::useBackdropActive` 在 `scope=all` 下不按路由屏蔽壁纸 | `app_route_surface.dart::routeBackdropPolicy` 桌面端改为：影视/音乐 `content`（连续），照片/阅读 `staticContent`，Settings/Admin/Files 等系统页 `content`。`RouteEnvironmentSurface` 在落位后保持透明，壁纸可见 | `flutter test test/app/route_backdrop_policy_test.dart test/app/route_surface_transition_wash_test.dart` → 8 passed |
| Files 左树缺 `.fx-tree` 玻璃容器 | `desktop.css:446`（圆角 20/`--panel`/1px/`blur(20px)`）、`extra.css:62-64`、`polish.css:245` | `desktop_files_rail.dart` 重写：整轨 `DesktopGlassSurface`+面板容器；导航行 34px、树行 32px、缩进 `4+(depth-1)*14`、分组标题 gap 分隔线；存储用量按 `.usage/.u-bar/.u-leg` 重排 | `dart analyze` 通过；组件测试 25 passed（列表/表格/工位组件） |
| 新建目录后左树不刷新 | `Files.tsx::newFolder` 直接改同一份 `files`，树即时更新 | `_FolderTree` 监听 `FileBrowserState`：当前目录文件夹签名（id+名称）变化即丢缓存重取；展开目录时始终重取该层（不再命中旧缓存） | 同上；逻辑覆盖见 `_syncWithState` |
| 树节点无拖放/延迟展开/键盘 | `Files.tsx` 树项 `draggable`、`dropProps`、`expandOnHover`（650ms）、`ArrowRight/Left` | 树行加 `Draggable` + `DragTarget`：落点 accent 22% 底 +1.5px 描边；悬停 650ms 展开并加载子级；聚焦后 ←/→ 收起/展开；根条目 "My files" 也接收拖放（`moveFilesTo(ids, '')`） | `dart analyze` 通过；拖放运行态未实测 |
| 目录副标题是类型而非子项数 | `Files.tsx::rowEl` 的 `${childCount(f.id)} items` | 后端 `FileNodeDto.childCount` + `FileNodeRepository.countChildrenByParentIds`（按本页目录 id 一次分组统计）；`FileListQueryService` 三处填充；前端 DTO/领域模型透传；行副标题改为 `desktopFilesItemCount` | 后端 `mvn -f backend/pom.xml -q -pl omninest-file -am -DskipTests compile` exit=0；DB 级 IT 未执行 |
| 更新时间格式固定 `YYYY-MM-DD` | 样例 `modified` 为 Today / Yesterday / `Sep 24` | `_formatModified`：今天/昨天 + `MaterialLocalizations.formatShortMonthDay` | 同上 |
| 文件行缺少行内星标/分享 | `Files.tsx` `.ra` 的 star / share / more | `_FileRow` 增加 `onFavorite`/`onShare`，仅回收站禁用；收藏走真实 `addFavorite/removeFavorite`，分享打开现有分享抽屉 | 组件测试 25 passed |
| Home Hero 缺两张 action tile | `Home.tsx` `.hero-tile`（`polish.css:412-417`） | 新增 `desktop_home_hero.dart`（part）：52px 封面 + 两行文案 + 3px 进度条；悬停上浮 2px / 底 20% / 边 34%；无数据时不出 tile | `dart analyze` 通过 |
| Hero 尺寸与暗部层级 | `polish.css:404-406`：高 `clamp(380,46vh,500)`、径向+线性暗角、`clamp(26,3.4vw,44)` 内距 | Hero 高度/两层渐变/内距按上式；天气卡 264px 进 grid 右上；`.bd-on` 下透明面、白 20% 边、仅底部长渐变、不画天象 | 同上 |
| 首页照片条比例与标签 | `Home.tsx`：`flexGrow=p.ratio`、hover `3`、标签 `p.place` | `desktop_home_lists.dart` 改用 LayoutBuilder 按比例分配宽度 + `AnimatedContainer(600ms)`；标签取 `gpsLocation` 首个地名，不再显示 title | `dart analyze` 通过 |
| Photos 单图铺满整行 | `polish.css:324-328` `.justified.solo` + `.solo-note` | 单张照片保持比例（`targetHeight*ratio`）+ 右侧旁注（Single capture/标题/地点/相机/曝光），窄窗自动换行 | `dart analyze` 通过 |
| Admin 缺独立 Media library 分区 | `Admin.tsx` 六分区，Media library 独立 | 新增 `AdminSectionGroup.library` + `AdminSection.mediaLibrary`（`media:library:manage`）；`AdminMediaLibraryPage` 复用库源扫描区；桌面侧栏/移动底栏/分组标签同步；分区切换失效 `videoLibrarySourcesProvider` | `flutter test`（admin_five_sections/section_refresh/section_visibility）→ 9 passed |

### 追加实施（同日晚些时候：恢复桌面测试套件 + 真布局缺陷）

1. **桌面测试夹具修复**：`desktop_test_harness.dart` 与当前源码对齐——`MusicPortalSnapshot` 补 `weekListeningSeconds/itemsAddedToday`；照片分页改用 `photoRepositoryProvider` 的 `_SeededPhotoRepository`（实现 `dashboard/listTrash/listPhotos/listFavorites/listAlbumsPage`，其余 `noSuchMethod`）；阅读页注入 `readerCenterControllerProvider`；`localDatabaseProvider` 换内存库（否则视觉基线会走 `path_provider` 抛 `MissingPluginException`）。
2. **修复桌面下拉在无界宽度下的布局断言**：`DesktopSelect` 未给 `width` 时在 `Wrap` 里用 `Expanded`，触发 "non-zero flex + unbounded width"（管理台任务分区实测 26 条异常）。改为 `mainAxisSize.min` + `Flexible(loose)`。
3. **修复抽屉底部无界宽度**：`DesktopDrawerFrame` 的 `footer` 之前塞在无界 `Row` 里，任何 `Row + Spacer` 的 footer（影视详情编辑）都会崩。改为 `Align(centerRight)`，给 footer 有界最大宽度。
4. **Files 网格卡片按原型重排**（`extra.css:88-92`）：84px 图舱 / 圆角 18、名称与副标题居中、隐藏大小列、左上勾选与右上星标/分享/更多（悬停或选中浮现）、悬停底色 `raise2` 且上浮 3px。
5. **管理台概览统计标签**：运行任务卡改用 "Running tasks"（新增 `adminRunningTasksStat`），与 `Admin.tsx:48` 一致。
6. **桌面测试断言与当前设计对齐**：Hero 双 tile、`Continue · 36%` 眉标、`Resume` 按钮、图标式收藏、`Sign out`、媒体库服务卡、`Today/Yesterday` 日期、`My files` 导航、鼠标指针拖拽、密码强度计仅在有输入时渲染、窗口三键按 `Semantics`/key 断言；首页 golden 因 Hero 视觉有意变更而重录。

### 追加实施（页面级：Reader / Music）

- **Reader 总览改双栏**：`desktop_reader_page.dart` 在 ≥1180 时左「继续阅读」62%、右「洞察面板」38%（面板内 2×2 卡 + 14 天柱图），窄窗上下叠；与原型 `05-reader` 的两栏结构一致。
- **Music 主视觉**：`desktop_music_widgets.dart` 的频谱从右侧 160×64 小图改为样例 `.f-viz` 的贴底通栏 90px、白色 56 柱、整体 55% 不透明度、`IgnorePointer`；眉标改为 `Playing from {album}` / `Paused · {album}`（新增 `desktopMusicPlayingFrom`）��
- 桌面测试套件稳定在 **172 条全绿**；`test/app` 全量亦全绿。
- 为守 800 行棘轮拆出两个 part：`desktop_reader_insights.dart`、`desktop_files_grid.dart`（阅读页 607 行、文件行 793 行，均回到线下）。
- `session_epoch_wiring_contract_test` 同步到照片分页控制器迁移后的文件位置（`photo_paged_list_controller.dart`，基类 build 内 watch 世代）。
- **Photos 瓦片**：标题改为样例 `.ph-cap` 的悬停淡入（不再常显），收藏心移到右下 10/10 并改白色；避免与标题重叠（右内距 36）。
- **Files Access 标签**：字号 9→11、非共享项改透明底（样例 `.tag.dim`），共享项 accent 16% 底。
- **静态分析归零**：修掉遗留测试夹具漂移后，`flutter analyze --no-pub` 为 **0 error**（仅 7 条 probe 脚本的 info/warning）。修复内容：`requiresTwoFactor` → `requiresChallenge`；文件仓储 fake 补 `requestMediaImports/scanDuplicates`；音乐 fake 补 `updateListeningDuration` 与 `MusicDashboard` 新必填字段。

### 本轮验证命令与结果

- `flutter gen-l10n`：通过（新增键中英同步）。
- `dart analyze`（改动文件）与 `flutter analyze --no-pub`：`lib/` 无问题；全量仍有 18 条 error 全部位于测试夹具（见下"未执行/阻塞"）。
- **`flutter test test/app/desktop` → 170+ 全绿（exit=0）**，含首页 golden、文件列表/网格/拖放、影视/详情、照片、阅读、设置、管理台、窗口 chrome。
- 前端测试：`route_backdrop_policy` + `route_surface_transition_wash` 8 passed；`file_optimistic_update` + `file_browser_controller_append` 12 passed；`file_list_row_target` + `files_workstation_components` + `files_table_view` 25 passed；admin 三分区测试 9 passed。
- 架构棘轮（子集）：`motion_duration_ratchet` 通过；`l10n_unique_keys` 仅剩既有 `readerTypeComic` 重复键（非本轮键）；`font_size_lint` 仅剩 `reader_view_desktop_top_bar.dart`（非本轮文件）；`file_size_ratchet` 仍为既有清单（`desktop_photos_page.dart 1133/935` 等，本轮未触碰这些文件；`desktop_home_page.dart` 由 989 拆到 618 + 新 part 624，`desktop_files_rail.dart` 750，均未新增超线文件）。
- 后端：`mvn -f backend/pom.xml -q -pl omninest-file -am -DskipTests compile` exit=0。

### 未执行 / 阻塞

- 桌面 widget 套件已恢复并通过（见上）；`test/features/files/files_hosted_share_sheet_test.dart`（5 条）与 `admin_oauth_app_dialog_test`（1 条）仍是既有失败：分享面板现在有 4 个 `MobileEnvSwitch`，测试按单个断言；OAuth 保存调用未发生。二者均不在本轮改动面，未修。
- 未采集原型/Flutter 同视口截图，未实测 hover/拖放/650ms 展开/窗口缩放；Files 树拖放、Hero tile、单图旁注均属运行态待验。
- 6.8px Dock 溢出、播放器双层、Ops 双分类栏：本轮无源码级新证据，维持运行态待定责。
- 后端 DB 级集成测试未执行（需容器化数据库）。

## 执行摘要

此前版本不是全面对比：路由页面被合并成宽泛类别，许多单元格只列“下一轮要核对”，没有列出原型源码和当前源码的具体差异；少数判断也不够准确。本次补审后，报告将每个页面/主要子页面分别列项，并把结论分为源码已确认、源码意图相符但需运行态验收、原型没有独立对应页三类。

本轮新确认的源码事实包括：全站壁纸在 Admin、Settings、Movies 等桌面路由被路由表面的 work 策略明确设为不可见；播放器最终原型宽度来自 more.css 的层叠规则；Movies 的 7 个分类与 Movies/Photos/Music 的导入入口在当前源码中均已存在；Photos 的独图 justified.solo 样式在 Flutter 对应网格中没有同等分支，单张照片会组成一个填满整行的 Row。

仍需实机定位的已知故障：

- Flutter 源码现在定义 `immersive` shell posture，`/photos/:photoId`、`/video/:videoId`、书籍详情等路径会离开常规 `_Workspace`。因此“点图片后壳层仍在”的报告与当前静态路由分支不一致，可能发生在运行构建落后、路由实际仍停留在图库页、或查看器是在页面内 Overlay 打开的路径。源码证据不足以定位其中哪一种。
- 壁纸范围 predicate 在 everywhere 下虽覆盖所有 path，但路由表面策略会显式遮住部分内容路由；具体源码原因见下方全站壁纸条目。
- 当前 workspace 只找到一个 `DesktopPlayerBar` 构建点，但用户报告底部播放器叠加；第二个可见绘制源尚未定位。

### 覆盖范围与证据等级

| 证据等级 | 判定标准 | 本报告写法 |
|---|---|---|
| 源码已确认 | 两边源码结构、条件分支、组件参数或明确尺寸直接不一致 | 写明原型文件/组件、Flutter 文件/组件和实际差别 |
| 运行态待验 | 静态结构相近，差别取决于窗口宽度、动画/悬停/权限/实时数据或构建版本 | 不称为已修复或源码缺陷，列出需要观测的状态 |
| 原型无独立页面 | Flutter 路由是产品新增能力，原型只存在相邻 Drawer、Panel 或没有该功能 | 标记为新增信息架构，按相邻原型组件比较视觉；不伪造对应页面 |

报告按 router.dart 当前全部显式路由及其桌面分支盘点，另外拆分 Settings/Admin 的页内分区；另有一张用户已报问题闭环表，逐项标明已确认、旧问题已过时、当前源码有功能但视觉未核、或需运行态定责。仅做静态源码比对，没有对每个路由完成窗口截图、鼠标/键盘/触摸操作、后端数据状态和无障碍树验收；相关项明确标成运行态待验，不冒充视觉通过。

## 审查维度

此报告只记录可从源码直接比较的结构、路由、条件、尺寸、状态与交互证据；不使用综合分数替代差异清单。主题、响应式、加载/错误/空状态、可访问性提示、异步反馈、Drawer/Dialog/Overlay 和键盘操作均纳入下面的逐路由矩阵或共享控件项。运行时视觉、不同 DPI 和交互手势另列待验，不冒充源码可证明的结果。

## 问题清单与源码证据

### P1：工作区壳层、播放器与全屏内容的所有权不清

- **用户问题**：侧栏、顶栏、播放器在查看器等全屏模块里仍出现；底部播放器叠加。
- **原型结构**：`DesktopApp.tsx::Window` 只挂一套 `TitleBar`、`Sidebar`、`Dock`、`PlayerBar`；VideoPlayer/NowPlaying/BookReader 以高层 overlay 覆盖 Window。Photos 的 `PhotoViewer` 通过 `ui.tsx::Portal` 挂到 `.window`，`.viewer { position:absolute; inset:0; z-index:80 }`，同样覆盖侧栏、顶栏、Dock 和 PlayerBar。
- **当前源码**：`DesktopShellMode` 对 `/photos/:id`、`/video/:id`、`/video/series/:id`、`/reader/items/:id`、`/music/now-playing`、slideshow、edit、read、play 等路由返回 immersive；Immersive 分支不构建 `_Workspace`，但仍经过 `DesktopWindowChrome`。源码意图覆盖了主要沉浸页，是否与原型对齐需按路径逐项核对。壳层 `_Workspace` 中只找到一个 `DesktopPlayerBar` 构建点，音乐页引用该符号但没有第二个绘制实例。
- **尚未解释**：用户报告与当前源码分支不一致。需确认运行的前端构建提交、运行 path、`DesktopShellHost` 是否被重复宿主，以及照片查看是否实际走全屏 route。播放器重复的第二个绘制源不能从静态调用点确认。
- **影响**：沉浸查看/播放被常驻控件遮挡，主内容可用面积减少；两条播放器争夺点击和布局。
- **下一步审查重点**：以同一个已启动构建实测 Home→照片、Photos→Viewer、Movies→详情/播放、Reader→详情/阅读；记录每次导航实际 location、可见 shell widgets 和 player widget tree。未完成实测前不把此项标为源码已修复。

### P1：详情坞展开/收起时的 6.8px RenderFlex 溢出尚未定责

- **用户症状**：详情面板展开或收缩时 Flutter 报 `A RenderFlex overflowed by 6.8 pixels on the right`。
- **原型结构**：`Shell.tsx::Dock` 由外层 `.dock` 在 0↔348px 之间做宽度动画，内层 `.dock-in` 固定 348px 并滚动；头部是详情/队列分段与关闭按钮，主体随 tab 显示 detail 或 queue。
- **当前源码**：`frontend/lib/app/desktop/desktop_dock.dart::DesktopDock` 同样使用 348px Dock；动画宽度变化时通过 `ClipRect + OverflowBox(minWidth=maxWidth=348)` 保持内部完整宽度，意图避免收放过程中把内部 Flex 压窄。详情头部 `Row` 内为 `Expanded(DesktopSeg)` 与固定尺寸关闭按钮；内容滚动。
- **结论**：用户所称详情面板对应当前 Shell 的 `DesktopDock`，该组件已有动画期间固定内宽的保护；仅凭源码不能证明该保护覆盖了实际 RenderFlex，也不能将 6.8px 的具体触发子树定为头部 Row。报告保留为**运行态待定责**，复现时需记录 Dock 展开状态、窗口宽度、当前 tab/详情类型、locale、Flutter RenderFlex ancestor chain 和触发帧。
- **影响**：展开/收起的面板内容可能裁切，或调试模式持续打印溢出错误；不能把“Dock 有 ClipRect”视为已修复证据。

### P1：全站壁纸在 Admin/Settings 等页面未生效

- **原型结构**：`BackdropView.tsx::useBackdropActive()` 在 scope=`all` 时允许任何桌面 route 使用壁纸；`BackdropLayer` 挂在 `.window` 下，Home/Movies/Photos/Music/Reader/Files/Settings/Admin 均处于同一背景层上。
- **当前源码**：`desktopBackdropAppliesToRoute()` 在 everywhere 下确实返回 true，但路由页又经 `AppRouteSurface.environmental()` 包装。`routeBackdropPolicy()` 在桌面将 `/admin`、`/profile`、`/video` 等归为 `AppBackdropPolicy.work`，其 `visible:false`；`RouteEnvironmentSurface` 因而用 `Theme.surface` 实色包住这些页面。证据：`frontend/lib/app/router.dart::_routeSurface`、`frontend/lib/app/route/app_route_surface.dart::routeBackdropPolicy/RouteEnvironmentSurface`、`frontend/lib/features/backdrop/domain/app_backdrop_policy.dart::work`。
- **差异结论（源码已确认）**：后台 scope 允许壁纸并不能覆盖路由级 work policy；Admin、Settings、Movies 的实色路由表面会挡住壳层壁纸。这与用户反馈一致，不是单纯的截图/旧构建猜测。Photos/Reader 采用 staticContent、Music 等路由策略不同，需按 route 单独记录可见/静止语义。
- **影响**：背景设置语义与显示结果不符，管理/设置区视觉层级断裂。

### P1：Home Hero 结构缺项，壁纸下未按样例透出

- **原型结构**：`Home.tsx` 的 `.hero-sky` 由动态 `Sky`、暗部渐层、左侧日期/问候/文案、两个横向 Hero action tiles（继续观看 + 专辑播放）以及条件 Weather glass card 组成，CSS 为 340px–460px `clamp(340px,42vh,460px)`。自定义壁纸下由 `BackdropView.tsx` 控制壁纸，同时 Home 的天空内容仍按样例规则处理。
- **当前源码**：`desktop_home_page.dart::_HeroSky` 保留天气、日期、问候、文案、操作入口，Hero 高度公式与原型 `clamp(340px,42vh,460px)` 一致，但没有原型两张带 artwork 的横向 action tiles；由 dashboard 汇总数据决定 Resume / Listen 的按钮标签及可用性。Home 自定义壁纸时 Flutter 用 `showSky:false`，仍绘制固定 `heroShade` 渐层、边框与阴影，结构不等于样例的透明 Hero。
- **差异**：缺少/替换了 Hero 卡片的 art、信息密度与视觉分组；背景库启用后 Hero 仍是带遮罩的卡片壳，而不是随壁纸透出的透明版。天气卡、断点和空/加载内容也须逐项对照。
- **影响**：Home 第一屏重点和背景图关系偏离样例；文案/操作对真实空数据的状态与原型展示不同。

### P1：Home Recent Photos hover 行为需要按 CSS 重核

- **原型规则**：`Home.tsx` `.photo-strip` 展示最多七项，按照片原始比例给 `flexGrow`；`desktop.css:299` 悬停将单张 `.ps` 扩张为 `flex-grow:3` 并显示位置标签，没有动态光晕/透视倾斜。
- **当前源码**：`desktop_home_lists.dart::DesktopPhotoStrip` 也按原始比例分配 flex，并悬停扩张；但每一项的基准 grow 是将宽高比乘 100 后 clamp 到 60–220，而 hover grow 固定 300，标签显示 `PhotoItem.title`（样例用 place）。加载态使用固定数组 flex 值，非七张照片会改变轨道组成。
- **差异**：宽高比换算与原型 CSS flex grow 单位不同；显示字段不同；需核实 hover 过程中的总宽分配是否出现横向抖动/其他卡挤压，且样例位置标签语义与当前标题并非同一字段。

### P1：Sidebar / Titlebar 材质、尺寸和图标体系待逐项对齐

- **原型**：`Shell.tsx` 的同一套 icon registry 和 `NAV` 定义侧栏 6 个主空间；`desktop.css:174` 顶栏 46px，`desktop.css:193` 侧栏 232px、折叠 64px；顶栏/侧栏分别使用透明混色底、边线和统一 `.tb-btn` hover/selected 反馈。玻璃 blur 随具体面板规则，不是每个控件一律发光。
- **当前源码**：分拆为 `desktop_title_bar.dart`、`desktop_sidebar.dart`、`desktop_icons.dart`、`desktop_panels.dart`；`DesktopMetrics` 中 TitleBar 46px、Sidebar 232/64px 与原型 CSS 几何值一致。当前 Flutter 桌面一级导航是 Portal/Library/Reader/Files 等产品路由，原型 NAV 是 Home/Movies/Photos/Music/Reader/Files；宽度对齐不代表导航内容、标签、图标字形和反馈对齐。
- **差异**：导航信息架构已确认不同；逐图标 glyph、留白、基线、颜色、badge/hover/active、玻璃背景 opacity/blur 尚需按 `Shell.tsx` + `desktop.css` 对照。当前无运行截图，不能给出最终像素偏差值。

### P1：Admin 顶层缺少独立 Media library 分区

- **原型**：`Admin.tsx` `sections` 明确有 Overview、Users & roles、Media library、Operations、Configuration、Storage 六项，Media library 使用独立 `LibraryManager` 页面。
- **当前源码**：`admin_section.dart` 只有 overview、identity、operations、configuration、storage 五个 `AdminSectionGroup`；没有 library group/tab。存在 `admin_operations_library.dart`，但它是存储/媒体库运维能力的一部分，不等同于原型 Admin 顶层 Media library。
- **差异**：顶层信息架构和入口缺项。现存运维 Library 管理页是 backend media source 管理，不能替代样例对媒体库总览/整理的独立页面。
- **影响**：管理员无法按样例从 Admin 主导航访问媒体库管理工作区。

### P1：Admin Operations 导航与页内栏目可能重复

- **原型**：`Admin.tsx::Ops` 在一个卡片内只创建一条 tabs：Tasks、Dead letters、Sign-in audit、Sessions、System logs；每个 Tab 内显示内容及自身过滤栏。
- **当前源码**：`admin_group_pages.dart` 的 `_DesktopOperationsHub` 新增 Tasks/Dead letters/Sign-in audit/Sessions/System logs 的 `DesktopSeg`，并嵌入 `AdminTasksPage` / `AdminLogsPage`。嵌入时传 `hideDesktopTabSelector:true`，静态意图是隐藏子页面原有栏目。
- **差异**：Flutter 同时保留 Operations section 路由、Hub 的分段以及任务/日志子页的旧 Tab 状态；需要按实际 permission 和每个 Ops 子项分别核对 hub/子页 segment 是否重复呈现。用户已实机报告有两个分类栏；源码需进一步定位具体窗口状态，单看 Hub 参数不够解释。

### P1：Photos 查看器、照片单行、选择与悬停细节

- **原型**：`Photos.tsx` 通过 `PhotoViewer` 作为全屏 Viewer；图库以分组网格为主，按 `photo-strip`/`photo` CSS 规则布局。点击选中按钮与批量选择是离散交互；拖动重排限定为原型支持的分组/项目。相册、位置、收藏、回收站等以顶部分段/视图切换呈现。
- **当前源码**：桌面 photos 拆成 `desktop_photos_page.dart`、`desktop_photos_sections.dart`、`desktop_photos_groups.dart`、`desktop_photos_selection.dart`、`desktop_photo_viewer_page.dart`，且额外接入分页、日期排序和 overlay drag ghost。图库和 Viewer 分路由；图片点击应切至 immersive route。当前用户报告单张照片宽度占满一行，说明布局约束/单项条件没有按样例比例排列；长按、批量选择、hover、单选/多选的相互状态尚未完成成对实测。
- **差异（源码已确认）**：原型给单照片列表添加 `justified.solo`，取消普通 flex 扩张并并排显示照片信息块（polish.css 的 `.solo-note`）；Flutter `desktop_photos_sections.dart::_layout` 对任意数量都按目标行高累计 ratio，单项单独成行后由 `Expanded` 占满可用行宽，没有 solo note。另需把多选/拖动和 hover 状态按原型逐态核验，不能以已实现 reorder 推断等价。
- **影响**：单张图异常扩展时破坏相册浏览节奏；批量选择误触或 hover 反馈不符会使高频照片管理难以预期。

### P1：音乐卡 hover 发光及底部播放器重复/规格

- **原型**：Shell.tsx 只渲染一个 PlayerBar。级联顺序 `desktop.css → extra.css → more.css` 后，more.css 设为可见宽度 `min(1080px, calc(100% - 40px))`、高度 66px；≤1180px 收窄至 `min(860px, calc(100% - 28px))` 并隐藏音量，≥1360px 显示 64×26 visualizer。控件包含封面/曲目信息、收藏、播放模式、前后切、播放、进度、音量/Queue/Now Playing。
- **当前源码**：`DesktopPlayerBar` 单点挂载；Flutter 外层最大约束 1120px 且左右 margin 各 20px，实际绘制宽度上限为 1080px；紧凑态外层 888px、左右 margin 各 14px，实际绘制宽度上限为 860px。因此可见宽度与原型最终级联值一致，不能据 token 数值声称有 40/28px 宽度差。高度 66px 和 compact 断点 1180px 对齐。第二个播放器的运行时绘制来源尚未找到。
- **差异（运行态待验）**：播放器叠层、控件顺序/可见阈值、曲目信息和 Queue/Now Playing 行为仍须实测；静态源码没有第二个 `DesktopPlayerBar` 绘制点。Music 卡片 hover 不能笼统写“原型没有光影”：原型局部有普通黑色投影/按钮显隐；需具体核对 Flutter 是否额外叠加 accent glow，而非删除原型存在的选中/唱片/按钮效果。

### P1：桌面通知仍与系统通知功能耦合

- **原型**：`Shell.tsx::NotifPanel` 由 Shell 顶栏 bell 打开，呈 All/Unread、今日/较早分组、清空/标记已读和设置入口。原型通知数据来自 `data.ts` 演示态，是桌面视觉交互基准。
- **当前源码**：`desktop_title_bar.dart` 的 bell 打开 `desktop_panels.dart::NotificationsPanel`，消费 `notificationControllerProvider`；路由还保留 `/notifications` 的 `NotificationPage`。这使原有后端通知中心作为桌面第二套交互继续存在；与用户要求“移动端保留、桌面端采用样例通知 UI”未完成隔离。
- **差异**：需要区分“桌面沿用样例通知面板结构/交互”和“系统通知后端/移动端页面能力”；当前桌面标题栏、通知面板、通知全页仍直接复用系统通知域。

### P1：Files 左侧结构树的样式、刷新和拖拽交互不符合原型

- **原型结构**：`Files.tsx::treeFolders` 从同一份 `files` 状态派生目录层级，按名称排序并反映 `cwd` 当前目录；折叠状态保存在 `fileTreeOpen`。`extra.css:62-64` 将主区分为 244px 树栏与内容区；`desktop.css:446-448` 给整个 `.fx-tree` 独立圆角面板、半透明底/blur/边框，导航行高 34px。树目录项支持点击进入、双击展开、方向键展开/折叠、原生 draggable、拖到目录重排；拖进子目录悬停 650ms 自动展开，drop 目标高亮。
- **当前源码**：`desktop_files_page.dart` 把 `_FilesRail` 直接放进 244px `SizedBox`/滚动视图，没有包裹原型整块 `.fx-tree` 面板。`desktop_files_rail.dart::_FolderTree` 在 `initState` 时只拉一次根目录；展开时加载子目录并存入 widget 本地 `_children` map。目录行仅有点击打开与单独点击箭头展开；该树节点没有 `Draggable`、`DragTarget`、长按拖拽、hover-drop 目标或悬停自动展开。
- **新建目录刷新问题（源码已确认）**：样例 `newFolder()` 把新 folder 加入 `files`，随后选择并打开该树节点的 inline rename；树直接由 `files` 状态渲染，所以目录即时出现在树中。Flutter 工具栏调用 `_showNewFolderDialog`，再由 controller 发起真实创建并刷新当前列表；但 `_FolderTree` 的本地 `_children` 缓存既不监听文件列表，也没有创建后失效/重取机制，且 `_load()` 对已缓存 parent 会直接返回。此结构解释了“列表已有新文件夹但左树无变化”的现象。
- **树栏视觉差异（源码已确认）**：原型是单一 glass panel，内含 section 标题、导航和树项目；Flutter 左轨各组/条目直接落在页面底色上，没有整轨边框/blur/圆角容器，主项高度与树缩进也分别使用不同规格。这里是层级容器差异，不是单纯换树 icon。
- **影响与范围**：树缺实时更新会让目录导航与主列表状态分叉；树缺少原型拖放意味着不能用目录树直接整理文件，虽然 Flutter 主列表行仍有内部拖动到文件夹的 DragTarget。当前断点在 1180px 以下会隐藏整棵树，是样例 CSS 的响应式行为；此断点行为与树不可用问题分开记录。
- **主列表内容（部分已确认、部分待定位）**：原型文件夹副标题显示子项数量，Flutter `_fileKindLabel()` 对文件夹只显示“Folder”；原型 `modified` 展示短日期/相对日期，Flutter `_formatDate()` 固定输出 `YYYY-MM-DD`。表格列类别和 58px 行高已有对应关系；用户反馈其余列表内容问题已记录为待逐项定位，不能仅凭目前描述推断是某条数据、列宽还是筛选结果错误。
- **待核范围**：主列表真实数据/排序结果、共享/最近/收藏/回收站不同分区的副标题和权限标记、空态/加载态、grid 卡片与 1180px/短窗口下列表列折叠，需用用户当前运行态截图/步骤补齐；本报告不把此类待定位项冒充根因。

### P2：其余各页面逐页矩阵

| 页面/视图 | 原型源码结构 | 当前实现位置/结构 | 需纳入下一轮逐页对照的差异 |
|---|---|---|---|
| Splash | `Auth.tsx` 的 splash/安装/认证阶段；窗口切换与无边框过渡。 | `router.dart` boot route、`desktop_splash_page.dart`、BootGate。 | 动画时序、窗口背景、品牌图标与原型加载画面；桌面 window frame 边界。 |
| Login | `Auth.tsx` + `setup.css`：左图/右表单、自适应、TOTP/注册状态。 | `desktop_login_page.dart` 与 `login_page.dart`、auth challenge panel。 | 列宽断点、玻璃卡、表单焦点和错误状态需重新截图核验；登录挑战真实流程与原型静态演示差别单列，不改变认证契约。 |
| Setup | `Setup.tsx`：步骤栏、身份/安全/存储/完成步骤，抽屉/输入状态。 | `desktop_setup_page.dart` 与 `initial_setup_page.dart`。 | 步骤比例、内容滚动、安装 TOTP、错误提示和窄宽截断。 |
| Home | `Home.tsx`：Sky Hero、两张 Hero tile、Weather、四 KPI、影视/音乐/阅读/照片/文件/活动。 | `desktop_home_page.dart` + `desktop_home_sections.dart` / `desktop_home_lists.dart`。 | Hero 结构和壁纸透明态、Recent Photos hover 是已确认重点；其余 KPI/两列/照片空态/Activity 数据语义需要按真实数据状态核对。 |
| Movies Browse | `Movies.tsx::Browse`：cinema Hero、七分类入口、推荐轨道、Continue watching、空态。 | `desktop_movies_page.dart`, `desktop_movies_cinema.dart`, `desktop_movies_cards.dart`。 | 分类切换和 Hero 真实空数据时是否保持样例占位、卡片 hover/封面比/轨道间距、宽窄窗口截断。 |
| Movie detail | `MovieDetail.tsx` 与 `Movies.tsx::VideoPlayer`。 | `desktop_movie_detail_page.dart`, `desktop_movie_detail_actions.dart`, route `/video/:videoId` 和 `/play`。 | 沉浸详情的壁纸层级、封面、信息列、播放 controls/字幕菜单、返回路径和全屏 key。 |
| Series detail | 原型 Movies/detail 系列拓展的剧集列表/播放上下文。 | `desktop_series_detail_page.dart` 与分区组件。 | Hero、季/集列表、选中进度、字幕/音轨与 shell 沉浸边界。 |
| Photos Library / albums / places / favorites / trash | `Photos.tsx` 顶部分类和各 gallery 空态/网格。 | `desktop_photos_page.dart`, `desktop_photos_sections.dart`, feature pages。 | 单 item sizing、分组标题、视图切换、拖动顺序、批选、删除/撤销和加载 skeleton。 |
| Photo viewer / info / slideshow / editor | `Photos.tsx::PhotoViewer`, `.viewer`, 信息抽屉、filmstrip。 | `desktop_photo_viewer_page.dart`, photo detail/editor/slideshow routes。 | 路由是否真正 immersive；照片 contain/zoom/filmstrip、Info panel 进退动画和 keyboard。 |
| Album detail / picker | `Photos.tsx` 新建相册 Drawer 与相册内容。 | `desktop_photos_album_detail.dart`、album picker。 | 卡片比例、相册工具栏/批选/编辑抽屉、详情导航。 |
| Music Home / Tracks / Albums / Playlists / Queue | `Music.tsx::Music` tabs/rows/cards/queue，以及 `MetaEditor.tsx`。 | `desktop_music_page.dart`, rows/widgets/metadata drawer。 | 卡片光晕、曲目 hover actions、列表行高、曲集封面、详情抽屉字段和异步空/错误态。 |
| Now Playing | `Music.tsx::NowPlaying` 全屏 stage、art、播放列、Queue/Lyrics/Appearance。 | `desktop_now_playing_page.dart` / immersive route。 | 封面/唱片动画、播放控制、歌词切页、样例装饰与真实 metadata 缺省时降级；与底栏重复问题联动。 |
| Reader shelf/library | `Reader.tsx::Shelf/Library`：分类、grid/list、筛选、导入、空态。 | `desktop_reader_page.dart`, `desktop_reader_library.dart`, Reader feature pages。 | 书架密度、封面比例、行列切换、筛选与导入入口、未收录/加载状态。 |
| Book detail / immersive reader | `Reader.tsx::BookDetail`, `ReaderView.tsx`。 | `desktop_book_detail_page.dart`、Reader detail/view routes。 | 详情 cover/metadata/reading stats；章节阅读 typography、spread、TOC、工具条、沉浸边界。 |
| Files | `Files.tsx`：树、面包屑、列表/网格、筛选、排序、拖放、分享。 | `desktop_files_page.dart` + rail/rows/table/dialogs/actions。 | 树宽、分享权限、选中/拖入状态、列表 column、网格密度、预览壳、批量撤销和窄屏。 |
| Settings Appearance/Profile | `Settings.tsx` section rail、theme swatches、profile rows/form。 | `desktop_settings_page.dart`, `desktop_settings_more.dart`。 | 样例控件状态、全站 theme/accent 色、输入焦点、保存反馈与两列布局。 |
| Settings Backdrop / Weather | `Settings.tsx::BackdropSettings/WeatherSettings`，BackdropView 全局。 | `desktop_settings_backdrop.dart`, `desktop_settings_backdrop_library.dart`, `desktop_settings_weather.dart`。 | 当前 scope 逻辑、wallpaper 可见度、选择/预览抽屉、dim/blur slider、动态播放 pause、天气字段反馈。 |
| Settings Security / Notifications / Connected / Storage / About | `Settings.tsx` 的真实 section rail + cards。 | `desktop_settings_page.dart`, `desktop_settings_more.dart`, `desktop_settings_storage.dart`。 | 通知桌面隔离、会话行/2FA、连接卡片、Storage 图表/按钮、About 信息结构；需逐节复核。 |
| Admin Overview | `Admin.tsx::Overview`：4 KPI、14 天柱图、system health、role pills、Recalculate storage。 | `admin_overview_page.dart` 与 `admin_overview_desktop.dart`。 | 源码已接真实数据但数值语义、柱图颜色/tooltip/14 天刻度、存储概览卡是否移除及 recalculation 控件位置须截屏核验。 |
| Admin Identity | `AdminIdentity.tsx` users/roles tables、状态/排序、drawer、role editor。 | `admin_group_pages.dart`, `admin_users_*`, user/roles management。 | 用户 drawer/role drawer、状态分类/排序和输入样式；当前按分组聚合显示，需检查与六项导航结构的差异。 |
| Admin Media library | `LibraryManager.tsx` 独立分区。 | 无 `AdminSectionGroup.library`；相关代码仅在 `admin_operations_library.dart`/storage sources。 | 独立页面是缺项，拆解哪些 library cards/扫描/管理状态需要单独入口，后端有数据则沿用真实 API。 |
| Admin Operations | `Admin.tsx::Ops`, Task/Dead/Audit/Session/Logs single tabbar。 | `_DesktopOperationsHub` + `AdminTasksPage`/`AdminLogsPage`/Sessions/System logs。 | 确认实机双分类条来自哪里；每个二级内容应只保留原型一层 Ops 分类栏及内层筛选。 |
| Admin Configuration / Storage | `AdminConfig.tsx`, `Admin.tsx::Storage`；参数分组、Review/Save、locations/provider accounts。 | `admin_operations_config_*`, `admin_operations_external_storage.dart`, storage dashboards。 | 布局密度、参数分组、抽屉尺寸、可编辑字段和真实后端字段对应关系。 |
| Shared / File preview / Search / import drawers / confirmation dialogs | `Shell.tsx`, `ui.tsx`, `ImportDialog.tsx`, per-page Dialog/Drawer。 | route preview/search, `desktop_overlays.dart`, `desktop_media_import_dialog.dart`, feature dialogs. | Portal/z-order、popover anchoring、关闭/焦点返回、toast/undo、键盘 Escape、页面内 Overlay 和 Shell ownership。 |

## 全路由逐页核对矩阵

上表是模块索引；以下按当前 router.dart 的具体桌面路由展开。标为“无原型路由”的项目仍须将其窗口视觉映射到最相近的原型 Panel/Drawer/Overlay。原型为本地静态演示、Flutter 为真实数据时，只要求内容结构/状态反馈对齐，不要求伪造演示数据。

| 当前桌面路由/页面 | 原型位置及组成 | 当前源码证据 | 源码级差异 / 状态 |
|---|---|---|---|
| /boot 启动/引导 | Auth.tsx::Splash：品牌标记、文字、单条进度动画；DesktopApp 从 splash 转入 setup/auth。 | DesktopSplashPage、BootGate、DesktopBootSwitch。 | 产品启动加入服务器配置和认证状态门控，原型没有这些真实路由；视觉需对照动画时长、窗口底色和落位，不将门控流程误报为视觉缺项。 |
| /setup 首次安装 | Setup.tsx：单页管理员表单、账户信息/语言/时区、强度条、可选演示 2FA、提交状态。 | DesktopSetupPage：含 setup token/instance、账号、密码、确认、时区、语言和真实 TOTP 服务。 | 内容多出部署凭证与实例字段；原型 2FA 是 optional/demo，当前真实部署首个管理员受更强约束，需以产品安全策略保留功能但按样例重排结构。 |
| /login | Auth.tsx::Auth：左侧 artwork+两层 shade，右侧 420px 卡；≤900px 隐藏 artwork；用户名/密码后进入样例 2FA 卡。 | DesktopLoginPage：宽屏左 5/右 form pane，>900px 两列；左图 ClipRect 内 30s 1→1.14 Ken Burns；≤900px 仅表单；真实 challenge/Enrollment/PasswordChange。 | 源码修正了壁纸缩放越界：动画在 ClipRect 内，不改两列布局。原型 art 仅线性遮罩；暗主题 radial 背景在 auth 根层而非 artwork 内。当前两层 linear shade 可对应 art-shade；不应把根层 radial 搬到左图。2FA 文案/卡片状态须保留真实认证语义。原型 CSS 当前是单向 30s kenburns forwards，并非无限呼吸循环；若用户所指 prototype 已有新版循环动效，需以该新版源码为准。 |
| /server-setup 服务器配置 | 无独立原型页；样例的 setup/auth 只展示视觉。 | ServerSetupPage。 | 当前为产品新增独立配置流程；视觉按 Setup 表单/步骤控件风格核对，字段与部署契约不能用演示数据代替。 |
| /portal Home | Home.tsx::Home：Hero Sky、weather、4 KPI、continue watching、Evening listening、Currently reading、7 张 recent photos、Recent files、Activity。 | DesktopHomePage、desktop_home_sections.dart、desktop_home_lists.dart。 | Hero 缺原型两张带 artwork 的 action tiles；背景库开启时仍画 shade/框面。Recent Photos 当前在比例换算、hover grow 与标签字段(place→title)上不等价。KPI/Continue/Listening/Reading/Files/Activity 还需逐节核对空/加载/错误态和行列密度。 |
| /library 媒体入口 | 原型 Sidebar 直接导航 Movies/Photos/Music/Reader/Files；没有聚合 Library landing route。 | LibrarySpacePage。 | 产品新增聚合入口，无一对一原型页；需要把每张模块卡、分类入口、空库 CTA 与 Sidebar 导航逐项映射至原型 NAV，不把新 IA 误认为同构。 |
| /video 影视 Browse | Movies.tsx::Browse：cinema carousel、7 tabs、sort chips、Continue rail、Film/Series/Anime rails、导入、分类空态。 | DesktopMoviesPage、DesktopMoviesCinema/Cards。 | 7 个分类、导入入口及分档空态当前都存在，旧报告称“缺少”已过时。原型 carousel 固定精选并 7s 轮换，Flutter 从 API backdrop/recent 取前 3 项并在无数据时显示 skeleton/placeholder；布局相似不等于 artwork/轮播节奏相同。需要对照 For you 空库 Hero、继续观看为 0 时占位、分类切换滚动和 tab 标签。 |
| /video 分类状态 | Movies.tsx 的 Films/Series/Anime/Favorites/Watchlist/History 单页状态，Empty 由该 tab 决定。 | DesktopMoviesTab、_MoviesEmpty。 | 7 项枚举和 Series/Anime/Favorites/Watchlist/History 的空态已有代码。Movies 实体在 API movieCount 为 0 时由 recentMovies fallback，需检查空数据下“电影”列表是否错误复用 recentlyAdded；这是数据语义而不是缺少页面。 |
| /video/:videoId 影视详情 | MovieDetail.tsx::FilmDetail：大 backdrop hero、poster、评分/标签/进度、Play/Resume/From start、favorite/watched/watchlist、Overview/Cast/Files tabs。 | DesktopMovieDetailPage、desktop_movie_detail_sections/actions。 | 原型影视详情在 Movies 模块交互状态中，Flutter 使用独立 immersive route；需逐项比对 tabs、动作顺序、认证/API 失败反馈、Hero 尺寸和背景策略。routeBackdropPolicy 当前对 /video 使用 work 实色策略，遮掉全站壁纸。 |
| /video/series/:seriesId | MovieDetail.tsx 的 Series 分支/剧集详情与播放上下文。 | DesktopSeriesDetailPage 及 episode/subtitle sections。 | Flutter 拆出季/集/字幕/音轨管理，原型演示字段较少；需比较 Hero、剧集列表密度、选集状态、播放/字幕操作抽屉和 immersive 壳层。壁纸继承 /video 实色策略。 |
| /video/:videoId/play | Movies.tsx::VideoPlayer：Window 级 inset 0 overlay，播放/暂停、seek、字幕、音轨、键盘/idle chrome。 | MoviePlayerPage，DesktopShellMode immersive。 | 全屏 owner 的静态意图相符；必须验证在实际 window 下是否隐藏 app titlebar/sidebar/dock/playerbar、OS window chrome 的边界、seek/controls 自动隐藏和错误恢复。 |
| /photos 图库 | Photos.tsx：Library/Albums/Places/Favorites/Trash 顶部分段，媒体导入、筛选、分组网格、batch actions。 | DesktopPhotosPage、desktop_photos_sections/selection。 | 各 5 个一级 tab 和导入入口均存在；需对齐 density slider、日期分组/空态/分页骨架和批量工具栏。不应再记录“缺少导入入口”。 |
| /photos 单图网格状态 | Photos.tsx 为长度 1 的 Justified 增加 solo-note，并禁止 tile flex 扩张。 | desktop_photos_sections.dart::_layout 每行均 Expanded；没有独图旁注分支。 | 源码已确认差异：单照片构成一行时占满整行，缺少样例 metadata note。 |
| /photos 新建相册 | Photos.tsx::NewAlbum 以 Drawer 打开，表单校验重名并可接入预选照片。 | desktop_photos_selection.dart::_NewAlbumDrawer、_CreateAlbumCard、_CreateAlbumBorder。 | 当前已有整卡自绘虚线和抽屉，并按 hover 改描边/文字 accent；源码未见该卡额外 halo。此前“旧矩形控件/缺透明虚线”的问题不再能从当前源码确认，须用当前构建截图复核。 |
| /photos/albums/:albumId | Photos.tsx 的 Albums 子视图/专辑内容。 | DesktopPhotosAlbumDetailPage。 | 当前独立 route 展示详情/分享/删除，原型在 Photos 内部切换；IA/返回行为不同，内容栅格、toolbar、空相册状态需比较。 |
| /photos/albums/:albumId/add | Photos.tsx 的相册选择器内选择照片并添加。 | PhotoAlbumPhotoPickerPage。 | 当前独立 picker route；原型是图库状态/Drawer 式选择，核对多选确认、返回后选择保持、空态和批量反馈。 |
| Movies/Photos/Music 导入 | ImportDialog.tsx：From My files/From this device 两个 tab、选择列表、格式/大小、电影 metadata toggle、Import 按钮；提交后为每项排 task 并 toast，关闭 Dialog。 | DesktopMediaImportDialog 分页浏览 FileNode（page size 100、文件夹 breadcrumb、类型过滤、错误/加载/加载更多）；设备文件经 MediaImportButton 上传；三模块再通过 mediaImportQueueProvider 和 task waiter 异步创建媒体实体/更新列表。 | 入口三模块均存在，异步后台队列也存在；视觉/流程明显比 prototype 多真实浏览、分页、失败和队列状态。需比对 tab/列表/dialog 的尺寸和控件状态，同时保证上传进行中、取消、部分失败、后台解析完成反馈映射到样例 task/toast，不回退到旧同步/旧样式对话框。 |
| /photos/period/:year/:month 与 /photos/groups | 原型按日期/位置分组显示，未设独立 period/groups route。 | PhotoPeriodPage、PhotoGroupsPage。 | 两个是产品深层列表页；需把日期网格和地点入口样式映射到 Photos 分组/Places section，并检查返回与全屏 shell。 |
| /photos/:photoId Photo Viewer | Photos.tsx::PhotoViewer 经 Portal 到 .window；toolbar、prev/next、zoom/pan、filmstrip、slideshow、Info drawer、keyboard。 | DesktopPhotoViewerPage，desktop shell path matcher 应设 immersive。 | 功能集合有对应项，路由承载方式不同；按 prototype 的 Window 全屏覆盖边界核对。实机“壳层仍在”与静态 path 分支不符，需实测 URI/build。 |
| /photos/slideshow | 原型为 Viewer 内开关 slideshow。 | PhotoSlideshowPage 独立 route。 | 产品独立 route vs 原型 Viewer 状态；比对进度条、暂停/继续、键盘、到末张行为和退出时回图库位置。 |
| /photos/:photoId/edit | 原型 Viewer toolbar 提供 rotate/favorite/share/delete/info，不见独立照片编辑器 route。 | PhotoEditorPage，immersive。 | 原型无独立编辑页；按 Viewer 工具栏风格核对编辑器功能，不把产品新增编辑器当同构页。 |
| /shared/photos/:token、/shared/photos/item/:token | 原型没有公开分享链接页。 | PhotoSharedAlbumPage、PhotoSharedItemPage。 | 产品新增公开访问页面；需匹配 Share/Viewer 的 typography、loading/expired/error states，协议与权限不在视觉层面伪造。 |
| /music Music library | Music.tsx::Music：For you/Tracks/Albums/Playlists/Queue 状态，导入、album/playlist 卡、track table、metadata drawer。 | DesktopMusicPage、music rows/widgets/metadata drawer。 | 音乐导入入口当前存在；实际曲库来自 API。需逐态比较空库、专辑 mosaic、队列操作、Track hover actions、drawer 字段及分栏。用户报告的彩色 glow 要定位具体 widget/CSS；原型存在普通投影和 selected states。 |
| /music/now-playing | Music.tsx::NowPlaying：Window overlay，两列 album deck + controls、Queue/Lyrics/Appearance。 | DesktopNowPlayingPage/Deck，immersive path。 | 同为沉浸播放器但当前是独立路由、支持更真实的播放引擎与更多外观设置；核对 cover/deck 尺寸、歌词状态、Queue、所有 shell 隐藏和底栏唯一实例。 |
| /music/history、/music/scan | 原型无独立 History/Scan route；音乐历史/扫描只作为列表或操作状态。 | MusicHistoryPage、MusicScanPage。 | 当前为产品新增全页；视觉应沿用 Music section/任务状态，不能未经映射新增一套页面 chrome。 |
| /reader Reader overview/library | Reader.tsx：Overview/Library、shelf、reading stats、recent books、导入入口位于 PageHead 左侧、Empty。 | DesktopReaderPage：PageHead actions 顺序为 ReaderLibraryImportAction 再 Overview/Library segmented control。 | Import 按钮当前源码位置、upload icon 与 soft button 已符合“在总览/书库左侧”的历史要求，不应记作缺失。仍需比较文字、icon 尺寸、按钮高度和边距；真实异步解析状态另见 import status。 |
| /reader/bookshelf | Reader.tsx 内 Bookshelf/library 内容与筛选/排列。 | ReaderBookshelfPage。 | 原型是同页面视图，Flutter 有独立 route；核对 grid/list、分类/筛选、空态、加载 skeleton 与原型 tab 状态映射。 |
| /reader/stats、/reader/admin | 原型 Reader overview 内阅读统计/管理入口，无独立路由页。 | ReaderStatsPage、ReaderAdminPage。 | 产品新增页面；统计图/管理工具应复用样例卡片、空态、section typography，检查与原型 overview 信息重复。 |
| /reader/items/:itemId 书籍详情 | Reader.tsx::BookDetail：cover/metadata/progress、Read/Continue、Details/Chapters/Notes/Activity tabs、相关书籍。 | DesktopBookDetailPage，shell matcher immersive。 | 当前独立全屏 route 对应样例 book-detail 全视口；字段数据真实，样例有演示 Activity/Notes；核对 tab 顺序、首屏布局、章节进度/相关书籍空态。 |
| /reader/items/:itemId/chapters/:chapterId | ReaderView.tsx::BookReader：theme/type/column controls、TOC/notes/bookmark panels、page/spread/scroll modes、键盘。 | ReaderViewPage。 | 有真实阅读进度与加密笔记，样例只用静态章节；比较三种 mode、TOC/notes 抽屉、文字栏宽和沉浸键盘。 |
| /reader/comics/:itemId/read、/reader/pdfs/:itemId/read | ReaderView.tsx 演示 Comic/Book reader mode。 | ComicReaderPage、PdfReaderPage。 | Flutter 按文件格式拆两个 route，原型 reader 共用一个组件；比较同一 toolbar/content surface 和错误/空文件状态。 |
| /reader/items/:itemId/metadata | 原型 BookDetail 书籍 metadata 内容和 edit actions，没有独立路由页面。 | ReaderMetadataEditPage。 | 当前全页 metadata editor；映射到样例编辑控件/Drawer 后再核对字段布局、保存/取消/错误反馈。 |
| /reader/items/:itemId/import-status | 原型导入后仅 queue task/toast，不展示解析确认全页。 | ComicImportConfirmPage。 | 产品新增异步解析确认路由；需映射 ImportDialog、TaskPanel、Toast 的进度/结果视觉。 |
| /files 文件管理 | `Files.tsx::treeFolders/newFolder/rowEl`：244px 左树卡，树目录可进入/拖放/延迟展开；创建后同一 `files` state 同步更新树；面包屑、筛选、排序、list/grid、名称/子项/更新时间/容量/Access 列、批选与拖放。 | `DesktopFilesPage`、`desktop_files_rail.dart::_FolderTree`、`desktop_files_rows.dart::_FileRow`、`desktop_files_table.dart`。 | 树栏缺原型整块玻璃容器；树节点只点击/箭头展开，未挂 draggable/drop/长按；树的本地 `_children` cache 不随 createFolder 刷新，解释列表与树状态分叉。Folder 副标题是类型而非子项数，日期格式固定 `YYYY-MM-DD` 而样例用短/相对日期。其余用户所报列表异常逐项待具体截图/步骤定位。 |
| /files/preview/:fileId | 原型 Files 的详情/preview overlay（非独立主导航页）。 | FilePreviewRoutePage。 | 当前 route-level preview，需与原型 preview overlay 的尺寸、关闭返回、键盘、主壳遮挡和文件类型空态对齐。 |
| /s/:token 文件分享预览 | 原型仅有 Files.tsx::ShareDialog 配置分享，没有公开 token route。 | FileSharePreviewPage。 | 产品新增公开页面；沿用样例 modal/preview 视觉，核对过期/无权限/下载反馈。 |
| /profile?section=profile | Settings.tsx Profile：头像、name/email 表单、Reset/Save。 | DesktopSettingsPage profile section；使用真实当前用户资料。 | 字段对应；样例 PageHead 无副标题，当前 Settings PageHead 额外传 `desktopSettingsSubtitle`。样例 Save disabled 到 dirty/valid，当前真实资料保存状态需核对焦点、dirty 提示和错误 feedback。 |
| /profile?section=appearance | Settings.tsx Appearance：theme/accent/density/type controls。 | DesktopSettingsPage appearance section + appearance sheet。 | Settings 8 个分区的顺序与原型一致；样例四 accent Sage/Mist/Copper/Iris，当前 enum 有相同四类。需逐项比较 Light/Dark/System、swatch、字体/密度控件和保存反馈。当前 Appearance section 内容是否完全同构仍需把动态壁纸偏好与通用偏好区分核对。 |
| /profile?section=backdrop | Settings.tsx BackdropSettings + BackdropView：范围、库选择、静态/动态/透明度等。 | DesktopSettingsBackdrop/Library，DesktopBackdropScope。 | 全站 scope predicate 与 route surface work 策略冲突是已确认差异；light/dark、媒体/Utility scene 和 slider 实际值仍需核对。 |
| /profile?section=notifications | Settings.tsx 通知偏好。 | DesktopSettingsMore 通知 section；另有顶部 NotificationsPanel。 | 设置偏好与通知内容列表要分开比较；用户要求桌面通知 panel 样例化、移动端保留原系统中心。当前顶部面板仍读 notificationControllerProvider，桌面全页 /notifications 仍存在。 |
| /profile?section=security | Settings.tsx Security：登录保护、sessions/revoke、2FA toggle。 | DesktopSettingsMore 安全/会话 section。 | 必须尊重用户已明确的授权规则：普通用户自行开关 2FA，超管强制；管理员创建账号与用户注册的首登策略区分。表面/行样式尚需逐状态图核。 |
| /profile?section=services | Settings.tsx Connected services provider cards/connect states。 | DesktopSettingsMore Connected Services。 | 对照 provider icon/card、未连接/授权中/过期/重新授权状态；真实 OAuth 返回状态和错误文案不能用 prototype mock 填充。 |
| /profile?section=storage | Settings.tsx Storage section. | DesktopSettingsStorage。 | 用户历史反馈的 Storage 配置/存储视觉重做未逐张对照完成；逐项比 provider/location/容量图/设置 Drawer 与 Admin Storage 区分。 |
| /profile?section=about | Settings.tsx About & updates。 | DesktopSettingsMore About section。 | 核对版本/更新状态、检查更新动作、空/失败反馈和样例 section 卡片密度。 |
| /notifications | Shell.tsx::NotifPanel 为浮层，不是全页通知中心。 | NotificationPage 路由仍在 router.dart，并由桌面/移动共享入口可达。 | 桌面额外全页与 prototype information architecture 不同；桌面铃铛仍接系统通知 provider，需在未来实现阶段隔离 desktop visual surface，mobile 保留系统通知。 |
| /search、Ctrl+K command palette | Shell.tsx::Palette 是中心命令/搜索面板，搜索媒体库/文件/命令。 | MobileSearchPage route + Shell search入口；desktop panels/Palette。 | 当前 search 是全页 route/真实跨域检索，与样例 palette overlay 的尺寸/关闭/结果结构不同；需要 source matching overlay mapping。 |
| /tools | 原型 Shell task panel/shortcuts/context menu，没有 WorkspaceTools 全页。 | WorkspaceToolsPage。 | 产品新增页面；视觉映射至 Shell Panel，不应生成第二套独立 system-tools 导航。 |
| /settings、/profile/notifications、/notifications-tasks、/tasks、/activity 等兼容地址 | 原型 Settings 是主页面，通知/任务只在 Shell panel 中打开。 | router.dart 将 /settings 重定向到 /profile?section=appearance、/profile/notifications 重定向到通知偏好；旧任务/活动地址重定向到 /notifications。 | 是 URL 兼容别名，不是独立 UI 页面；视觉责任在最终落点 route。桌面 `/notifications` 落地后仍是整页，是用户要求下的实际信息架构差异。 |
| /admin Overview | Admin.tsx::Overview：4 KPI、14 日 bars、health、role pills、Recalculate storage。 | DesktopAdminOverview 读 summary+analytics；4 stat cards、14 日图、health、roles、Recalculate card 均存在。 | 旧报告“缺 14 天柱图/缺重算卡”已过时。当前第四张 KPI 是 Storage，样例也有 Storage KPI；是否另有额外 Storage overview tile 需确认实机所指的具体卡片。图表真实数据/加载 skeleton 与样例演示 bars 的布局不同，柱数应固定 14。 |
| /admin Identity/users | AdminIdentity.tsx users table、Status `All/Active/Disabled` chips、Role chips、search、Sort select、create/edit UserDrawer、quota dialog。 | `admin_users_desktop.dart::_DesktopUsersPanel` 有 Role 与 Active/Disabled filters、username/storage/last active sort select、Create/Edit User Drawer、quota Modal。 | “缺少状态/排序/抽屉”不是当前源码可确认的功能缺项；已存在相同类别控件，但 Flutter 将搜索、角色/状态 ChipGroup 和排序选择器放在 Wrap toolbar，prototype 使用 Toolbar + FilterChips + sort select。需比较具体排列、密度、控件皮肤、字段列和编辑/创建 drawer 表单，不应再写“列表没有状态分类/排序”。 |
| /admin Identity/roles | AdminIdentity.tsx role cards、permission summary/grid、RoleDrawer/permission tree。 | admin role management pages/drawers/permission tree。 | 当前已存在角色卡片、权限网格与 Role Drawer；逐项比较 role card 高度/顺序、权限分组密度、built-in/custom 状态、drawer width、保存/校验/未保存状态。API权限语义保持真实。 |
| /admin Media library | Admin.tsx::sections 的独立 library + LibraryManager sources/review/scan drawers。 | AdminSection enum/group只有 overview/identity/operations/configuration/storage；相关媒体来源管理置于 admin_operations_library。 | 源码已确认：原型六分区里独立 Media library 缺失；现有媒体来源页面不等价于独立 LibraryManager 工作区。 |
| /admin Operations/Tasks | Admin.tsx::Ops tabs 中 Tasks，status/type filters、search、CSV、pager。 | DesktopOperationsHub + AdminTasksPage。 | Flutter hub另有同级 segment并向子页传 hide selector；双栏仍以运行状态确认，但 mock live/history 与真实任务状态、Retry/Export状态需逐列映射。 |
| /admin Operations/Dead letters | Admin.tsx::Ops Dead tab，状态/重试/过滤。 | Admin dead-letter page。 | 独立页内重复栏需检查；比对 failed payload details、retry/delete confirmation、空态和 table columns。 |
| /admin Operations/Sign-in audit | Admin.tsx::Ops Audit tab，事件、时间、IP/状态等表。 | Admin sign-in audit page。 | route group 映射相符；真实审计字段及筛选项可能与 prototype mock 不同，行高/状态 chip/table toolbar需比对。 |
| /admin Operations/Sessions | Admin.tsx::Ops Sessions tab，session rows/revoke。 | Admin session management page。 | 核对 active/revoked/expired 状态、批量撤销确认、IP/device metadata、空态和分类栏重复。 |
| /admin Operations/System logs | Admin.tsx::Ops Logs tab、level/source filters、details/export。 | AdminLogsPage + hideDesktopTabSelector。 | 需确认 hub tab 与 logs 内部 tab是否重复；行级等级色、details drawer、过滤/分页对照。 |
| /admin Configuration | AdminConfig.tsx 分类设置、Review/Save。 | admin_operations_config_*。 | 逐 section 对照控件类型、保存/取消/dirty diff、危险操作确认；原型 mock field不是后端 schema，缺字段要另列接口缺口。 |
| /admin Storage | Admin.tsx::Storage locations/provider account rows + Add location/account Drawer。 | admin_operations_external_storage/storage pages。 | page tree exists but visual/fields需逐项核；与 Settings Storage 不能合并。provider secrets不得回显，保留样例的配置抽屉交互。 |
| 全局 Shell、标题栏/侧栏/Dock | Shell.tsx::NAV 六项、46px titlebar、232/64px sidebar、detail Dock、window controls。 | desktop_shell.dart、desktop_title_bar/sidebar/panels、window controls。 | 页面信息架构并非一一相同；按图标字形/标签/尺寸/透明底/模糊/active/hover/badges逐项量化。原型 theme tokens为 dark #0b0e11/light #eef0ec 和四 accent，Flutter tokens需对照实际平台渲染。 |
| 全局 Buttons/Inputs/Slider/Segment/Toggle | ui.tsx primitives；按钮34px/r10，输入40px/r10及 focus ring，seg/slider/toggle各有状态反馈。 | desktop_controls.dart、desktop_fields.dart、desktop_controls_slider.dart、desktop_select.dart。 | slider源码默认使用 accent fill 与可显隐 thumb；若某调用将 trackFill 关闭需在逐控件表列出。输入 focus ring/鼠标 hover 属样例明确效果，禁止一概清除；需逐调用对比颜色和形状。 |
| Modal/Drawer/Confirm | ui.tsx Modal 460px / wide760px；Drawer默认480px从右侧进场；Confirm/Portal有 Escape/focus行为。 | desktop_dialogs.dart、desktop_overlays.dart、各 feature dialog/drawer。 | 当前跨 Flutter Overlay/Route/Dialog 多实现，不能按同名类推等价；按宽度、圆角、背景 blur、backdrop、Esc/点击外部关闭、焦点恢复、footer位置和窄窗适配对照。 |
| Loading/Skeleton/Error/Empty/Toast | ui.tsx::useSkel 保持真实布局并把各卡/行转成尺寸对应 skeleton；Empty size sm/md/lg；Shell::Toasts 带 Undo/task action。 | DesktopSkeleton、DesktopEmpty/ErrorView、DesktopToast，以及各页面 AsyncValue 分支。 | 用户报告骨架位置/设计不对仍是跨页差异；应按 Home/Movies/Photos/Music/Reader/Files/Admin每个异步区分别对照 skeleton 的占位尺寸/位置/数量和 error retry，不用单个通用加载状态代替样例组件结构。 |
| Context menu/Task panel/Palette/Shortcuts | Shell.tsx 提供 Window 级 context menu、task panel、palette、shortcuts、toast。 | Desktop overlays/panels、Notification/task surfaces、keyboard handlers。 | 视觉 owner 与 route/shell z-order、Escape、外部点击、焦点返回须矩阵验证；全屏页面不应被非样例常驻 chrome 覆盖。 |

## 用户已报问题闭环表

下表把此前分散在多轮消息中的实机问题合并，保留每项当前静态证据和判定边界。它是防止漏项的索引；详细源码位置、页面上下文和原型映射见上方 P1 分析及全路由矩阵。

| ID | 已报问题 | 当前源码对照结论 | 判定 |
|---|---|---|---|
| U01 | Home Hero 缺少样例卡片；启用背景库后应透明 | 已新增两张 `.hero-tile`（封面/文案/进度），壁纸态改透明面 + 白 20% 边 + 仅底部长渐变，不再绘制天象。 | 已实现；运行态截图待补 |
| U02 | 侧栏/顶部栏模糊材质、icon、文本不一致 | 46px TitleBar、232/64px Sidebar 几何值与原型一致；导航项目和 icon registry 映射并不相同。逐 glyph、标签、透明底/blur、hover/active/badge 仍需逐项记录。 | IA 已确认不同；造型细节待逐项源码/运行态验收 |
| U03 | 全站背景在 Movies、Admin、Settings 未生效 | 桌面路由策略改为 content/staticContent，实底 surface 不再覆盖壳层壁纸；回归测试断言所有桌面策略 `visible`。 | 已实现；截图待补 |
| U04 | Home 最近照片 hover 不符合样例 | 改为按比例分配宽度（hover=3×），600ms 过渡；标签取 `gpsLocation` 地名。 | 已实现；hover 运行态待验 |
| U05 | Admin 缺少 Media library | 新增第六分区 `library`，`AdminMediaLibraryPage` 复用库源扫描/最近扫描摘要；侧栏、移动底栏、URL 段与权限齐备。 | 已实现；抽屉级视觉待核 |
| U06 | Admin Operations 出现双分类栏 | Hub 已有一级分段，嵌入子页传 `hideDesktopTabSelector:true`；用户运行态仍看见重复分段。具体重复控件由权限/当前子页/运行 build 决定。 | 运行态症状已知，源代码触发链未定责 |
| U07 | 底部播放器双层、宽度/控件/功能不一致 | Flutter 静态只有一个 `DesktopPlayerBar` 调用；按外层约束减两侧 margin 后，可见最大宽 1080/860px 与原型一致。控件差异及第二层来源静态未定位。 | 可见宽度非源码差异；重复与交互待运行态定责 |
| U08 | Photos 单图铺满一行，hover/长按/批选不符 | 单图改按原比例 + `.solo-note` 旁注（标题/地点/相机/曝光），窄窗换行。 | 单图已实现；手势待运行态核验 |
| U09 | 桌面通知要与移动端系统通知隔离 | 桌面标题栏/面板和 `/notifications` 仍读通知域 provider；样例桌面交互是 Shell NotifPanel。数据服务可保留，差异在桌面呈现/入口 owner。 | 源码已确认耦合 |
| U10 | Music 卡 hover 出现样例没有的光晕 | 不能用“全局没有光晕”概括原型：样例有投影、选中层、slider thumb/focus ring 等局部效果；通用卡片额外彩色 glow 是否存在要定位 Flutter 实际绘制控件。 | 具体 glow 尚未逐控件定位；不做全局删除结论 |
| U11 | Viewer/详情/播放时仍显示 Sidebar、Titlebar、Player | Router/`DesktopShellMode` 对主要沉浸路由有 immersive 分支，但它仍处于 `DesktopWindowChrome` 边界；静态意图与用户实机相反。 | 运行态症状与当前静态结构冲突，须核运行 path/build/owner |
| U12 | Movies 结构、分类/空态/Hero 缺失 | 七分类、导入按钮和分档空状态已存在；Flutter 用真实最近媒体构建 Hero，原型用精选轮播/演示数据。空库 Hero 和 rail 排列语义不等价。 | “缺组件”旧结论过时；数据选择与构成仍有差异 |
| U13 | Movies/Photos/Music 导入仍旧样式，要求异步 | 三模块入口、FileNode 分页浏览、设备上传、队列 controller 和 task 等待均已在源码中。Dialog 内视觉、部分失败/取消/后台继续与样例 task/toast 的映射尚未一一核过。 | 异步链路存在；视觉/失败状态未完成对照 |
| U14 | Reader 导入按钮位置、名称/icon、样式不对 | `DesktopReaderPage` 的 PageHead actions 将 Import action 放在 Overview/Library segmented 前；upload icon 与 soft variant 已在源码。 | 位置/icon 基本满足历史要求；尺寸/文案待截图验收 |
| U15 | Drawer/Dialog/Input/按钮/焦点/旧矩形样式不统一 | 样例 `ui.tsx` 共享 Modal/Drawer/Confirm/Button/Field primitives；Flutter 有多套 Dialog/Drawer/Overlay 和 feature-local controls，统一类名不能证明同材质/尺寸。样例 field focus 有明确 ring。 | 跨组件源码差异范围已确认，须按 primitive 建逐项表 |
| U16 | 全页面骨架位置/设计错误 | 样例 `useSkel` 用真实布局的卡/行结构替换内容；Flutter 各 AsyncValue 页面自行返回通用 Skeleton 或 feature skeleton。当前矩阵列出 Home/Movies/Photos/Music/Reader/Files/Admin，具体尺寸分支待补图。 | 结构机制已确认不同；逐页面细节待对照 |
| U17 | Admin Overview 数据与样例不一致、缺柱图/重算卡、多存储卡 | Flutter 有 4 KPI、14 天 dailyUploads 图、Recalculate card；样例同样有 Storage KPI。用户所说“多出的存储概览卡”尚未从实机截图对应到具体 widget。 | 部分旧问题已过时；额外卡需截图指认 |
| U18 | 新建用户/编辑角色应抽屉；列表要状态分类、排序 | 原型 `AdminIdentity.tsx` 使用 user/role drawers、Status `All/Active/Disabled` chips、Role chips 与 Sort select；当前 `_DesktopUsersPanel` 有 Active/Disabled 和角色筛选、用户名/容量/最后活跃排序、Create/Edit User Drawer、Role Drawer。 | “缺状态/排序/抽屉”不是当前源码可确认的功能缺项；Flutter 把筛选、搜索、排序放进可换行 Wrap，视觉排布、表格列与抽屉表单仍需对照。 |
| U19 | Storage 配置页/Storage 管理页不符合 | Settings Storage 原型是单一用量分布卡、Find duplicates；Flutter 读真实 storage stats 并分类型绘制、执行真实 duplicate scan。Admin Storage 原型是 location/provider rows + add drawer，与 Settings Storage 是两页。 | 数据/交互语义明确不同；容器布局和 fields 仍待逐项比对 |
| U20 | 拖动 slider 后已选值无颜色 | Flutter DesktopSlider 默认 `trackFill=true`，按当前 value 绘制 accent fraction；原型 `.slider .track b` 同样按 value 填充 accent，drag 时取消 width transition。当前源码未证实“没有填色”，需用复现路径检查调用是否关闭 `trackFill` 或 provider value 是否回写。 | 设计意图一致；运行态故障待定位 |
| U21 | Security/Sessions、2FA 设计不对 | 原型为 Security 区内 Change password、2FA toggle、sessions；Flutter 真实认证/会话页面保留同类能力。产品规则已经由用户明确：普通用户可自选 2FA，超管强制开启；管理员创建账号首次登录改密，与自助注册用户分开。 | 视觉需对照；产品权限规则已明确，不得改向 |
| U22 | Connected Services 完全不符 | 原型分 Music platforms/Other，含 NetEase QR link、Local library scan、Last.fm toggle；当前真实服务 provider/OAuth 生命周期不一定与演示 provider 相同。 | 信息结构/真实 provider 映射需逐 service 比较；不可伪造服务数据 |
| U23 | 登录页遮罩白边、壁纸光晕/默认图/缩放/自适应不符 | `BundledWallpaperPoster` 读取 `assets/backdrops/default_wallpaper.jpg`；该资源与用户提供的 `StockSnap_GI4HC0TIXR.jpg` SHA-256 相同。Flutter art 在 ClipRect 中做 transform、>900px 两栏，≤900px 单表单；当前样例源码是 root dark radial + art linear shade、≤900px 隐藏 art、30s 单向 Ken Burns。用户之前要求的“呼吸式”与当前原型源码不一致，需以最近优化的原型文件为准。遮罩覆盖/全屏布局症状与静态约束意图冲突，需用当前运行 build 核实。 | 默认壁纸资源已确认一致；动效/白边/响应式症状待运行态验收 |
| U24 | 详情面板收放时右侧溢出 6.8px | Flutter Dock 在收放时固定内部 348px 内容宽度；用户报告的 RenderFlex ancestor/触发帧尚未获得。 | 运行态待定责，见 P1 详情坞条目 |
| U25 | Photos 与其他卡片 hover 的多余光晕 | Photos 新建相册源码是整卡 dashed painter，hover 改描边/文字色，未发现该 card 有额外 halo。样例其他局部控件确有 hover/focus ring；应以控件为单位记录。 | Photos 新建相册未发现 halo 源码证据；其余逐控件待核 |
| U26 | Files 左侧目录树样式完全不对 | 整轨改为玻璃面板（圆角 20 / `--panel` / 1px / blur 20）；行高、缩进、gap 分隔线、存储用量按样例重排。 | 已实现；截图待补 |
| U27 | 新建文件夹后结构树无变化 | 树按当前目录文件夹签名失效缓存并重取；展开时强制刷新该层。 | 已实现；运行态待验 |
| U28 | 无法长按/拖动结构树元素移动 | 树行加 Draggable/DragTarget，落点高亮、650ms 悬停展开、←/→ 键盘；根条目接收落点。 | 已实现；拖放运行态待验 |
| U29 | Files 主列表内容和呈现仍有问题 | 目录副标题改真实子项数（后端新增 `childCount` 批量统计），日期改 Today/Yesterday/短月日，行内补星标与分享。 | 三项已实现；其余症状仍待具体截图定位 |

### 覆盖边界

- **页面/路由覆盖**：当前显式 GoRouter 路由、兼容 redirect、Settings 8 分区、Admin 6 个原型分区映射、共享 Shell 与主要 overlay 均有矩阵条目；Files 树、树列表同步和主列表状态已拆成独立差异项。
- **源码结论覆盖**：已把能静态证明的结构/尺寸/数据绑定列为确认差异；“需要比较”用于源码不足以判定的动态、条件或实机症状，不能误读为该页面已像素级验收。
- **运行态完整度**：没有原型和当前应用同分辨率截图、不同主题/locale/缩放、空/加载/错误/超长数据、hover/长按/拖拽/键盘/窗口resize 的逐状态实测；本报告因此不是截图像素审计或故障已修复声明。
- **后端完整度**：已核对 UI 直接消费的代表性模型/Provider，但尚未穷举 Spring Controller、DTO、数据库迁移和权限契约；只有在该审计完成后才能断言缺少后端接口。

## 数据绑定与后端接口观察

本节只列出当前 UI 源码能证明的绑定；没有完成所有 Spring Controller/DTO/数据库表的接口审计，因此不把“尚未查到”写成“后端缺失”。若后续确认样例要求的字段确实没有服务端来源，再登记 API/DTO/迁移缺口。

| 功能 | 当前数据路径 | 与原型字段/状态的关系 |
|---|---|---|
| Home Hero movie tile | DesktopMoviesPage 从 MovieDashboard.recentlyAdded 取带 backdrop 的前三个条目作为 heroItems；无项时 fallback 到 movies。 | 原型按 featured 集合轮播。当前页面未使用专门的精选排序字段；如果产品需要管理员/推荐服务控制 Hero 顺序，当前 UI 数据路径尚未表达该契约，应核查并设计 API。若“取近期有 backdrop 条目”即为要求，则无需新增接口。 |
| Home Recent Photos | DesktopPhotoStrip 从 PhotoItem 显示 title 和宽高比。PhotoItem 同时持有 dateTaken、GPS 坐标/位置元数据。 | 原型 hover 标签字段是 place。当前 title 与 place 不保证同义；需检查现有 gpsLocation 是否含可展示地点名称/后端反向地理编码能力。当前证据首先指向字段绑定差异，不能直接断定缺 API。 |
| Admin uploads 14 days | AdminOverviewDesktop 消费 AdminAnalytics.dailyUploads；空数据走 14 根 skeleton bars，异常显示 retry。 | 14 天数据接口和 UI 状态已有明确模型，不支持“缺柱图数据接口”的结论；剩余主要是图表视觉、日期刻度和真实数据长度校验。 |
| Movies/Photos/Music imports | 三页面共享 MediaImportButton；本机文件进入 upload provider，FileNode 导入经 MediaImportQueueController 编排异步导入，页面等待对应 task 并刷新实体。 | 当前已具备异步导入链路。各媒介 filter、部分成功/失败、取消/关闭后的任务继续行为需要对照样例 ImportDialog；不得把样例静态 candidates 当成真实后端数据。 |
| Desktop notifications | 顶栏 NotificationsPanel 消费 notificationControllerProvider，/notifications 仍有 NotificationPage。 | 数据 API 可保留；已确认的差异是桌面交互/路由仍与旧通知中心耦合。后续可只替换桌面呈现层而不推断要删除通知后端。 |
| Reader page position / total pages / remaining time | `ReaderView.tsx` 示例把搜索命中定位到页，并显示阅读进度/余时。 | 既有 API 审阅记录未找到可稳定提供整本总页数/阅读余时的字段；当前阅读状态主要按章节与字符 offset 保存。 | 页面/余时差异可能是数据契约缺口，不能用样例固定值冒充生产值。若要复现，需要先确定统一分页/预计时长算法及对应数据/API 契约。 |
| Files 预览与公开分享 | `Files.tsx` 可显示文件详情/预览；分享表单提供原图质量与位置元数据策略。 | 普通 Files 分享 DTO/DB 已保存 `originalQuality`、`includeLocation` 等策略；既有审计记录指出后端尚未对实际文件字节生成原图尺寸副本或剥离 EXIF/GPS。 | 这是后端处理能力缺口，不等于缺少请求字段；不能宣称策略已作用于下载内容。 |
| Movie file path / series metadata | `MovieDetail.tsx` 演示 File location 与更完整的编辑字段（Title/Genre/Year/Runtime/Rating/Cast/Poster/Synopsis）。 | 既有审计记录指出影片文件 API 返回文件名/大小/媒体信息但没有规范化库路径；主影片元数据编辑已持久化字段，系列编辑接口仍只覆盖标题与简介。 | 路径显示不可造假；如样例规范路径/剧集字段是硬性要求，需评估真实 API、权限及数据来源后登记后端契约。 |
| Home Library aggregate | 原型 Home 展示 Library 指标和今日新增。 | 当前首页总量按影片、照片、音乐与 Reader 条目汇总；不含 Files。 | 若样例语义包含 Files，则 dashboard aggregation/API 缺字段；若 KPI 指媒体书库而非全部文件，则属于计数口径问题。需按原型字段语义确认。 |

## 全局系统性差异

1. **路由与页面容器不是一套信息架构**：原型主空间以 `Shell.tsx::NAV` 六项组成；Flutter 桌面路由已引入 Portal、Library、Profile、Admin 与模块全屏 route。需要记录明确映射，避免以路由存在推断页面层级等价。
2. **共享 chrome 有多个 owner 风险**：shell host、模块页面、immersive overlay、窗口 chrome 和 mobile-hosted route 同时存在；播放器和查看器的实机反馈说明需要以一张 route × shell visibility 矩阵作为权威，当前源码意图未通过实机证明。
3. **Backdrop 画面由三层共同决定**：scope predicate、根 Wallpaper layer、页面自身不透明容器。仅把范围设为 all 不足以保证页面实际可见。
4. **设计语义混淆**：样例中存在 accent selected ring、黑色投影、专辑唱片中心点和歌词光影等局部效果；用户明确规定“只有样例本身有的效果可保留”。不能做全局零阴影/零 blur，也不能把某页的强调效果复制到样例没有的 hover 控件。
5. **真实数据与演示排版分离**：结构、占位、字段顺序应按样例；数值沿真实 API，不得使用演示统计数值伪装后端状态。没有对应 API 时要在后续阶段标注缺口。

## 下一步审查/实现顺序

1. 先复现并定责 shell visibility、播放器重复和 backdrop stacking。这三项影响多个页面；形成路由矩阵与截图，不同时改各页面局部样式。
2. Home：Hero、Recent Photos hover、空/加载态、启用 backdrop 的两种状态。
3. Photos：Library 单项宽度、hover、长按、批选、viewer、filmstrip、album drawer；逐项比较 dark/light 和实际鼠标状态。
4. Music：单一底栏、控件规格与功能、封面/Track hover 无额外光晕、Now Playing。
5. Admin：六项主分区（含 Media library）、Overview、Operations 单分类栏、Identity drawers/filters、Config/Storage。
6. Movies、Reader、Files、Settings、Login/Setup、通用 drawers/dialogs 按本报告页面表逐页核对。

除用户明确要求提交当前工作区外，本报告没有执行代码修复。下一阶段先完成统一截图基线，再进入单页差异实现。

## 2026-11-19 第四批：底部播放器双层根因与收口

- **用户反馈**：底部音乐播放器明显两层，底部有模糊玻璃溢出，宽度/功能/样式与样例不符。
- **源码取证**：原型终值是 `desktop.css:229` → `extra.css:8` → `more.css:4-9` → `polish.css:138` 的叠加结果：面板宽 1080（compact 860）、高 66、圆角 20、居中且两侧至少 20px；底部 14px；clearance 116；队列键是 `Shell.tsx:280` 的 `setDock(!dock)`。
- **根因**：Flutter 在 `DesktopGlassSurface` 内放了一个带左右 margin 的面板，玻璃背板因此比可见面板宽 40px，视觉上就是“面板底下又垫一层玻璃”；旧 token 1120/888/104 还把 margin 算进了面板宽度。
- **修正**：`LayoutBuilder` 直接算 `min(panelMax, viewport - 2*margin)`；阴影交给非裁剪外层，玻璃层与描边面板同宽、同高、同圆角，玻璃内部不再出现 margin；队列键改为可再次收起；曲目 Tooltip 移到整个按钮；展开键用 `desktopExpand`。
- **验证**：`test/app/desktop/desktop_shell_test.dart` 新增 3 条，锁定单一玻璃、1080/860 宽度、居中坐标、完整控件组与队列 toggle；`test/app/desktop` 179 全绿，`test/app` 358 全绿，`test/features/admin|files|music` 986 全绿；播放器改动 `flutter analyze` 0 issue。
- **未验证**：运行态截图、hover/缩放/主题切换下的实际玻璃合成仍未采集；本条只声明源码与 widget 层收口。
