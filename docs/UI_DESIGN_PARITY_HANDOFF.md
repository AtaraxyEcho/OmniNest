# OmniNest Desktop 原型对齐交接

- 日期：2026-11-19（第二轮：审查 + 首批源码实施）
- 当前代码基线：`6b7281713 Align desktop UI and backend workflows` + 本工作区未提交改动
- 当前工作区：共享壳层、Home、Photos 单图、Files、Admin 六分区已实施；见下方"本轮已实施"。
- 权威原型：`D:\Development\Project Collection\UI Design\OmniNest Desktop UI UX`，以当前 `src/desktop/*.tsx` 和 CSS 源码为准；`imgs/dark`、`imgs/light` 只作为视觉核对参考。
- 当前完整差异清单：[UI_DESIGN_DIFF_REPORT.md](UI_DESIGN_DIFF_REPORT.md)
- 历史交接记录：`UI_DESIGN_PARITY_HANDOFF_ARCHIVE_2026-11-18.md`，保留此前各阶段实施/验证流水；本文件记录当前审查范围与接手状态。

## 本轮已实施（2026-11-19 第二批）

1. **全站壁纸**：`routeBackdropPolicy` 桌面分支改为影视/音乐 `content`、照片/阅读 `staticContent`、系统页 `content`；`/admin`、`/profile`、`/video` 不再被实底路由表面遮住。回归测试同步更新。
2. **Files 左树**：整轨玻璃面板（`.fx-tree` 圆角 20 / 半透明底 / 1px 边 / blur 20）；导航行 34、树行 32、缩进 14、gap 分隔线；树节点 `Draggable`+`DragTarget`、落点高亮、650ms 悬停展开、←/→ 键；根条目接收拖放；展开即重取该层，并按当前目录文件夹签名失效缓存（修复新建目录后树不刷新）。
3. **Files 列表**：后端 `FileNodeDto.childCount`（`countChildrenByParentIds` 一次性分组统计）驱动目录副标题 "N items"；更新时间改 Today/Yesterday/短月日；行内补星标与分享按钮（回收站禁用）。
4. **Home**：新增 `.hero-tile` 双卡（封面 52 / 文案 / 3px 进度条 / 悬停上浮）；Hero 高度 `clamp(380,46vh,500)`、径向+线性暗角、`clamp(26,3.4vw,44)` 内距、天气卡 264 进 grid；壁纸态透明面 + 仅底部渐变；照片条按比例分配 + 600ms 过渡 + 地名标签。Hero 已拆为 `desktop_home_hero.dart`（part）。
5. **Photos**：单图 `justified.solo` + `.solo-note`（标题/地点/相机/曝光），不再铺满整行。
6. **Admin**：新增第六分区 Media library（`AdminSectionGroup.library` / `AdminSection.mediaLibrary` / `AdminMediaLibraryPage`），侧栏与移动底栏、URL 段、权限、分区切换失效均已接线。

### 追加（测试套件恢复 + 布局缺陷）

- 桌面夹具已对齐当前源码，`flutter test test/app/desktop` 全绿；顺带修掉两个真实布局崩溃：`DesktopSelect` 在 `Wrap` 中的无界 `Expanded`、`DesktopDrawerFrame` footer 的无界 `Row`。
- Files 网格卡片按 `extra.css:88-92` 重排（84 图舱 / 居中名称副标题 / 左上勾选 / 右上星标分享更多 / 悬停上浮）。
- 管理台运行任务统计改用 "Running tasks"；首页 golden 因 Hero 改版重录。
- Reader 总览改为「继续阅读 62% + 洞察面板 38%」双栏（含 14 天柱图）；Music 主视觉频谱改为贴底通栏 90px/56 柱，眉标 `Playing from {album}`。

### 本轮验证

- `flutter gen-l10n` 通过；`dart analyze` 改动文件无问题；`flutter analyze --no-pub` 的 `lib/` 无问题（18 条 error 全在测试夹具）。
- 通过：`route_backdrop_policy` + `route_surface_transition_wash`（8）、`file_optimistic_update` + `file_browser_controller_append`（12）、`file_list_row_target` + `files_workstation_components` + `files_table_view`（25）、admin 三分区（9）。
- 后端：`mvn -f backend/pom.xml -q -pl omninest-file -am -DskipTests compile` exit=0。
- 未跑：桌面 widget 套件（`desktop_test_harness.dart` 与源码签名漂移，基线即红）；运行态截图/拖放/hover/resize；后端 DB 级 IT。

## 用户要求与产品约束

- 一次处理一个页面/共享层，完成当前阶段再继续下一阶段。
- 必须按样例源码对齐结构、尺寸、颜色、反馈、交互和状态，不用“真实 API”作为偏离布局的理由。
- 真实后端没有数据能力时再明确指出缺口，避免演示值假装真实状态。
- 原型没有的光晕不新增。原型确实使用了局部投影/模糊/选中环时，先按样例还原，不能全局删除原型有效的层次。
- 桌面系统通知与移动端通知分开：移动端保留原系统通知；桌面端按 `Shell.tsx::NotifPanel` 重构交互。
- 详情、viewer、play、read 等沉浸内容以原型全屏范围为准；侧栏、顶栏、dock、播放器的显隐必须逐路由验证。
- 新建差异报告需记录每页的原型证据、当前实现、差异、影响、优先级和验证状态。

## 原型页面索引

| 区域 | 原型源码 |
|---|---|
| App/路由/阶段 | `src/desktop/DesktopApp.tsx`, `Auth.tsx`, `Setup.tsx` |
| 全局壳层 | `Shell.tsx`, `ui.tsx`, `icons.tsx`, `desktop.css` |
| Portal/Home | `Home.tsx`, `Sky.tsx` |
| Movies | `Movies.tsx`, `MovieDetail.tsx` |
| Photos | `Photos.tsx`, `reorder.tsx` |
| Music | `Music.tsx`, `MetaEditor.tsx`, `musicLib.ts`, `more.css`, `npstyle.css` |
| Reader | `Reader.tsx`, `ReaderView.tsx`, `reader.css` |
| Files | `Files.tsx`, `fileTree.ts` |
| Admin | `Admin.tsx`, `AdminIdentity.tsx`, `AdminConfig.tsx`, `LibraryManager.tsx`, `logs.ts` |
| Settings | `Settings.tsx`, `BackdropView.tsx`, `Wallpaper.tsx` |
| 所有页面样式 | `desktop.css`, `extra.css`, `more.css`, `polish.css`, `setup.css`, `select.css`, `reader.css`, `npstyle.css` |

## 初始 11 项实机反馈状态（只作入口，不是完整差异清单）

以下是新的交接状态，不表示修复完成：

1. **Home Hero**：源码证实 Flutter 的 Hero 与原型双图 Hero tile 结构不同；壁纸启用时 Flutter 仍画渐层遮罩与卡片外框，透明度语义需调整/验证。
2. **侧栏/顶栏**：拆件与图标体系不同；需比较每一个 glyph、尺寸、blur、selected/hover、badge 和留白。尚无同窗口截图。
3. **壁纸全站范围**：`everywhere` 谓词覆盖全路径；用户报告 Movies/Admin/Settings 仍为纯色，需查页面 opaque surface、stack/clipping 和实际运行构建。
4. **Recent Photos hover**：原型 flex-grow=3 并显示 place；Flutter grow 比例换算、title 字段和挤压动画未证明等价。
5. **Admin Media library**：原型为六个主分区之一；Flutter 分组只有五项，独立 LibraryManager 入口缺失。
6. **Admin Ops 双分类栏**：Hub 和子页面均保留 tab 机制；有传 `hideDesktopTabSelector`，仍需实机定位重复栏具体状态。
7. **播放器叠层**：`DesktopShellHost` 只有一个静态 `DesktopPlayerBar` 调用点，用户报告双层仍待定责。Flutter 外约束 1120/888px 扣除左右 margin 后的可见宽度为 1080/860px，与原型最终 CSS 宽度一致；高度 66px 对齐。控件和运行时叠层仍需逐项验证，不能把外层约束误读为可见宽度差。
8. **Photos**：原型 `.justified.solo` / `.solo-note` 在 Flutter `_layout` 没有对应分支，单张占满整行是源码已确认差异；长按、批选、hover、拖动取消仍需逐状态核对。
9. **通知**：桌面仍调用真实 `notificationControllerProvider`、顶部 NotificationsPanel 和 `/notifications` 页面，与移动端通知系统未隔离；样例桌面交互是 Shell 内 NotifPanel。
10. **Music 光晕**：对样例 hover CSS 逐状态检查；没有源码依据前不保留彩色 glow。样例存在的普通阴影、选中状态、唱片中心点等局部视觉必须单独保留。
11. **跨模块全屏**：代码定义了 `chrome/immersive/standalone` 模式，照片单项等 route 静态上会隐藏 Workspace；实机反馈与源码意图冲突，优先验证当前运行版本与实际 route/overlay owner，不先假定已解决。
12. **详情坞溢出**：实机报告 Dock 收放时 `A RenderFlex overflowed by 6.8 pixels on the right`。当前 `DesktopDock` 用固定 348px `OverflowBox` 维持内部宽度，但静态源码不足以定位报错的 RenderFlex 子树；需要捕获错误 ancestor chain 和具体窗口/tab/locale。
13. **用户/角色列表**：历史报告称缺少状态栏、排序、抽屉，但重新读 `admin_users_desktop.dart` 后，源码已存在 Active/Disabled 状态 Chip、Role filter、排序 Select、Create/Edit User Drawer、Role Drawer。源码确认两端控件类别相同，差异应聚焦 toolbar 排布、样式、列表列和表单细节；不能再登记为“控件缺失”。
14. **Files 左树与列表**：此前报告仅笼统写“对照树宽/拖放/列表列”，记录粒度不足。现已补明：Flutter 左树没有原型整块 glass panel；`_FolderTree` 在 initState 缓存各级 children，创建后不失效，所以列表新增目录不会同步到树；树项没有 draggable/drop target/长按移动；样例树有拖放和 650ms 悬停展开。列表方面，文件夹副标题当前显示类型而非子项数，日期固定 `YYYY-MM-DD`；其余用户所说列表内容问题仍待具体示例定位。

复核之后确认，首版报告没有达到用户要求的全面程度，且有数项旧状态需更正：

- 全站壁纸问题已有明确源码根因：桌面 route policy 把 `/admin`、`/profile`、`/video` 设为 `work` 且 `visible:false`，路由实底遮住 shell 壁纸。
- Movies 的 7 个分类、分档空状态与导入入口在当前 Flutter 源码中存在；Movies/Photos/Music 都已挂接媒体导入按钮，不能继续记录为“缺入口”。需核 dialog 样式和异步 job 反馈，而非把入口说成不存在。
- Photos 新建相册当前已有自绘虚线整体卡片和 Drawer；Photos 单图 justified grid 缺少原型的 `solo` 分支，单图会填满整行，这是源码可确认的差异。
- Reader 导入按钮当前在 PageHead actions 中先于 Overview/Library segmented control，图标为 upload；此前用户提出的位置要求在源码结构上已满足，剩余是像素/交互核验。
- Admin Overview 当前有 14 天上传图、重算存储卡及 4 张 KPI。样例也包含 Storage KPI；需通过实机标清用户所指额外的 Storage overview card，不能把 KPI 和额外卡片混为一谈。
- Admin 用户/角色相关的状态分类、排序和编辑 Drawer 在当前源码中均有对应控件；样例与当前布局是否一致仍需截图，但“缺控件”已被源码证据否定。
- 登录页当前代码把 artwork 动画裁切在左侧 ClipRect，右栏宽度断点为 900px；样例 CSS 中左侧 artwork 是线性 shade，暗主题 radial 背景位于 auth 根层。样例当前文件定义 30 秒单向 Ken Burns，而非无限循环 breathing；若原型已再次改版，先核对该文件实际内容。
- 默认壁纸资源 `frontend/assets/backdrops/default_wallpaper.jpg` 与用户提供的 `StockSnap_GI4HC0TIXR.jpg` SHA-256 相同；资源选择已确认，白边与全屏自适应症状和静态布局意图冲突，仍需当前运行版本实测。
- desktop slider primitive 默认绘制 accent fill；某一处具体使用是否关闭 fill 要按调用参数查证，不能笼统写成全局缺少颜色。
- 播放器的 Flutter `maxWidth` token 是外约束；减去容器左右 margin 后，实际可见上限为 1080/860px，与原型 `more.css` 一致。重复播放器与控件差异仍待运行态/交互实测。

报告中“用户已报问题闭环表”有 29 条编号项，将 Home、Movies、Photos、Music、Reader、Files、Admin、Settings、Shell、导入、共享控件、滑块、登录与 6.8px 溢出逐项收口。该闭环表可用来确认问题是否漏登记；实际运行态验证和后端全量 API/DTO 审计仍没有完成。

## 全路由差异覆盖

报告新增“全路由逐页核对矩阵”和“用户已报问题闭环表”，按全部显式路由/兼容 redirect、Settings 八分区、Admin 原型六分区与共享 UI primitives 展开；原型没有独立 route 的项目显式映射到相邻 Panel/Drawer/Overlay，不再用“其他页面待核对”概括。矩阵用于锁定源码覆盖面；运行态截图、所有状态变体和后端 DTO/数据库尚未穷举，因此没有把“列出路由”说成像素级全面验收。

## 逐页范围清单

以下页面均在 [全面差异报告](UI_DESIGN_DIFF_REPORT.md) 有独立条目。后续按此勾选，不跳页：

- Splash、Login、Setup
- Home
- Movies Browse、Movie detail、Series detail、Video player
- Photos Library、Albums、Places、Favorites、Trash、Album detail/picker、Photo viewer/info/slideshow/editor
- Music Home/Tracks/Albums/Playlists/Queue、Metadata drawer、Now Playing
- Reader Shelf/Library、Book detail、Book reader、metadata/import flows
- Files list/grid/tree/preview/share dialogs
- Settings Appearance/Profile、Backdrop library、Weather、Security/sessions、Notifications、Connected services、Storage、About
- Admin Overview、Identity/users/roles、Media library、Operations/tasks/dead letters/sign-in audit/sessions/system logs、Configuration、Storage/external storage
- Search、Command palette、background tasks、desktop notifications、toast/undo、Context menu、全局 Drawer/Dialog/confirmation

## 建议的阶段次序

1. **复现基线**：确认原型源码版和当前 Flutter 窗口均来自上述目录/提交；固定分辨率、缩放、语言、深浅主题、动态壁纸状态。采集 Home、photo viewer、music player、Movies/Admin/Settings 五类关键 route 的成对截图和 route/shell 可见性记录。
2. **共享桌面 Shell**：先定责沉浸页面还显示 chrome、播放器重复、通知 owner；再比较 titlebar/sidebar 文字/图标/玻璃参数。
3. **Backdrop route 覆盖**：全站与 Home & Music 两种范围分别截取 Home、Movies、Photos、Music、Reader、Files、Admin、Settings、immersive detail，并记录遮挡来源。
4. **Home**：Hero 主体/透明壁纸态 → Recent photos hover → KPI、Continue、Listening/Reading、Files/Activity 空态/加载态。
5. **Photos**：单图宽度 → hover → 普通选择/长按 → 批量 → reorder/取消 → Viewer/Info/Filmstrip → Albums/Places/Favorites/Trash。
6. **Music**：底部唯一播放器规格与功能 → 卡片/Track hover → Music 分类 → metadata drawer → Now Playing Queue/Lyrics/Appearance。
7. **Admin**：顶层 Media library → Overview → Ops 单层 tab → Identity 状态/排序/drawers → Config → Storage。
8. **Files**：先处理左树容器材质 → 新建目录后的 tree/list 同步 → 树项拖拽/延迟展开 → list/grid 行内容与空/加载态；再完成不同分区和 1180px/短窗口状态。
9. **Movies、Reader、Settings、认证页及共用弹层**，按报告逐页收口。

每阶段只实现一个页面或一个共享基础层，完成后更新报告的状态、源码位置、验证命令和运行截图路径，再进入下一阶段。涉及后端数据缺失时单独标注 API/DTO/数据库缺口，不把 UI 占位误写成生产数据。

## 本轮审计执行情况

- 已重新枚举原型 `src/desktop` 页面与 Flutter 桌面/功能路由，并阅读 `DesktopApp.tsx`、`Shell.tsx`、`Home.tsx`、`Admin.tsx`、`Photos.tsx`、`Files.tsx`/`fileTree.ts`、`Settings.tsx`、`BackdropView.tsx`、播放器样式及对应 Flutter 壳层/页面结构。
- 原型开发服务器没有运行；Flutter 目标窗口也未启动。因此没有同视口截图、hover/长按录屏、窗口 resize 或实际 backdrop 视觉确认。
- 本轮未运行测试或修复。全量差异审查为源码可证据审查；现场已知症状纳入待定责事项。
- 前端原则/审查细节参照本机 `impeccable` product register；当前代码库没有 DESIGN.md，因此所有关键视觉判断直接以用户指定的 React/CSS 原型源码为准。
- 当前指定的报告和交接文件是已跟踪文档的工作区修改；为保留前一版长报告/交接内容而创建的 `*_ARCHIVE_2026-11-18.md` 文件被 `/docs` 忽略，未纳入 Git 追踪。

## 第四批交接（底部播放器）

- 播放器“双层/玻璃溢出”的权威口径：原型四层 CSS 叠加后，1080×66 是**可见描边面板**本身，玻璃背板不得比它宽；Flutter 已改为同一盒子的 `DecoratedBox(shadow) → DesktopGlassSurface → 描边 Container`。
- 宽度与间距：wide 1080/margin20，compact(≤1180) 860/margin14，narrow(≤860) gap8；`playerBarClearance=116` 是 `polish.css` 终值，不要再退回 104。
- 功能回归点：队列键必须 toggle 开/关；曲目按钮整体挂 “Open Now Playing”；展开键为 “Expand”；完整控件集合 favorite/mode/prev/play/next/queue/mute/volume/expand 均有测试 key。
- 维护提醒：`desktop_player_bar_parts.dart` 是 part，主文件 633 行；继续加播放器内容时先确认 800 行棘轮。
- 测试夹具同步：OAuth 表单输入后需 `pump()`；托管分享面板是四个 `MobileEnvSwitch` 且 create/update 都要 stub 媒体策略参数；音乐歌词文件回显两处，按 `findsNWidgets(2)` 断言。

## 播放链路接入交接（commit b58cac87a）

- 桌面「播放键翻图标但没声音」不是后端/API 未接入：`_api.playbackPlan`、`openMusicAudio` 与播放会话都在。缺口是桌面 UI 只改 `musicCenterControllerProvider`，没有移动端的 `MiniPlayerSlot`/`MusicCenterPage` 常驻监听去调用 `syncFromCenterState()`。
- 现在由 `DesktopShellHost` 统一在帧后合并同步，只盯 `currentItem.playableKey / playbackPlan.url / isPlaying`；冷启动首帧也同步一次。该监听覆盖 chrome 与 immersive 路由，别移除，也别把同步责任放回单个页面。
- 回归点：`desktop_shell_test` 断言中心播放态变化会触发 `syncPlayback()`；桌面壳单测 22 全绿，音乐功能测试 483 全绿。运行态音频输出未做真机听感验证。

## 频谱与 Music 页文案/光晕交接（2026-11-19 第六批）

- 样例 `ui.tsx:60-94` 的 `Visualizer` 是伪动画，不读真实音频采样；Flutter 算法已一致。频谱静止的根因是 painter 收到原地列表引用，`shouldRepaint` 因身份未变永远 false。现改为每帧传入列表副本，`desktop_visualizer_test` 锁定相邻帧 repaint。
- Music 页“相册栏”是本地化键误用：tab/section 用了 `photosTabAlbums`，收藏用了 `photosFavorite`。现改 `musicNavAlbums / musicNavPlaylists / musicNavFavorites`，测试断言 `相册` 不再出现。
- 专辑/歌单卡原本套 `DesktopTilt`，多出样例没有的 `.shine` 指针柔光和 hover 60px 投影。现改静态圆角封面 + 样例投影，测试断言 Music 页无 `DesktopTilt`。
- `test/app/desktop` 183 全绿；改动文件 analyze 0 issue；全量 analyze 仍 0 error，warning/info 来自并行会话文件与 probe 脚本。

## 播放详情页 About 频谱（2026-11-19 第七批）

- 样例 `Music.tsx:248` + `more.css:85` 的频谱只出现在 About 页：64 柱、seed 5、90px、85% 透明度；`desktop.css:402` 的 `.np-viz` 在 TSX 无引用，不应额外塞进底部走带区。
- 当前 `_NowPlayingAbout` 已接 `DesktopVisualizer`，颜色取当前外观笔刷，播放态由中心状态透传；`desktop_now_playing_test` 断言切到 About 后频谱参数正确。
- `test/app/desktop` 184 全绿；改动文件 analyze 0 issue；全量 analyze 0 error / 7 既有 info-warning。
