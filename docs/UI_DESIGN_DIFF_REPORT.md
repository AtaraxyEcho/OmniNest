# OmniNest 桌面前端对照差异报告

- 审查日期：2026-11-16 起，最近更新：2026-11-17
- 唯一视觉与交互基准：D:\Development\Project Collection\UI Design\OmniNest Desktop UI UX
- 审查对象：OmniNest 仓库 frontend 中桌面端壳层、模块页面、路由、主要交互和表单/API 调用
- 结论：当前桌面前端**不满足与设计参考完全一致**。Movies、Photos、Music、Reader、Files 均存在可由源码确认的结构、布局、动作或表单差异；此外还有全局布局和 Reader 详情壳层差异。
- 方法与边界：逐项静态对照参考目录的 React/TSX/CSS 与 Flutter/Dart 实现、路由和涉及的 DTO；参考项目以源码目录运行 `npm run dev`，不使用 `dist`。Setup 本轮完成源码核对和对应实现修正，但尚未完成 Flutter 与参考项目的成对运行态截图/像素验收。源码注释写着“按样例实现”不作为通过证据；只有两端实际结构、字段、动作相同才视为匹配。
- 数据处理原则：原型里的固定演示数据、伪造媒体地址、localStorage 状态与生产后端实时数据的值不同，不单独判为视觉差异；但生产页的控件、状态、文案、表单字段、布局必须按参考稿复现。

## 1. 总览与判定

| 区域 | 判定 | 已确认差异 |
|---|---|---|
| 全局桌面壳层与布局 | 不完全一致 | Files 全宽/断点/底部留白和 Reader 书本详情沉浸路由已按参考修复；原生窗口控制与参考模拟窗口/任务栏仍有平台差异，运行态几何未验收。 |
| Home | 不完全一致 | 阅读连续天数卡现有当前值与最长值；Library 今日新增缺跨模块聚合，Listening 目前显示近期播放次数而原型显示本周时长；页面几何未做运行态核验。 |
| Movies | 不完全一致 | 本轮按用户要求移除顶部七项分类分段并完善空态；详情、播放器状态及运行态几何仍待核验。当前 `Movies.tsx` 源码仍包含七项分段，与用户描述的参考状态冲突，尚无运行态截图确认参考版本。 |
| Photos | 仍需核验 | Albums 内联详情、justified 照片墙、查看器分享/删除/撤销、编辑入口、Delete 快捷键、Trash 清空及幻灯片动效已补；分类栏和缩放条现保持同一操作行并靠右；分享抽屉、批量操作条与运行态几何仍待核验。 |
| Music | 不完全一致 | Home / Tracks 的分区、队列表格、筛选、排序、分页与曲目行交互已按原型源码继续修正；曲目编辑入口、播放器状态及运行态几何仍需核验。 |
| Reader | 不完全一致 | 展示类型、元数据编辑与跨端保存/恢复、搜索字段和排序选项已按参考补齐；桌面顶/底工具栏及 Book/Swipe/Scroll 模式、整本书搜索已在源码对齐。参考每页显示一条命中，Flutter 显示最多 60 条出现位置，无法准确提供原型页码；全书页数/剩余分钟也没有可靠数据源，运行态负载与几何仍未核验。 |
| Files | 不完全一致 | 全宽/断点/侧栏存储卡、文件类型色、长按拖动和分享访问/口令/收件人设置已补；原图/GPS内容转换与运行态几何仍有差异。 |
| Settings | 不完全一致 | Profile 资料编辑/移除头像、Appearance、Weather 城市联想已补；语言和字号仍位于顶部外观弹层，安全/通知/存储/服务等状态尚未逐项验收。 |
| Admin | 需继续核验 | 五大分组与 Operations 页签对齐；Identity 的用户/角色/权限卡、Storage 的位置/外部账户卡现已在桌面各自同页纵向呈现，并按当前权限加载；表单细节和运行态布局仍待核验。 |
| Auth / Setup | 源码差异已修复，运行态待验收 | Setup 的语言/时区控件颜色、弹层宽度与状态已按源码修正；原生桌面的 Login/Setup standalone 路由使用轻量主题宿主提供窗口按钮和拖拽区，不渲染工作区。登录、验证页及 Setup 的逐态渲染尚未完成运行态验收。 |

## 2. 全局壳层与布局

### 2.1 已核对的共同基线

| 项目 | 参考稿 | Flutter 桌面实现 | 判定 |
|---|---|---|---|
| 普通工作区壳层 | 标题栏、232px 侧栏、内容区、348px 详情 Dock、底部播放条 | 对应组件存在；DesktopMetrics 中侧栏 232px、Dock 348px，常规页最大宽度 1560px，左右留白按 3vw 并限制在 24–52px | 尺寸令牌大体对应；没有运行态像素证明。普通页面显示全局侧栏本身是参考稿工作区结构的一部分。 |
| Files 页面内部分栏 | 参考最终样式为 244px 文件树 + 22px 间距 | Flutter 固定 244px + 22px | 对应。参考 desktop.css 中基础宽度 236px 被 extra.css 后续规则覆盖为 244px。 |
| 常规页顶部间距 | 默认 22px，紧凑页 14px | DesktopPage 令牌分别为 22px、14px | 对应源码值。 |
| 窗口控制 | 原型在应用内模拟最大化、窗口化、最小化、关闭，并绘制任务栏 | Flutter 使用原生窗口控制，系统桌面任务栏不由页面绘制 | 平台行为及视觉不一致。若要求设计截图绝对复刻，需要明确原生窗口控件与任务栏是否也纳入复刻范围。 |

### 2.2 确认的布局偏差

1. **Files 全宽例外已修复。** DesktopFilesPage 现在使用全宽内容布局，与参考 `.files { max-width: none }` 对齐。
2. **Files 窄窗口断点已修复。** 1180px 以下隐藏文件树并改为单列；仍需运行态截图核实实际窗口尺寸和缩放下的几何。
3. **页面末尾播放条避让值已修复。** DesktopMetrics.playerBarClearance 已从 116px 调整为参考值 104px。
4. **Reader 书本详情路由已设为沉浸式。** `/reader/items/:itemId` 命中 `desktopShellModeForPath` 的 immersive 分支，源码意图是隐藏标题栏、侧栏、Dock 和播放条；还需运行确认用户实际打开的路由和内容视口。
5. **章节/漫画/PDF 阅读路由同样在源码中标记为 immersive。** `/chapters/`、`/read` 路径应隐藏工作区壳层。用户反馈的内容宽度问题尚未用当前运行态复现，代码路由配置不能替代运行验证。
6. 普通模块页面都处于带侧栏的工作区，这一点与参考 Shell 的普通页面结构一致；当前源码不能支持“多数普通模块本来就应该没有侧栏”的判断。应区分普通模块壳层与参考稿标记为全屏的详情/阅读/查看页面。

### 2.3 色彩令牌核对

- 桌面四档强调色 Sage/Mist/Copper/Iris 的深浅值，以及深浅主题底色、文字色，在设计 Settings.tsx / desktop.css 与 Flutter DesktopPalette 中源码值相符。
- 已修复文件类型配色：桌面 Files 行图标现在按真实文件类型使用独立色，色值对应参考 desktop.css 的文件图标色；Home 最近文件共用的类别令牌也已对齐到参考色值。Files.tsx 的 KIND 表包含用于其他场景的 Audio #8b7aa5，与文件行/Home `.fi` 的 Audio #7dbcc9 是两套用途不同的颜色；本实现对应的是后者。
- 本项只比对令牌值，没有测量透明混色、模糊、阴影或显示器色彩管理下的最终像素。

证据：参考 src/desktop/desktop.css:174,193,210–218,445,500；src/desktop/extra.css:16,62；Flutter frontend/lib/app/theme/desktop/desktop_skin.dart:234–255、frontend/lib/app/desktop/widgets/desktop_surfaces.dart:33–80、frontend/lib/app/desktop/pages/desktop_files_page.dart:170–200、frontend/lib/app/desktop/desktop_shell.dart:57–83、frontend/lib/app/router.dart:422–446。

## 3. 页面逐项差异

### 3.1 Home

- 设计 Home.tsx:60–61 的四卡是 Library（今日新增）、Listening（本周聆听小时数）、Reading streak（当前/最长天数）、Storage。
- Flutter 的 Reading streak 卡使用 Reader 统计 API 的 currentStreak，最长连续天数已由后端按本地日期聚合并返回。Library 当前把电影、照片、音乐曲目和 Reader 条目数相加，仍未覆盖 Files，也没有“今日新增”计数；Listening 当前显示受限的 recentItems 列表长度，而非本周累计播放时长。两者需要统一首页统计口径和真实聚合来源。
- 首页的继续观看、聆听、阅读、最近照片、最近文件、活动等内容在两端均有对应入口；固定样例数据不作为差异。本轮没有运行态确认卡片宽高、栅格断点和折叠顺序。

### 3.2 Movies 与影片详情

- 参考 `Movies.tsx` 的 For you 包含 Films、Series、Anime 三条内容轨道；Flutter 已提供这些轨道，Movies 分区优先展示完整影视中心片库，仪表盘最近添加数据只作加载回退。
- 用户指出最终参考页面不应有 For you/Films/Series/Anime/Favorites/Watchlist/History 顶部分段。本轮按该明确要求移除可见 Seg，保留内容轨道、分区深链和单一返回动作。需要注意：当前参考 `src/desktop/Movies.tsx:19,65–66` 仍定义并渲染七项 Seg；这一版本冲突尚未由原型运行画面确认，因此不能将该项记为源码一比一一致。
- Continue watching 的 See all 跳转到 History，与参考 Movies.tsx:72–73 一致。
- History 已改为海报网格，清空会先保存进度快照；Undo 逐条通过真实进度 API 恢复并刷新历史。
- 影片详情参考 MovieDetail.tsx:61–106 包含 Overview、Episodes、Files、Subtitles（电影隐藏 Episodes）、剧情展开、演员/主创卡、版本文件列表和转码状态。
- Flutter 桌面电影详情现提供 Overview / Files / Subtitles；Overview 使用实际 cast/crew 元数据和三行剧情展开，Files 从服务端读取真实文件名、大小、编码、主版本与派生版本，并根据服务端转码开关显示控件。转码任务写入后端并显示可打开任务面板的成功提示。系列的 Episodes 仍由独立系列详情页呈现。
- Hero 的 From start、收藏、已看和 Watchlist 操作已接入真实进度/清单 API；Watchlist 使用服务端数据并响应 VIDEO 同步失效事件。与样例的像素级布局、演员头像、实际媒体字段覆盖情况和错误/窄窗口状态仍需运行态截图核对，Movies 当前仍未能声明完全一致。

证据：设计 src/desktop/Movies.tsx:34,65–84、src/desktop/MovieDetail.tsx:28–84,87–115,268–286；当前 frontend/lib/app/desktop/pages/desktop_movies_page.dart:186–220、frontend/lib/app/desktop/pages/desktop_movies_cards.dart:472–573、frontend/lib/app/desktop/pages/desktop_movie_detail_page.dart:103–169,309–478。

### 3.3 Photos 与照片查看器

- 五个分类名称/顺序和 Library 的 justified 照片墙结构在源码中对齐：Library、Albums、Places、Favorites、Trash；缩略图密度滑杆、分组全选、选择浮层、照片查看器也都有对应实现。这里不把“完全没有对应结构”作为审查结论。
- Albums 现有可点击内联打开和 New album 创建入口；新建入口按 420px 右侧抽屉只采集相册名，重复名禁用 Create，成功后留在相册架并提示。详情保留 Albums 分类栏，以大标题/说明、Share/Delete album 操作和 justified 照片墙呈现，并接入服务端详情分页、分享和删除。空相册提供返回 Library 操作；整体几何仍未做运行态截图核验。
- 查看器已具备分享、移入 Trash、Undo、Delete 快捷键，并保留下载等生产额外动作。Delete 复用真实 Trash API；分享抽屉打开时不触发删除快捷键。
- 幻灯片模式下，顶栏和胶片条会按参考稿在指针进入/离开查看器时以 600ms 淡入淡出；每张照片以 4 秒 ease-out 缓推并轻微平移，减弱动效系统设置会关闭缓推。
- 参考信息面板包含 Taken、Location、Camera、Exposure、Size、AI labels、Zoom；Flutter 面板展示后端可用的拍摄日期/GPS/相机/曝光/尺寸和 tags。AI labels 的显示与来源不同，且字段缺失时面板内容会随真实数据改变。
- Trash 已有 Empty Trash 确认和批量清理路径。照片删除可 Undo；永久清空按样例给出不可撤销确认。
- Photos 的上述主交互已补齐源码实现，但相册详情、批量选择工具栏、失败占位与撤销反馈仍需运行态验收。

证据：设计 src/desktop/Photos.tsx:53–120,132–175,186–192；当前 frontend/lib/app/desktop/pages/desktop_photos_page.dart、desktop_photos_album_detail.dart、desktop_photos_sections.dart、desktop_photos_selection.dart、desktop_photo_viewer_page.dart。

### 3.4 Music 与 Now Playing

- 参考 Music.tsx:134–142 的 Home 顺序为精选/当前播放 Hero、Albums 横向轨、Playlists 横向轨、Up next 曲目表。
- Flutter 桌面 Home 现有 Albums、Playlists、Tracks/Queue 内容入口；歌单创建、编辑、删除和播放/队列动作已有真实实现，主内容排序仍需运行态几何核验。
- Now Playing 已增加 About 信息页，曲目编辑从桌面入口打开右侧抽屉。
- Now Playing 抽屉可直接编辑 Title、Artist、Album、Cover image URL、Lyrics 并保存真实元数据；原始覆盖可恢复。模块其它入口仍有 Genre、文件封面、歌词导入/在线匹配等额外生产操作。

证据：设计 src/desktop/Music.tsx:129–161,189–270、src/desktop/MetaEditor.tsx:36–54；当前 frontend/lib/app/desktop/pages/desktop_music_page.dart:105–218、desktop_music_rows.dart:110–143、desktop_now_playing_page.dart:391–400；已有非桌面入口 frontend/lib/features/music/presentation/widgets/music_metadata_edit_dialog.dart:94–175, frontend/lib/features/music/presentation/widgets/music_metadata_edit_sections.dart:170–310。

### 3.5 Reader、书本详情与沉浸阅读

- 参考 Reader.tsx:76–104 的 Overview 页眉提供 Overview/Library、Import 按钮；统计为 Books、Comics、Hours read、Streak，并分成 Books 与 Comics & manga 两条书架。
- Flutter Overview 已提供 Import，分 Books / Comics 书架，并显示 Books / Comics / Hours / Streak 统计。
- 参考书库有 All/Books/Comics 类型筛选、All/In progress/Finished/Unread 状态筛选、标签筛选、对 title/author/series/tag 搜索、Recently read/Title/Author/Progress/Recently added 排序、网格/列表、结果数和 Clear filters。
- Flutter Reader Library 已有 All/Books/Comics、All/In progress/Finished/Unread、标签筛选、结果数、清除筛选和网格/列表；类型分段由服务端按展示类型分页，漫画与日漫归入 Comics，解析类型仍决定实际阅读路径。搜索覆盖 title/author/series/description/tags，排序为 Recently read/Title/Author/Progress/Recently added，与样例选项一致。
- Book detail 有 About/Chapters/Notes/Activity 四页签，路由现为 immersive；源码壳层已对齐，但实际视口仍未截图验收。
- 参考 `ReaderView.tsx` 的桌面沉浸阅读工具栏直接提供 Book/Swipe/Scroll 模式、Search、Contents、Bookmark、Highlights、Appearance；底栏提供页码、进度拖动、百分比和剩余时间。Flutter 桌面顶栏现已按这一顺序提供相应入口，Book 映射为 Page + cover，Swipe 映射为 Page + slide，Scroll 使用现有连续阅读模式；这些操作复用已有 Reader 设置和面板。桌面浏览器现可使用两种页模式，Android/iOS 手机浏览器保留滚动模式，移动窄屏保留 ReaderFocus chrome。底栏已改为居中进度轨道，并可显示当前章节页码/进度；当前没有全书总页数或可靠的剩余阅读时间来源，因此不能显示原型的全书页码范围与剩余分钟。全书搜索现逐章读取，最多保留 60 条出现命中；不一次性预载全书，命中偏移会映射到相应章节并支持跨章跳转。原型按每页生成一条命中，Flutter 尚未把动态排版位置换算为全书页码。
- 参考 Reader 详情内可编辑的元数据字段为 Title、Author、Type（Book/Comic/Manga）、Series name、Volume number、Tags、Cover image URL、Description，并可 Restore original。
- Flutter 桌面抽屉已提供封面、Title、Author、Type、Series、Volume、Tags、Cover URL、Description 与有手动覆盖时的 Restore original；卷号限制为 1–999，标题必填。移动端编辑器也提供相同新增字段，并保留生产端已有字段。

证据：设计 src/desktop/Reader.tsx:76–104,116–167,178–215,224–289；当前 frontend/lib/app/desktop/pages/desktop_reader_page.dart:100–165、desktop_reader_library.dart:19–159、desktop_book_detail_page.dart、desktop_book_detail_sections.dart、desktop_book_metadata_dialog.dart:12–170；路由 frontend/lib/app/router.dart:422–446、desktop_shell.dart:57–83。

### 3.6 Files

- 参考 Files.tsx 左轨分区为 My files、Recent、Favorites、Shared by me、Shared with me、Shared space、External storage、Recycle；存储用量 meter 留在左轨底部。Background tasks 由全局标题栏浮层提供。
- Flutter Files 侧栏现按参考组织分区和文案（My files、Shared by me、Recycle），并将存储用量 meter 放回轨底；后台传输仍保留为真实任务入口。
- Files 区现为全宽布局，1180px 以下隐藏文件树，详见第 2 节。
- 参考文件表是 Name、Modified、Size、Access + 行内动作；桌面表的行高和文件树宽度等部分源码尺寸能对上。参考支持 Ctrl/Cmd 多选、Shift 连选、右键菜单、键盘打开/返回、重命名回车/Esc、拖动文件夹悬停展开、把行拖到目录移动、外部文件拖入上传。
- 参考行图标按 Folder/PDF/Video/Audio/Image/Text 使用独立类型色；Flutter 行图标与 Home 最近文件令牌现已按参考 CSS 着色。
- Flutter 桌面保留鼠标即时拖放，并为触控指针加入长按后拖动；参考稿桌面交互本身是鼠标拖放，长按是用户额外要求。
- 分享表单现支持 Off、Anyone、Passcode、自定义/自动口令、收件人搜索与选择，以及 Allow downloads、Original quality、Include location；字段经真实后端保存并通过分享同步更新其他客户端。禁止下载时服务端不签发下载链接，也拒绝接受/转存分享。普通 Files 分享的原图尺寸转换和 EXIF/GPS 清理尚未接入文件内容管线，当前只持久化策略值，不能视为内容处理已完成。
- `Files.tsx` 的 KIND 表和 CSS `.fi` 使用场景存在不同 Audio 色值；Flutter 对照 Home/Files 文件图标 CSS `.fi`，采用 #7dbcc9。
- 分享策略现已加入创建/更新 DTO、响应 DTO、数据库基线与存量库升级脚本。`allowDownloads` 在公开文件访问和转存入口生效；`originalQuality` 与 `includeLocation` 可跨端保存/读取，但普通 Files 分享目前没有尺寸转换或 EXIF/GPS 剥离处理，需继续实现并运行验证。

证据：设计 src/desktop/Files.tsx:25–47,175–236,252–274,300–360；src/desktop/desktop.css:445–451,500；当前 frontend/lib/app/desktop/pages/desktop_files_rail.dart:20–117、desktop_files_page.dart:159–200,264–318,420–500、desktop_files_rows.dart:225–250、desktop_files_dialogs.dart:239–415、frontend/lib/features/files/data/file_api_shares.dart:69–84、backend/omninest-file/src/main/java/com/omninest/modules/file/dto/CreateShareLinkRequest.java:14–29。

### 3.7 Settings 与个人资料

- 参考 Settings.tsx:13 的顺序是 Profile、Appearance、Backdrop library、Notifications、Security、Storage、Connected services、About & updates。
- Flutter DesktopSettingsSection 现按参考顺序展示 Profile、Appearance、Backdrop、Notifications、Security、Storage、Connected services、About。
- Profile 已接入真实资料编辑和头像上传，显示名限制 40 字、邮箱必填并校验；头像选择限制 2 MB。后端 UpdateMeRequest 仍允许 displayName 最长 120，DTO 上限比参考 UI 更宽；当前前端主动按参考 40 字收紧。
- Appearance 已加入字体比例、语言、Atmosphere 控件；Weather 已接入生产偏好和 Open-Meteo 城市联想搜索，并提供加载、无结果、离线状态；头像可上传与移除。其它 Settings 分区还需逐态核验。

证据：设计 src/desktop/Settings.tsx:13–67,105–130；当前 frontend/lib/app/desktop/pages/desktop_settings_page.dart:41–169,251–330,477–531、frontend/lib/app/desktop/desktop_appearance_sheet.dart:205–245、backend/omninest-system/src/main/java/com/omninest/modules/user/dto/UpdateMeRequest.java:11–17。

### 3.8 Admin、Auth、Setup

- Admin 设计存在 Overview、Users & roles、Operations、Configuration、Storage 五个主分组；生产 AdminSection/AdminDashboardPage 也映射成五个入口。Operations 内的 Tasks/Dead letters/Sign-in audit/Sessions/System logs 与参考同类分段交互对应。
- Admin Identity 与 Storage 原先被拆成组内页签；本轮已把桌面 Users / Roles / Permissions 以及 Storage locations / External accounts 按参考稿纵向组合到同页，并根据当前用户权限加载可访问面板。管理表单字段、权限状态与每个弹窗仍需逐项核对。
- 桌面配置区有分组、搜索、过滤、待保存状态、Review/Save、配置历史等同类关键交互。Admin 的用户/权限/任务/存储数值是服务端数据，和原型种子数据不比对。本轮没有对所有管理表单字段、每类配置控件、权限状态和每个弹窗逐一做运行态验收，因此 Admin 不标“完全一致”。
- 本轮缺少真实运行态截图，尚未逐屏核验登录、二次验证、初始管理员设置的布局、字段、控件、校验提示和各状态反馈；这些页面仍需按生产业务路径逐态做视觉验收。

## 4. 表单字段与后端参数逐项核对

### 4.1 影视元数据编辑（重点）

参考 src/desktop/MetaEditor.tsx:10–34 的右侧抽屉字段与校验：

| 参考字段 | 参考约束/交互 | Flutter 桌面现状 | 当前后端 DTO / 影响 |
|---|---|---|---|
| Title | 必填；保存按钮随表单有效性启用/禁用 | 已对齐；空标题禁用保存，不额外显示原型没有的星号 | 请求 `title`。 |
| Genre | 文本字段 | 已提供逗号分隔输入并动态保存 | 请求 `genres: List<String>`。 |
| Year | 恰好 4 位数字 | 已限制 4 位数字并纳入保存有效性 | UI 年份映射为 `releaseDate: LocalDate`。 |
| Runtime | 类似 2h 14m 的文本字段 | 已支持 `2h 14m`、`14m` 和纯分钟，空值清除；非法内容给出本地化提示 | 解析成 `runtimeSeconds`；空值使用 `clearRuntime`。 |
| Rating | 0–10 数值校验 | 已提供小数输入并校验范围；空值按原型的数字转换语义保存为 0 | 请求 `rating: Double`。 |
| Cast | 逗号分隔演员 | 已提供逗号分隔输入 | 请求 `cast: List<String>`。 |
| Synopsis | 5 行多行简介 | 已使用原型字段名、5 行输入区 | 请求 `overview`。 |
| Poster image URL | 编辑时预览，保存更新封面 | 已提供 URL 输入和随输入更新的 92×138 海报预览；未编辑时保留已有文件资产 | 新 URL 对应 `posterUrl`；已有资产继续由 `posterFileId` 表示。 |
| Restore original | 有覆盖值时出现 | 已按 `manualMetadataOriginal` 快照条件显示，并调用恢复动作 | 请求 `restoreOriginal: true`，后端恢复字段和海报来源并广播 `UPDATED`。 |
| 容器/按钮 | 右侧抽屉，宽 520，Cancel/Save | 已改为 `showDesktopDrawer` + `DesktopDrawerFrame`，宽 520，固定底部 Cancel/Save | 容器、遮罩、滑入和内容滚动现与样例抽屉一致。 |

`MovieMetadataUpdateRequest` 与前端调用字段对应为 `title`、`releaseDate`、`overview`、`runtimeSeconds`、`clearRuntime`、`genres`、`rating`、`cast`、`posterUrl`、`posterFileId`、`backdropFileId`、`metadataStatus`、`restoreOriginal`。Year 与 Runtime 是表单格式到后端类型的显式映射；没有让输入框伪造 `year` 或 `runtime` wire 字段。Genre/Cast 字符串按逗号拆为数组。原型不定义 API JSON，报告只将其字段语义映射至实际请求契约。

证据：当前 frontend/lib/app/desktop/pages/desktop_movie_detail_actions.dart:149–165,191–326；backend/omninest-media/src/main/java/com/omninest/modules/video/dto/MovieDtos.java:262–272。

### 4.2 音乐曲目编辑

- 参考 MetaEditor.TrackEditor 字段：Title、Artist、Album、Cover image URL、Lyrics 多行文本；仅 Title 必填。
- 桌面 Now Playing 的 About/edit 入口打开右侧抽屉；字段为 Title、Artist、Album、Cover image URL、Lyrics 和条件显示的 Restore original。封面 URL 与文本歌词可通过后端保存，原始歌词/封面来源也纳入恢复快照。桌面抽屉已去除原型没有的本地图片上传/移除控件，并对齐 96px 封面、歌词行数、10 行文本区、字段间距/焦点反馈和保存反馈。
- 模块内部其他入口仍使用 MusicMetadataEditDialog，包含 Genre、封面文件、歌词导入/在线匹配；这些入口保持生产能力，视觉与样例 TrackEditor 不同，尚未逐态对齐。
- 生产更新 DTO 使用 `title`、`artistName`、`albumTitle`、`genre`、`lyricsRaw`、`coverFileId`、`clearCover`、`coverUrl` 与 `restoreOriginal`；响应补充 `manualCoverUrl` 和 `hasManualOverride`。字段语义与表单控件对应，封面 URL 只接受 HTTP(S)，后端不代客户端请求该地址。

### 4.3 Reader 书籍元数据编辑

- 参考字段：Title、Author、Type（Book/Comic/Manga）、Series name、Volume number、Tags、Cover image URL、Description；标题必填；如已有本地覆盖可 Restore original；提示仅改书库元数据，不改原文件。
- 桌面抽屉与移动编辑页均包含 Type、Series、Volume、Tags、Cover URL、Description 和 Restore original；编辑请求字段分别为 `readerType`、`seriesName`、`volumeNumber`、`genres`、`coverImageUrl`、`description` 与 `restoreOriginal`。卷号清空通过 `clearVolumeNumber` 表达，Tags 映射至既有 `genres.items`。
- 后端 `UpdateItemMetadataRequest` 已加入并校验上述字段及 `clearReleaseDate`、`clearRating`，阅读展示类别、系列、卷号、封面 URL 和原始元数据快照保存在现有 `external_ids` JSONB 中，不新增 Flyway 迁移。更新通过现有 Reader `UPDATED` 同步事件传播；所有平台从同一服务端条目读取数据。`readerType` 只影响书库分类，不改变 `contentKind` 与解析/阅读路径。封面 URL 限 HTTP/HTTPS，清空后回退至书库封面；服务端不代客户端请求该地址。

### 4.4 Files 分享链接表单

- Flutter UI 已提供下载、原图、GPS 策略；创建/更新请求与响应 DTO、数据库基线、存量升级脚本和分享同步事件已接入。禁止下载已由后端执行，原图/GPS内容处理仍缺。
- Flutter 请求 JSON / 后端 CreateShareLinkRequest 对齐项：resourceId、resourceType、password、generatePassword、expiresAt、maxAccessCount、recipientUserIds；桌面创建表单可搜索并指定收件人。
- `CreateShareLinkRequest` / `UpdateShareLinkRequest` 与 `FileShareLinkDto` / `FileSharePreviewDto` 已对齐 `allowDownloads`、`originalQuality`、`includeLocation`。三项策略写入 share_links，修改通过现有分享同步事件传播；禁止下载拒绝公开文件 URL 签发与转存。普通 Files 的 `originalQuality=false` 尚未切换网页尺寸副本，`includeLocation=false` 尚未从内容字节移除 EXIF/GPS，后两项虽可跨端保存/读取，实际内容处理仍是后端缺口。

### 4.5 Profile 与其他已核对字段

| 接口 | 前端字段 | 后端字段 | 判定 |
|---|---|---|---|
| 更新本人资料 | displayName、email | UpdateMeRequest 同名字段 | 字段名一致；参考显示名 maxLength 40，DTO max 120；桌面表单按参考限制 40 字，头像上传/移除均有真实接口。 |
| 用户位置上报 | latitude、longitude、source | UserLocationDto 同名字段 | 已核对字段名/类型对应；不是本次主要 UI 差异。 |
| 影视刮削任务 | fileNodeId、force、provider、externalId | 当前 ScrapeRequest 对应字段 | 已核对字段名对应。 |
| Reader/音乐/Photos/Admin 其他接口 | 未全量列出 | 未按所有 endpoint/DTO 穷举 | 不从抽样结果推导为整个 API 已一致。 |

## 5. 对用户已列问题的逐条回应

1. **Movies 已补齐多项结构与动作差异并移除顶部分类栏。** Anime 轨道、History 海报网格/清空/Undo、See all 去向、电影 Overview/Files/Subtitles、演员/主创和文件清单、From start/已看/Watchlist 动作已有代码；Watchlist 与播放历史由后端持久化并触发跨设备同步。顶部 Seg 的移除按用户最新描述执行，但和当前 `Movies.tsx` 源码矛盾，需用正确版本的参考运行态复核；播放器各状态也仍待对照。
2. **Photos 的主要缺失交互已有代码修复。** 相册在 Albums 分区内展开并使用 justified 照片墙，服务端分页、分享和删除仍可用；Viewer 有分享/删除/Undo/Delete 键，Trash 可清空。分享对话框视觉、批量状态和完整运行态反馈尚未验收。
3. **Music 的主要结构入口已有代码修复。** Home 已加 Playlists，Now Playing 已加 About 与编辑抽屉；曲目 URL 封面和原始数据恢复现已接入后端，移动编辑器及其他入口仍有差异。
4. **Reader 的 Overview/书库入口、搜索/排序和沉浸路由已有代码修复。** 桌面与移动编辑器已覆盖样例元数据字段，并接入后端跨端保存与恢复；章节/漫画/PDF 实际视口仍需运行确认。
5. **Files 的全宽/窄屏、分区存储卡、类型色、长按拖动和分享表单已有代码修复。** 下载开关已由后端执行，原图/GPS 策略的文件字节转换仍缺。分享关闭、口令和收件人 UI 已接入真实后端。
6. **Reader 打开阅读的源码壳层现已配置为沉浸式。** 书本详情、章节、漫画/PDF 路由都应隐藏工作区侧栏；用户反馈仍需在实际应用中复现并核对 URL、壳层和内容视口。
7. **所有 UI/控件/交互/反馈/组件/视觉效果都要一致：当前不能通过。** 报告已记录多项可确认差异；但“所有状态和像素均完成运行态一一验收”尚未成立，需在可运行桌面窗口上覆盖不同页面、弹窗、空/加载/成功/失败状态和窗口宽度后才能签字为完全一致。
8. **表单参数/元数据抽屉：已具体对比。** Reader 字段已接入并与新增 DTO 参数对应；电影元数据字段已接后端，Files 三项分享策略已进 DTO/存储/同步，但普通文件的原图与 GPS 内容处理仍缺，详见第 4 节。

## 6. 需要运行态复核的项目

- 第一轮报告结论是源码静态对照，不是截图像素测量。第二轮确认参考运行页可访问，并读取到 Reader 书本详情的可访问状态树；后续虽修复若干源码差异，仍没有取得可核验的 Flutter 与参考稿成对截图。
- 所有页面的实际宽高、字体回退、长文本换行、加载/空/错误状态、抽屉/弹窗遮罩、hover/focus/pressed 动效、不同显示缩放及不同窗口宽度仍要截图逐一验收。
- Reader 的沉浸路由实际路径需要复现，重点记录打开书本详情、章节阅读、漫画阅读、PDF 阅读时的 URL、壳层是否隐藏、内容视口宽度。
- Admin 的所有字段、权限分支和弹窗，Settings 安全/通知/存储/服务区域以及 Auth/Setup 的各步骤，本轮没有逐状态做运行态全量验收。
- 任何后端 DTO 尚未列出的接口都不在“参数已全部一致”的结论范围内。

## 7. 第一轮变更与验证记录

- 本轮只更新了本报告，没有改产品 UI、交互、API 或后端代码。
- 实际执行：静态读取/检索参考 TSX/CSS、Flutter 页面/路由、音乐/文件 API 调用和影视/资料/分享 DTO。
- 未执行测试、构建、分析：按审查任务不改代码；开发规则也要求不要在未请求时擅自运行测试。
- 未做运行态截图：因此视觉尺寸、动效和实际 Reader 视口的风险仍未关闭。
- 仓库中已有紫色规则移除及其他工作区改动，本轮未改写或清理那些改动。

## 8. 第二轮全视觉覆盖审查

### 8.1 覆盖结论

**第一轮报告没有覆盖全面。** 它较完整地记录了 Home、Movies、Photos、Music、Reader、Files、Settings、Admin 的部分主页面差异，也抽查了影视/音乐/Reader/分享/个人资料表单；但共享壳层的大部分浮层、各页面的次级视图和完整状态矩阵、微观视觉令牌、不同窗口尺寸下的实际结果，没有逐项建立证据链。第一轮不能作为“所有视觉内容已一一核完”的验收报告。

第二轮扩展了核对清单和证据边界，但仍**不能判定前端已与参考稿一比一一致或本次审查已完成像素级验收**。可访问的参考运行页只观察到 Reader 书本详情状态；没有取得同分辨率、同主题、同文案/内容状态下的 Flutter 与参考稿成对截图。下面的“待核”不是通过，也不代表实现没有差异。

### 8.2 页面与组件覆盖矩阵

| 范围 | 必须逐屏/逐组件覆盖的内容 | 当前证据与结论 |
|---|---|---|
| 全局画布与窗口 | 深/浅主题、四档强调色、动态背景/环境光、grain/遮罩、窗口最大化/窗口化/最小化/关闭、原生标题栏与任务栏差别 | 已静态核对主色及部分壳层尺寸；原型绘制自己的窗口与任务栏，Flutter 交给原生窗口/系统任务栏，属于可见的平台差异。背景叠层、透明度、裁切、转场与最终像素尚未对照。 |
| 全局标题栏与导航 | 品牌区、返回/前进、搜索/命令入口、主题、任务、通知、详情 Dock、账户菜单、侧栏层级与选中态、存储卡 | 已确认主要组件和令牌存在；第一轮只对基本壳层/窗口作了比较。按钮尺寸、间距、菜单位置、焦点/禁用态、窄宽度折叠及操作后反馈未逐项对照。 |
| 全局浮层与反馈 | Account、Notifications、Background tasks、Context menu、Command palette、Shortcuts、Toasts/Undo、详情 Dock、空状态/骨架 | 参考 Shell 与 UI 原语、Flutter overlays/panels/command palette/toast/dock 均已纳入本轮组件清单；尚未逐一打开并对照遮罩、层级、尺寸、关闭方式、字段、内容滚动和成功/失败/撤销反馈。 |
| Home | 指标卡、继续观看/聆听/阅读、近期照片/文件/活动、卡片比例与内容空位 | 本轮将首页 provider 订阅缩到页面实际使用的字段，减少无关数据变化触发整页重建；今日新增缺跨模块汇总，近期播放次数不等于每周聆听时长，几何与运行态未验收。 |
| Movies | Browse/内容轨、History/清空撤销、详情页签和动作、视频播放器控制/音轨/字幕/设置/全屏 | 本轮移除顶部分类 Seg，空库终态显示空态并覆盖 Anime；当前原型源码反而定义七项 Seg，需确认参考版本。详情运行态布局、头像与播放器状态仍待核对。 |
| Photos | 分类、相册货架/创建/详情、选择与批量栏、Viewer、信息面板、分享抽屉、编辑器、幻灯片、Trash/恢复/清空 | 分类栏和缩放条现作为不可拆分的同排操作组；缩放范围按 150–320 映射。地点 Hero 卡加入裁切与前景描边。分享/批量状态及运行态几何仍待核验。 |
| Music | Home 轨道、列表/队列、播放条、Now Playing 的 Lyrics/Queue/About、曲目与播放列表编辑、音轨样式/波形 | Home Playlists、Now Playing About 和桌面元数据编辑入口已补；其它编辑表单、队列排序、播放状态/错误、波形和撤销仍待逐项对照。 |
| Reader | Overview/书库过滤、书本详情、章节/漫画/PDF 沉浸阅读、章节目录、进度、书签/笔记/搜索/排版控制、元数据抽屉 | Overview/主要过滤、搜索字段、排序项、沉浸路由、元数据字段、桌面顶栏模式/动作入口及全书搜索范围已对齐源码；搜索命中未映射到动态页码，全书页数/剩余时长、工具栏反馈及沉浸阅读运行态待核验。 |
| Files | 侧栏分区/存储卡、目录树、表格行、选择/批量操作、右键、拖拽悬停/移动、外部拖入、分享/详情对话框、回收站 | 全宽/断点/存储卡/类型色、触控长按拖动、Off/口令/收件人和策略字段已实现；原图/GPS 文件字节处理仍未接入，行几何、选中、拖放提示、进度/错误与反馈仍待运行态核验。桌面参考本身定义鼠标拖放。 |
| Settings | Profile、Appearance、Backdrop library、Notifications、Security、Storage、Connected services、About/updates、Weather | Profile、Appearance、天气城市联想和分区顺序已有代码修复；安全/通知/存储/服务表单字段及各保存/失败反馈仍未逐状态对照。 |
| Admin | Overview、Identity 的用户/角色/权限/配额、Operations 各页签、Configuration 搜索/过滤/Review/历史、Storage locations/外部账户表单 | Identity/Storage 桌面信息架构已改为同页纵向面板；用户/角色抽屉、权限矩阵、配额、危险确认、配置控件、dirty/review/save/rollback、密钥输入和校验错误均未逐项核对。 |
| Auth / Setup | Splash、登录、验证步骤、服务连接、初始管理员、字段约束与错误/成功/加载状态 | Setup 的输入/下拉表面与原型色值映射已校正；原生桌面 Login、Setup 使用无边框窗口 controls 与拖拽/缩放热区。逐状态运行态验收仍待完成，真实服务端认证流程保持有效。 |

### 8.3 跨页面视觉与交互维度

| 维度 | 当前核对范围 | 尚未完成的覆盖 |
|---|---|---|
| 颜色 | 深浅底色、主要文本色、四档强调色及文件类型色有源码值对照；Files 行图标与 Home 最近文件类别色已按参考 CSS 修正。 | 语义色在每种主题/强调色下的最终合成、透明色叠加、动态背景上的文字对比、海报/照片平均背景、hover/pressed/selected/disabled 色值、各模块局部色板未全量逐值核对。 |
| 布局与几何 | 侧栏、Dock、播放条、常规页顶部间距、Files 分栏令牌有静态尺寸对照；Files 全宽/断点/底部避让和 Reader 书详情沉浸路由已按参考源码修复。 | 上述修复以及其它页面仍缺实际 bounding box、栅格/列数、基线、留白、视口裁切、文本折行、滚动区高度、浮层锚点/层叠关系的同屏像素测量。 |
| 字体与内容 | 参考 CSS 与 Flutter 均声明 Inter/Newsreader 主族，Flutter 有对应字体令牌和字阶。 | 实际字体是否加载、中文/特殊字符回退、字体文件版本、字重插值、字号缩放、字距/行高及相同内容下的换行高度没有运行态核验。 |
| 图标与媒体素材 | 参考组件和 Flutter 图标/媒体组件均存在；Files 类型色差已修复。 | 图标字形/线宽/占位、图片源、封面裁切与焦点、模糊/颗粒/透明遮罩、加载/失败 fallback 未逐项对照。 |
| 控件状态与动效 | 两端均有按钮、选择器、滑块、表单、弹层等实现；参考含 reduced-motion 样式，Flutter 有对应主题/动效基础设施。 | 每个控件的 default/hover/focus/pressed/selected/disabled/loading/error，以及弹层打开/关闭、切页、拖拽、撤销的时长/曲线/焦点还原/键盘退出尚无完整矩阵。 |
| 响应式与密度 | Files 在 1180px 的断点已按参考源码实现。 | 桌面宽度、窗口化、短高度、DPI/系统缩放、主题、密度和字体缩放组合未做成套截图；除 Files 外的 breakpoint/溢出情况未逐页验收。 |
| 表单与参数 | 影视、音乐、Reader 元数据、Files 分享、Profile 的若干字段/校验和部分 DTO 已对照；已将样例字段与后端能力字段区分。 | Admin、Auth/Setup、Security、Photo editor、Backdrop、Notifications、外部存储和其余业务表单尚未完成字段/约束/默认值/控件/校验/提交状态与 API DTO 的全量映射。不能推导为全部后端参数一致。 |

### 8.4 下一轮严格一比一验收基线

要签署“完全一致”，每张对照必须固定同一窗口尺寸、DPI/缩放、主题、强调色、语言、字体状态、内容数据和页面滚动位置；对每个页面主态及可见交互状态取得参考稿与 Flutter 成对截图。截图之外还要执行与页面有关的点击、键盘、拖拽、校验、保存、失败、恢复和撤销路径，记录前后反馈。至少覆盖本节 8.2 的所有页面/组件，并为 8.3 的颜色、字形、尺寸、层级、动效和响应式建立逐项通过/不通过/未验证记录。当前报告仍有大量“未验证”，所以不能给出全量通过结论。

### 8.5 第二轮记录

- 第二轮检查了参考页面/组件清单、桌面 CSS 主题与全局交互原语，并对照 Flutter 桌面页面、共享壳层/浮层、主题令牌及第一轮报告的覆盖边界。
- 参考运行页可读到 Reader 书本详情及 About/Chapters/Notes/Activity 标签；没有完成 Flutter 与参考稿的有效成对截图，不能将该状态作为视觉通过证据。
- 未改动产品代码；本轮只补充了本报告的范围、覆盖矩阵和验收边界。
- 未运行测试、构建或静态分析；未完成像素比较、全页面交互录制和所有 DTO 的逐项追踪。

## 9. 第三轮：差异修复记录（2026-11-16）

本轮开始按参考实现修改 Flutter 桌面 UI。以下是**已落到代码的修复范围**，不是“全站一比一验收通过”的结论。

| 模块 | 本轮改动 |
|---|---|
| 全局壳层 / Reader | Reader 书籍详情路由改为沉浸式视口，桌面侧栏不再挤压阅读内容；播放条预留高度按参考尺寸收紧。 |
| Files | 主内容改为全宽；窄窗口按参考断点隐藏目录树；侧栏去掉样例不存在的任务分区，将回收站与来源、存储摘要重新组织。 |
| Movies | “Continue Watching”的 See all 改到 History；For You 补 Anime 轨道；History 改成海报网格并接入真实清空历史操作。系列详情路由改为桌面沉浸布局，接入真实 Overview / Episodes / Files / Subtitles、季集加载、播放、收藏、标题与简介编辑、字幕上传/删除。由于 API 没有恢复历史的接口，清空后不展示虚假的 Undo。 |
| Photos | Albums 区补 New Album 卡片和创建/打开路径；Viewer 顶栏补分享面板、移入 Trash 与可执行恢复 Undo；Trash 区补 Empty Trash 确认和批量清理任务。 |
| Music | Home 增加歌单轨道与详情；补歌单新建、编辑、删除及播放/队列动作；Now Playing 增 About 和真实元数据编辑入口。 |
| Reader | 数据页合并书库分页结果和 Dashboard 最近阅读；补 Books/Comics 书架、导入入口、筛选清除和滚动分页；统计卡改为 Books/Comics/Hours/Streak。 |
| Settings | Appearance 补语言切换、语言成功反馈和 85%–125%（每 5%）文字比例滑块，并把 Ambient light / Reduce motion / Compact density 按样例归入 Atmosphere；桌面 Profile 限制名称 40 字、邮箱必填，头像选择限制 2 MB；天气位置与当前状态接入现有生产偏好和天气 Provider。 |

上述改动均保留真实会话认证和后端数据，不使用原型模拟数据。字体偏好中的既有 `large` 档从 130% 调整到样例上限 125%；它仍使用原有持久化档位名 `large`。

### 9.3 后续差异修复

- Files 表格文件图标不再统一使用中性色，改为按 MIME/类型显示参考 CSS 的文件夹、PDF、视频、音频、图片和文本色；Home 最近文件类别色令牌同步修正。
- Photos 全屏查看器增加 Delete 键移入回收站，复用已有真实删除与 Undo 流程；分享面板打开时不触发快捷键删除。
- Files 桌面侧栏的 My files、Shared by me、Recycle 文案改为参考稿对应文案；使用独立 ARB 键，通用移动端标签保持各自文案。
- Home Reading streak 卡改用真实 Reader `currentStreak`，增加最长连续天数统计字段和本地化最长值文案；今日新增数和本周音乐时长仍缺生产统计字段。
- Reader 元数据抽屉先按已有接口改为封面预览 + Title/Author/Tags/Description；后续 9.5 节记录了新增后端能力和已补齐的样例字段。
- 本批只修复源码可确认的色值和键盘动作，没有取得配对截图；最终像素与交互状态仍需运行态验收。

### 9.4 本批验证

- `flutter gen-l10n`：通过。
- 本批涉及的 Dart 文件 `dart format --output=none --set-exit-if-changed ...`：通过，无格式差异。
- `git diff --check`：通过。
- `flutter analyze`：退出码 1，仍报告 8 项已有探针/测试驱动诊断；本批修改文件没有新增诊断。`frontend/test_driver/integration_test.dart` 是用户已有改动，本批未修改、未暂存。
- 未运行测试或桌面截图验收。

### 9.1 尚未达到一比一的差异与后端边界

- **尚未完成像素级或全交互验收。** 本轮没有取得相同窗口尺寸、数据、主题、滚动位置下的参考稿/Flutter 成对截图；字体加载、颜色合成、窗口缩放、各状态动效、弹层尺寸与焦点还原仍未运行态核实。因此不能称“完全一致”。
- **Movies**：系列桌面详情、主影片 Overview/Files/Subtitles、演员/主创、服务端文件清单、From start/已看/Watchlist 和清空历史撤销均有实现；系列 Watchlist/已看状态、播放器各状态仍未逐态核验。文件 API 只返回真实文件名/大小/媒体信息，不返回规范化路径；没有构造虚假库路径。
- **影视元数据表单字段**：样例 FilmEditor 展示标题、Genre、Year、Runtime、Rating、Cast、Poster image URL、Synopsis。电影编辑现在覆盖并持久化这些字段，支持恢复首次手动编辑前的元数据；剧集编辑仍按其现有接口只编辑标题与简介。
- **Photos**：Viewer 分享/删除/恢复 Undo、批量移入 Trash Undo、Trash 清空和 Albums 内联详情已有代码；Viewer 分享抽屉已对齐桌面抽屉容器、标题、区块滚动和固定操作栏，链接与策略继续使用真实 API；批量工具栏与 Add to Album 抽屉按 `.sel-bar` / `Drawer` 样式调整；查看器保留通往既有 PhotoEditorPage 的编辑入口（该业务扩展不在样例查看器按钮清单中，按用户要求保留）。相册管理分享弹窗、批量操作逐态反馈及删除/恢复后的运行态布局仍需截图核验。相册删除接口没有恢复操作，因此相册删除没有样例 toast Undo。
- **Music 元数据字段**：Now Playing 桌面抽屉有 Cover image URL 与 Restore original，并提交 `coverUrl` / `restoreOriginal`；桌面入口的额外文件上传/移除控件已移除，移动编辑器仍多出 Genre、导入/在线歌词动作，视觉仍需统一。
- **Reader 剩余差异**：样例元数据字段、书库搜索字段和排序选项已接入并按参考对齐（见 3.5 和 9.17）；桌面顶栏模式与操作入口已按现有 Reader 状态连接，全书搜索已按章节懒加载并可跨章定位；结果粒度尚未映射为原型页码，底栏缺少全书总页数和可靠剩余时长字段；面板状态反馈、页面几何与各状态仍未运行态核验。
- **Files 分享表单**：allowDownloads、originalQuality、includeLocation 已接入桌面/移动创建与编辑表单、创建/更新/响应 DTO、share_links 持久化和跨端同步；Off、Passcode、自定义口令与 recipientUserIds 收件人选择也已实现。allowDownloads 已由后端执行；普通 Files 的原图网页尺寸副本、EXIF/GPS 剥离仍未执行。
- **Settings**：桌面天气位置已支持城市联想搜索并将选中地点保存至生产偏好；个人资料可编辑、上传和移除头像。安全、通知、存储、服务等其余视图仍未逐状态验收。
- Security、Notifications、Storage、Connected services、Backdrop、About、Admin、Auth/Setup 及 Viewer/播放器/抽屉等次级状态仍未逐屏实现和验收。认证保持真实业务流程；其视觉差异需要独立对照修复。

### 9.2 本轮验证

- `flutter gen-l10n`：通过。
- 本轮所有修改的 Dart 文件 formatter 检查：通过（0 个待格式化文件）。
- 全部 `lib test` formatter 检查：未通过，报告 30 个既有、未触及的 Dart 文件待格式化；仓库根目录 `.` 检查另因 `build/flutter_plugin_android_lifecycle` 下失效的生成路径而无法遍历。
- `git diff --check`：通过。
- `flutter analyze`：退出码 1。修复后本轮改动文件无 analyzer 诊断；剩余诊断来自现有 raster/performance 探针和 `test_driver/integration_test.dart`，其中包含用户已有的 integration driver 修改，本轮未改写该文件。
- 未运行测试或桌面运行态截图验收；按当前任务约束未执行测试。故目前结论是**核心差异已有一批代码修复，但全量一比一仍未完成**。

### 9.5 Reader 元数据与展示分类跨端接入（2026-11-16）

- Reader DTO 与两端表单现已支持 Type、Series name、Volume number、Tags、Cover image URL、Description 和 Restore original。移动端原有 Publisher/Language/Release date/Rating/Serial status/ISBN 继续保留；另补齐清空 Release date 与 Rating 的显式请求字段，避免空值被当成“未修改”。
- `readerType`、`seriesName`、`volumeNumber`、`coverImageUrl` 和首次编辑时的原始元数据快照写入 `reader_items.external_ids` JSONB；Tags 继续写 `genres.items`。未新增 Flyway 迁移。保存/恢复均经现有 Reader 条目更新与 `UPDATED` 同步事件，其他平台可读取同一份服务端数据。
- 书库展示分类使用新 `readerType` 分页过滤，Books 与 Comics/Manga 分组不再误改实际 `contentKind`；后者继续决定文本/漫画解析和阅读器路径。自定义 HTTP(S) 封面由客户端读取，清空后回退到托管封面；上传或选择托管图片会清除自定义 URL。
- 前端更新包括桌面/移动元数据表单、Reader 模型与请求、封面渲染，以及 Home/Reader 书封调用点；测试替身仅同步新增的可选 API 参数签名，没有新增或执行测试。

验证：`flutter gen-l10n`、改动文件 `dart format`、`git diff --check` 均通过；`mvn -f backend/pom.xml -pl omninest-media -am -DskipTests compile` 构建成功。`flutter analyze` 退出码 1，报告的 8 项仍为既有探针与用户保留 integration driver 诊断，本轮修改文件无新增诊断。未运行测试、未启动依赖数据库的 API，也未取得 Flutter 与原型的运行态配对截图；因此 JPQL 运行时解析和封面网络运行效果仍未验证。

### 9.6 Movies 元数据字段与恢复跨端接入（2026-11-16）

- 影片编辑抽屉按参考稿补齐 Title、Genre、Year、Runtime、Rating、Cast、Poster image URL、Synopsis，并对齐预览图与底部 Restore original / Cancel / Save 操作。Runtime 接受 `2h 14m`、`134m` 或分钟数，保存为服务端秒数，留空时清除；Year 要求四位数字，Rating 限定 0–10。
- 影片更新 API 新增 Genre、Rating、Cast、Poster URL 和恢复原始数据参数。Genre/Cast 写入既有 `media_movies.genres` / `cast_members` JSONB；Rating 使用既有 `rating` 列；Poster URL 写入既有 `content_assets.external_url` 并作为 `manualPosterUrl` 保留可编辑源地址。未新增数据库迁移。
- 第一次手动编辑时服务端在 `provider_metadata` 留存标题、原名、上映日、简介、时长、评分、类型、演员、海报资源和元数据状态快照。恢复操作回写快照并通过现有 `UPDATED` 事件同步其他平台；既有托管海报与远程海报均保存恢复信息。
- 报告前文 9.1 对影视字段缺后端能力的描述已替换为当前实现状态。主影片详情字段动作现有后端能力；系列已看/稍后观看、影片详情其余结构、播放器以及表单像素级几何仍未完成一比一核验。

### 9.7 本批验证

- `mvn -f backend/pom.xml -pl omninest-media -am -DskipTests compile`：通过。
- `flutter gen-l10n`：通过；`dart format` 修改的 Movies Dart 文件：通过。
- `flutter analyze` 对本批三个修改的 Movies Dart 文件：通过，无诊断。
- `git diff --check`：通过。未运行测试、未启动数据库/API、未做成对桌面截图；海报外链加载、数据库 JSONB 恢复行为和运行态抽屉几何仍待验证。

### 9.8 Files 分享策略与跨端接入（2026-11-16）

- Files 桌面创建对话框与移动/桌面 ShareLinkSheet 已展示 Allow downloads；图片/视频额外展示 Original quality 与 Include location。ShareLinkSheet 编辑态加载当前策略并允许更新。
- 创建/编辑 API、文件分享列表响应与公开预览响应均传递三项策略。`allow_downloads` 已加入 V001 基线，并加入 `deploy/db/upgrade-baseline-20261116.sql` 的存量库补列；已有部署需先执行该脚本再按脚本说明运行 Flyway repair，不能只更新应用镜像。
- `allowDownloads=false` 时，公开单文件接口不签发下载 URL，文件夹子项不附下载 URL，接受/转存入口返回 FORBIDDEN；公开页面隐藏下载与保存按钮并显示本地化提示。修改策略继续调用现有分享同步事件，因此其它客户端可读取相同设置。
- `originalQuality` 和 `includeLocation` 在 Files 分享记录与公开预览中已持久化/同步，但普通 Files 文件访问仍签发原资源地址，没有网页尺寸副本生成或 EXIF/GPS 清理。Photos 专用分享已有自己的脱敏映射，不代表普通 Files 分享已完成这两项内容处理。
- Off 状态、桌面自定义口令输入与收件人选择还未对齐。未运行测试，也未启动数据库/API 或取得成对截图；策略的端到端同步、拒绝路径及新旧数据库升级尚待运行态验证。

### 9.9 Music 封面 URL、原始元数据恢复与跨端接入（2026-11-16）

- Now Playing 桌面编辑抽屉补齐样例的 Edit track / Metadata 层级、Cover image URL 字段、动态封面预览、Restore original 和作用范围提示；移动编辑器也可编辑 URL 与恢复原始数据。URL 在前端和后端校验为不超过 2048 字符的 HTTP(S) 地址，不由服务端抓取。
- `UpdateMusicTrackRequest` 新增 `coverUrl`、`restoreOriginal`；`MusicTrackDto` 新增 `manualCoverUrl`、`hasManualOverride`。前端模型、请求和恢复命令均使用同一服务端记录；保存/恢复沿用音乐曲目的 `UPDATED` 同步事件。
- 后续桌面 UI 对照移除额外封面上传/移除控件，封面缩略图改为样例的 96×96 方形及 22px 上边距；歌词标签改为 12px 字段标签并显示行数，文本区对齐 10 行、14px 正文字体、10px 内边距、10px 圆角和强调色焦点环。表单字段间距、标题为空时的禁用保存态、保存成功 toast 与原型交互保持一致；共享桌面文本字段字号同步到样例根字号 14px。
- 首次人工编辑会保存字段、原封面文件引用、状态和 provider 元数据快照。原始歌词/译文另存为 text 列，避免 2 MB 歌词副本进入 `provider_metadata` 的 512 KB 限制。恢复时回写封面来源、元数据和歌词；新刮削结果会清除旧人工快照。原封面文件在可恢复期间不会被误回收。
- V001 基线与 `deploy/db/upgrade-baseline-20261116.sql` 均新增快照列。已有数据库需执行升级脚本后运行 Flyway repair，再部署新服务端；只更新应用镜像无法兼容缺列数据库。
- `flutter gen-l10n`、改动 Dart 文件格式化与后端 `mvn -f backend/pom.xml -pl omninest-media -am -DskipTests compile` 均通过。全量 `flutter analyze` 退出码 1，残留 8 项既有 integration/raster probe 诊断；当时的 Music 代码与接口桩无新增诊断。未运行测试、数据库/API 或成对截图，因此数据库升级实测与界面逐态、像素级验收仍待完成。

### 9.10 Movies 详情页元数据抽屉对齐（2026-11-16）

- 详情页实际打开的桌面编辑抽屉已改为样例字段与结构：Title、Genre、Year、Runtime、Rating、Cast、Poster image URL、Synopsis；恢复按钮只在存在人工编辑快照时显示，遮罩点击与 Escape 按样例关闭。
- 表单几何对齐右侧 520px 抽屉、92×138 海报预览、Year/Runtime/Rating 三列和 5 行简介区。Title、四位 Year、0–10 Rating 决定 Save 有效性；运行时长可输入 `2h 14m`/分钟数并映射为秒，Genre/Cast 以逗号拆分为后端数组。
- 这批没有增加后端字段或数据库迁移：`MovieMetadataUpdateRequest` 已支持 `genres`、`rating`、`cast`、`posterUrl`、`restoreOriginal` 和 `clearRuntime`；桌面详情表单现调用既有 API。保存/恢复通过现有影视 `UPDATED` 事件同步。
- 前端本地化生成与 Dart 格式化通过；本批最终静态分析和桌面运行态截图仍在验证中。未运行测试、未启动后端/数据库，接口同步与抽屉最终像素尚未实测。

### 9.11 Movies 详情动作与跨设备 Watchlist（2026-11-16）

- 主影片 Hero 新增 From start、已观看/取消已观看、Watchlist 加入/移除；操作结果以本地化 toast 反馈，已看状态同步展示在徽章并隐藏完成进度。
- From start 通过播放路由参数明确从 0 秒打开，不读取服务端续播位置；普通播放仍沿用原续播策略。
- Watchlist 从 SharedPreferences 迁为后端系统合集，首次读取时会将当前设备旧清单幂等导入，之后独立于用户手动合集与 Favorites；服务端按用户保存条目，读写端点校验 ACTIVITY_READ/ACTIVITY_WRITE，并发出 VIDEO_COLLECTION 同步事件。前端 VIDEO 实时失效处理刷新清单；同一 Watched 操作使用现有播放进度端点和 MEDIA_PLAYBACK_PROGRESS 事件。
- `V001__init_schema.sql` 扩展合集类型约束并新增每用户唯一 Watchlist 索引；`deploy/db/upgrade-baseline-20261116.sql` 为已部署数据库补齐约束/索引。存量库需执行 upgrade-baseline 后运行 `flyway repair`，再部署新后端；仅更新前端不会有跨端清单功能。
- Flutter 定向格式检查（21 个 Dart 文件）、ARBs 本地化生成、变更 Dart 文件定向静态分析（无问题）和 `mvn -f backend/pom.xml -pl omninest-media -am -DskipTests compile` 均通过。未运行测试、未连接真实数据库/API 或进行成对窗口截图；像素级和完整状态验收仍未完成。

### 9.12 Movies 详情剧情、演职人员与文件页签（2026-11-17）

- 电影详情补齐 Overview / Files / Subtitles 页签；Overview 显示服务端实际剧情、演员、导演/编剧元数据，并提供三行折叠与展开；窄窗口改为单列。
- Files 页签显示真实文件名、大小、版本、编码和主版本状态，并纳入已生成的派生视频版本。新增 `GET /api/v1/video/items/{videoItemId}/files`，按现有媒体可读授权检查条目，只返回文件名/媒体信息，不返回规范化路径；同一响应包含现行服务端转码开关。已启用时可创建真实转码任务并收到带“查看任务”动作的提示，关闭时按配置显示说明；VIDEO_ITEM 实时事件会刷新已打开的文件清单。
- 本批只增加 DTO 与查询 API，没有数据库迁移；系列详情仍由专用页面承载 Episodes / Files / Subtitles。
- `flutter gen-l10n`、改动 Dart 文件格式化、定向 Dart 静态分析及 `mvn -f backend/pom.xml -pl omninest-media -am -DskipTests compile` 均通过。未运行测试、未连接真实数据库/API 或进行配对窗口截图；运行态权限组合、文件查询和像素对照仍需验收。

### 9.13 Photos 幻灯片查看器动效（2026-11-17）

- 依据 `src/desktop/desktop.css:361`，幻灯片模式下照片以 4 秒 ease-out 从原始比例缓推至 1.14 倍并轻微平移；照片切换时按照片 ID 重新开始动画。
- 顶栏和底部胶片条在幻灯片模式下随查看器 hover 状态以 600ms 淡入/淡出，隐藏时不接收点击；默认展示控件的非幻灯片行为不变。
- 新增 `DesktopMotion.viewerKenBurns` 与 `viewerChrome` 动效令牌；系统启用减弱动效时照片缓推关闭。
- 定向 Dart 静态分析、格式化与 `git diff --check` 通过。未运行测试、未启动桌面应用或取得 Flutter/原型配对截图，因此实际图像裁切边界、hover 命中与整体视觉仍需运行态核验。

### 9.14 Photos Albums 内联详情（2026-11-17）

- 桌面 Album 卡片现在在当前 Photos 页面内展开详情，保留顶部 Library/Albums/Places/Favorites/Trash 分区栏；详情区域按参考稿展示返回 Albums 链接、大标题、照片数与集合说明、Share/Delete album 操作及无标题/无选择控件的 justified 照片墙。New album 改为 420px 右侧抽屉，只保留名称字段和集合说明；相同名称提示、禁用创建与成功 toast 均有真实实现，创建后停留在 Albums 架。
- 详情照片来自现有相册 API，继续按服务端分页读完后才允许打开图片，打开时设置 Album 浏览范围，Viewer 的上一张/下一张保持在当前相册。相册详情的 Share 管理弹窗仍使用生产分享链接管理与复制流程；删除继续调用真实相册 API，确认后显示反馈，照片本身不会删除。
- 新增中英文集合说明文案；把 Photos 页面内的回收站/地点/照片墙展示组件拆到 `desktop_photos_sections.dart`，主页面降至 800 行以内。
- `flutter gen-l10n`、涉及 Dart 文件格式化、定向 Dart 静态分析和 `git diff --check` 通过。未运行测试或配对窗口截图；Share 对话框的视觉与样例直接复制链接的流程不同，后端当前也没有相册删除恢复接口，所以无对应 Undo toast，这两项仍是差异。

### 9.15 Photos 分享抽屉样式与页眉计数（2026-11-17）

- Viewer 的 Photos 分享抽屉保留生产链接管理能力，容器改为 330px 桌面抽屉宽度、主题 panel-solid、左侧 22px 圆角、主题细描边与阴影；标题区、滚动内容区和固定底栏按桌面抽屉结构组织。打开时使用参考稿 40% 遮罩、4px 背景模糊和 320ms 遮罩淡入，抽屉以 420ms 原型曲线滑入；关闭遮罩 300ms 淡出。有效期、复制成功、设置开关和文字颜色接入桌面强调色/排版 token。只从桌面 Viewer 启用该样式，移动分享面板和幻灯片入口不切换桌面视觉。
- 分享表单的接口与字段未改：继续读取/创建/更新/撤销真实照片分享链接，保留二维码/复制、有效期、提取码、位置及原图质量控制。相册详情的 Share 管理弹窗是另一个入口，本次未将其改为 Viewer 抽屉。
- Photos 页眉此前把第二个占位参数显示成相册数，与样例 `Photos.tsx` 的“photos · videos”不符。现改为显示照片数与视频数；视频数来自现有 `movieDashboardProvider` 的 movieCount + episodeCount，因此不新增后端 DTO/API 字段，也不会使用原型固定演示数字。
- `flutter gen-l10n` 成功；8 个 Dart 文件格式化无差异；5 个相关 Dart 源文件定向 `dart analyze` 输出 No issues found；`git diff --check` 通过。未运行测试、未启动桌面应用/后端、未取得配对截图；抽屉细节、窄窗口响应和两类统计在真实服务数据下的最终画面仍需运行态验收。

### 9.16 Photos 批量工具栏、加入相册和编辑入口（2026-11-17）

- 批量操作条按 `desktop.css:.sel-bar` 固定在播放条预留空间上方（104px），使用 30px 入场位移、500ms spring、30px 背景模糊、pop 表面与 18px 圆角；动作间距和关闭按钮尺寸按桌面控件统一。原先 90px 底距及无背景模糊与参考值不符。
- 批量 Delete 成功后显示 Undo；撤销逐张调用现有恢复 API，并提供本地化的恢复数量反馈，失败时保留清晰的错误 toast。
- Add to Album 不再使用定高对话框；改用 420px 右侧抽屉，首项为 New album，后续列出真实相册封面与数量。选中照片在打开抽屉时清除；创建新相册后按后端 API 创建相册并加入所选照片，成功 toast 显示名称和加入数量。
- 按用户要求，桌面 Viewer 增加指向既有 `/photos/:photoId/edit` 的 Edit 操作，PhotoEditorPage、编辑版本 API 和恢复能力继续复用；没有改动编辑数据契约或移除原功能。该编辑按钮是按用户要求保留的生产能力，原型查看器未列出此动作，后续视觉验收需单独确认其摆放。
- `flutter gen-l10n` 成功；8 个改动 Dart 文件格式化无差异；7 个相关 Dart 源文件定向 `dart analyze` 输出 No issues found；`git diff --check` 通过。按仓库任务规则未运行测试，也未启动桌面运行态/取得配对截图。抽屉关闭时序、长相册列表滚动、创建后同步和各种失败反馈仍需运行态核验。

### 9.17 本轮剩余项修复（2026-11-17）

- Reader 搜索现覆盖 title、author、series、description 和 tags；排序切换为 Recently read、Title、Author、Progress、Recently added，并使用参考稿 Select 控件。
- Files 桌面分享补齐 Off / Anyone / Passcode、自定义或自动口令、收件人搜索选择；前端将 password 与 recipientUserIds 传入现有分享创建 API，后端提供受 FILE_WRITE 授权保护的用户目录查询。Off 会撤销当前资源的活动分享链接。触控设备拖动改成长按触发，鼠标保持即时拖动。
- Settings 天气城市输入增加防抖联想、取消旧请求与加载/无结果/离线反馈；地理编码请求使用不带 OmniNest 认证令牌的独立客户端。Profile 补真实头像删除 API，清除用户头像引用、发出 USER_PROFILE 同步事件并释放旧文件。
- Movies 清空历史新增 Undo：保留清空前进度快照，通过真实播放进度 API 恢复并刷新。Photos 查看器主图与胶片缩略图加载失败时显示主题图片图标。
- Admin 桌面 Identity 分区在同页纵向展示 Users、Roles 和 Permissions；Storage 同页展示挂载位置与外部账户，并依据当前权限请求各面板。移动端原有页签布局保持不变。
- 更新了新增 repository 契约对应的测试替身；未新增或运行测试。用户已有 frontend/test_driver/integration_test.dart 修改一并保留在提交内容中，并移除无用的 integration_test.dart import。
- Files 分享的 originalQuality=false 网页尺寸副本和 includeLocation=false EXIF/GPS 剥离仍未实现；Home 统计语义、Admin 表单细节、Auth/Setup、播放器和其余模块次级状态仍有待处理差异。全屏逐状态配对截图和像素/交互验收仍未完成，因此不能标记为一比一通过。
- 验证：flutter gen-l10n 成功；改动的 32 个 Dart 文件 formatter 检查无格式差异；后端 `mvn -f backend/pom.xml -pl omninest-system -am -DskipTests compile` 成功；git diff --check 通过。全量 `flutter analyze` 退出码 1，仅报告 7 项未触及的 integration raster/performance 探针诊断，改动文件无诊断。未运行测试，也未取得配对桌面截图。

### 9.18 Setup 按原型源码逐项核对（2026-11-17）

- 对照来源为原型源码 `src/desktop/Setup.tsx`、`setup.css`、`Select.tsx`、`select.css`；参考页面通过源码目录的 `npm run dev` 提供，不使用 `dist` 构建产物。
- 表单几何按源码的 900px 响应断点、品牌区/表单卡两列、双列字段、右上角语言胶囊和分组标题核对。修正 Flutter 断点依据，使其按视口宽度判断；品牌区在 900px 以下隐藏。
- 两个语言控件与原型一样共享当前语言状态：选择右上角语言或表单默认语言都会同步另一处，并提交 `zh-CN` / `en-US`。时区列表按浏览器 `Intl.supportedValuesOf('timeZone')` 提供可搜索 IANA 选项，标签把下划线替换为空格，选项显示当前 UTC 偏移；默认取浏览器时区。非 Web 平台使用内置常用时区回退列表。
- Setup 字段与真实接口逐项映射：安装令牌通过 `X-Setup-Token` 请求头传递；请求体字段为 `username`、`displayName`、可空 `email`、`password`、`instanceName`、`defaultLocale`、`defaultTimezone`，并在启用 TOTP 时提交 `totpSecret` / `totpCode`。确认密码只用于前端一致性校验，不是接口参数；未发现请求字段缺失或命名不一致。服务端认证与 TOTP 仍按真实生产流程执行。
- 本轮新增修正语言控件联动和视口断点；目标 Dart 文件定向静态分析、格式检查与 `git diff --check` 通过。参考页面已使用 `npm run dev`；未取得 Flutter 与原型成对截图，因此这里只记录源码层面已对齐，不宣称运行态像素验收通过。Native Flutter Desktop 当前使用常用时区回退列表，完整浏览器 IANA 列表仅在 Web 环境动态读取；若要求 Native 下拉选项也完全相同，这仍是待补差异。

### 9.19 Setup / Login 窗口与下拉外观修正（2026-11-17）

- 对照 `desktop.css`、`Select.tsx` / `select.css` 和 Flutter 桌面源码，确认 Setup 下拉触发器此前用 `bg2`（样例为 `bg`），焦点环缺失，已选项在活动态也没有样例的 accent 16% 底色；已逐项校正。时区弹层此前固定 180px，现按触发器实际宽度展开，最小 180px、右边界仍钳在视口内；悬停描边按样例与 `line2` 混合。
- 重新核对 `.setup-grid` 的最终 CSS 后修正了此前过宽的表单几何：1120px 最大宽度现在包含响应式横向内边距，宽屏按 380px 品牌列 / 6vw 间距 / 最宽 620px 表单列计算，并在 900px 断点切为单列；两步验证 QR 卡也按该断点改为竖排。卡片与控件使用的深浅底、分隔线及强调色都直接映射样例 CSS 令牌。
- 根构建器原先只在已认证时创建 `DesktopShellHost`，因此 `DesktopWindowChrome` 在 `/login`、`/setup` 等未认证路由根本不会构建。原生桌面 standalone 路由现由轻量主题宿主挂载 `DesktopWindowChrome`，保持独立页面，不创建工作区；可见最小化/最大化/关闭按钮、46px 拖拽区、双击最大化和边缘缩放区。登录与安装两页因此一并补上窗口能力。Setup 右上角移除重复语言控件，改为主题切换按钮。
- Setup 页面仍可在窗口较矮时滚动，但隐藏原生自动滚动条；时区选项列表继续保留独立滚动条。表单字段与卡片沿用 DesktopSkin 映射到的原型 `bg` / `raise` / `line2` / accent 令牌。
- 原型以 `npm run dev -- --configLoader runner --host 127.0.0.1` 从源码启动，未使用 `dist`。标准 Vite config bundler 因参考目录只读而无法写 `.vite-temp`，改用 runner 后服务器启动成功；内置浏览器连接该本机地址超时。`flutter devices` 与 `flutter build windows --debug --no-pub` 在本环境均无输出卡住，故没有可用的 Flutter Windows 成对窗口截图，窗口按钮命中/拖动尚未实机确认。此轮运行的定向 `flutter analyze` 无问题、Dart 格式检查与 `git diff --check` 通过；未运行测试。
- 后续按浅色运行截图复核材质：原型 `--raise` 是叠在纯底色上的 4.5% 色层，而 Flutter 窗口合成时露出底层会呈玻璃感；Setup 卡改为先在 `--bg` 上合成同色值再以不透明表面绘制，阴影改为 `setup.css` 的单向下投影。副标题与 2FA 说明色调整为原型 `--text2`。语言胶囊桌面端在 46px 标题栏内垂直居中，与三键组保持 28px 间距；Web 仍按原型的 16px 顶距、28px 右距。窗口按钮与拖拽/缩放只在原生 Windows/Linux/macOS 启用，Web 标题栏和移动布局不显示这些原生窗口操作。

### 9.20 Setup 焦点语义异常与右上角控件（2026-11-17）

- 输入框点击日志的 `SemanticsNode._replaceChildren` / `node.built` 断言与 Flutter 官方 [OverlayPortal 语义树问题 #187198](https://github.com/flutter/flutter/issues/187198) 的异常相同。Setup 的未认证 standalone 路由此前被 `DesktopShellHost` 外层 `Overlay.wrap` 包住，形成额外 Overlay + Router Navigator + OverlayPortal 弹层的组合；现改为 `DesktopThemeScope` 直接挂 `DesktopWindowChrome`，不再创建这一层外部 Overlay。窗口控制的提示文案改为 Semantics label，保留无障碍名称，不用 Tooltip 再引入 Portal。
- Setup 右上角移除独立语言切换，保留表单“默认语言”字段作为唯一入口；右上角改为浅色/深色切换，原生桌面在标题栏中垂直居中并留出窗口按钮间距，Web 保持独立右上角位置。
- 窗口 controls 保留样例每键 46×46 命中区；最小化、最大化/还原、关闭图形改用 15/14px、1.8px 描边的样例路径，关闭悬停色改为 `#c4423b`。仅原生 Windows/Linux/macOS 构建 controls，Web 与移动端不显示。

### 9.21 Flutter 输入焦点语义树断言与相似弹层排查（2026-11-17）

- 新的 Windows Debug 日志确认程序构建启动成功，但语义树刷新期间多次触发 `SemanticsNode._replaceChildren` 的 `!child.attached` 断言，并出现 `node.built` 断言。日志没有指出具体应用组件；异常与 Flutter 开放问题 [OverlayPortal 语义树问题 #187198](https://github.com/flutter/flutter/issues/187198) 的症状相似，因此这里只按 Setup/Login 路径处理，不能据此推断全应用每个图标按钮都需要替换。
- 撤回全库图标按钮包装。仅在 Setup/Login standalone 路由关闭框架 Tooltip 的悬浮层，并为密码显示、TOTP 密钥复制等表单动作保留 `Semantics.tooltip` 标签；普通 `IconButton` 继续使用 Flutter 原生实现。桌面 `DesktopSelect` 改用 `OverlayEntry`，保留搜索、键盘导航、位置钳制和收起后焦点返回，以消除 Setup 时区/语言下拉的直接 `OverlayPortal` 路径。
- 相似机制扫描发现：Flutter `MenuAnchor` 在 Setup 的窄屏备用页面与通用 `AppDropdown` 中仍被使用，Music 音量面板也保留项目直接 `OverlayPortal`；各模块仍有常规 Flutter Tooltip。本次日志没有调用栈把问题定位到这些控件，故保留原生行为，列为后续若在对应页面复现时的追查点，不做全平台批量替换。
- 验证：`flutter analyze lib --no-pub` 无问题；6 个改动 Dart 文件的 `dart format --output=none --set-exit-if-changed` 无格式差异；`git diff --check` 通过。Windows Debug 构建与 `flutter --version` 在本轮启动后均长时间没有任何输出，随后手动终止，因此不记为构建通过。按仓库规则未运行测试。桌面 UI 控制会话审批超时，尚未点击输入框作运行态复测；当前修复是定向源码规避，焦点交互结果仍待实机确认。

### 9.22 Hero 圆角、Movies/Photos 布局与启动重绘（2026-11-17）

- 逐个核对使用 Hero 圆角的桌面卡片：Home、Movies 影院轮播、Photos 地点地球、Reader 继续阅读/洞察、Reader 书本详情。修复图片/子内容越界未裁切的容器；边框移到 `foregroundDecoration`，让内容绘制后仍完整显示圆角描边。Music Hero 本已使用该方式。Movie/Series 详情是全屏沉浸头图，样例本身没有圆角卡片，未强行套圆角。
- Movies 页面移除 Flutter 顶部七项分类 Seg，保留原有电影/剧集/动漫内容轨道；分区深链仍打开对应列表，子列表仅显示“返回 For you”动作。空态判定补入 Anime，并避免 dashboard/center 首次加载期间提前显示空状态。路由参数改变时同步切换 tab，避免同一页面实例停留在旧列表。
- **参考版本冲突**：用户描述样例没有 Movies 顶部分段；当前被指定目录的 `src/desktop/Movies.tsx:19,65–66` 明确声明和渲染该分段。实现按用户最新明确要求去掉它，但需确认此目录是否已更新到用户实际看的参考版本；目前不宣称该细节与目录源码一致。
- Photos 复核 `DesktopPageHead` 换行行为：操作区原先换到第二行后默认靠左；新增仅供 Photos 使用的右对齐窄屏布局，宽屏继续与标题同行。其它页面的通用页头策略不变。
- 启动/首页性能的源码优化包括：Web 字体准备和 SharedPreferences 读取并行启动；桌面环境色背景订阅改为只选择当前模块实际使用的封面 URL；Home provider 订阅改为选择指标、继续播放目标、当前播放文案等实际消费字段，降低无关模块数据变化引发的页面重建。没有更改画面内容、尺寸或动效。
- 本批运行态对照尝试：按要求从原型目录执行 `npm run dev`（未用 `dist`）；Vite 报 8443 已被占用，当前桌面自动化无法列出可连接浏览器，因此本批不能从该会话取得新截图。
- 本批涉及 `bootstrap.dart`、桌面 Shell、Home/Movies/Photos/Reader Hero 与共享页头。验证：改动 Dart 文件 `dart format` 已执行；`flutter analyze lib --no-pub` 通过（0 issues）；`git diff --check` 通过。未运行测试。没有运行 Flutter profile/Windows 构建，故启动延迟的实际前后毫秒和最终帧率没有测量；其它页面性能热点及像素级圆角仍需运行态逐屏确认。

### 9.23 Music Home 与曲目列表对齐（2026-11-17）

- 对照 `src/desktop/Music.tsx`，Home 删除原型没有的独立 Tracks 轨道；Albums / Playlists 保留 `See all (n)` 入口并切换到各自分区，空数据时仍展示分区标题和入口。
- Up next 改为原型标题与 `Open queue` 操作；操作打开桌面 Dock 的 Queue 页签。队列行复用曲目表格（封面、艺人、专辑、时长、操作），保留服务端队列索引播放，不再以纯文本行代替原型表格。
- Tracks 页补 All / Favorites 计数筛选、Title / Artist / Album / Duration 排序和 20 / 50 / 100 行分页；Favorites 页维持原型独立收藏列表，不重复显示 Tracks 工具栏。搜索无结果时可清除筛选。
- 曲目行单击打开详情 Dock，双击播放；悬停时序号位显示播放/暂停按钮，右键菜单补详情与元数据/歌词编辑入口，动作继续使用现有后端与详情实现。
- 验证：`flutter gen-l10n` 成功；Music 的 3 个 Dart 文件 `dart format` 无格式差异；定向 `flutter analyze --no-pub` 无问题。尚未运行测试、启动桌面程序或取得原型/Flutter 配对截图；键盘/鼠标状态、窄宽度下工具栏换行、完整曲库分页与真实队列反馈仍需运行态核验。Home 的 Library/Listening 统计语义，以及播放器和元数据抽屉的全状态对照仍未关闭。

### 9.24 Home 阅读最长连续天数统计对齐（2026-11-17）

- 对照 `src/desktop/Home.tsx` 的 Reading streak 卡，保留真实当前连续阅读天数作为主值，并补上原型副标题展示的历史最长连续天数。
- Reader 统计响应新增 `longestStreak`；后端按实例时区提取去重阅读日期，并用 PostgreSQL gaps-and-islands 聚合最长连续天数，只返回一个聚合值，不将全量会话记录加载进 JVM。前端模型和首页副标题消费该字段，英文/中文分别显示 `Longest: N days` / `最长：N天`。
- 首页 Library 总数已通过现有音乐中心状态补入真实音乐 `trackCount`，不再漏计音乐曲目；Files 是否应计入该指标仍需与原型所指的 Library 统一定义。
- Library 今日新增与 Listening 本周小时仍没有完整生产统计契约。音乐历史请求当前可传 `playDuration`，但 Flutter 播放流程没有可靠地累计并回写实际播放时长，因此暂不将时长字段视为可用统计来源。
- 验证：`flutter gen-l10n`、5 个改动 Dart 文件的格式检查、Reader/Home/Music 投影文件定向 `flutter analyze`、`mvn -f backend/pom.xml -pl omninest-media -am -DskipTests compile` 与 `git diff --check` 均通过。未运行测试；真实 PostgreSQL 执行和数据结果尚未验证。未取得原型和 Flutter 配对截图，最长天数副标题的最终宽度/截断和全卡几何仍需运行态验收。

### 9.25 Reader 桌面沉浸阅读控件（2026-11-17）

- 对照 `src/desktop/ReaderView.tsx` 与 `src/desktop/desktop.css`，桌面宽窗阅读器新增 Book / Swipe / Scroll 分段切换，并映射至已有 `readingMode` 与 `pageTurnMode`；当批首次实现时 Web 页模式仍受旧产品规则限制，后由 9.27 按用户确认调整为桌面 Web 可用。
- 桌面顶栏现在依序提供搜索、目录、添加/移除书签、批注与阅读设置入口。纸页双模式采用原型深色书桌面，Scroll/Swipe 采用阅读主题纸色渐隐；颜色取自 Reader 主题色板，设置页和章节切换遮罩同步使用阅读画布底色。
- 桌面底栏改为原型居中进度轨道，显示当前章节页码（分页模式下）或章节位置、真实全书进度百分比，并支持拖动跳转。原型显示全书总页数范围及剩余分钟；当前 Reader 数据没有可靠的全书页数与阅读速率统计，本次不生成推算值。
- 本批变更包括 `reader_view_desktop_top_bar.dart`、Reader 顶/底栏、阅读设置与色板、阅读页面布局，以及英文/中文 ARB 和生成的本地化类。验证：`flutter gen-l10n` 成功；Reader 相关文件定向 `flutter analyze --no-pub` 与全 `lib` 分析均无问题；改动 Dart 文件格式检查与 `git diff --check` 通过。全仓 `flutter analyze --no-pub` 仍报现有 `desktop_movies_view_test.dart:164` 引用未定义 `desktopMoviesSegTabs`，并有 7 条既有 probe lint；全 `lib` 格式扫描报告 24 个未修改文件格式不同，未批量格式化这些无关文件；含 `build/` 的全仓格式命令还遇到已消失的 Gradle transform 子目录。未运行测试或 Flutter Windows 程序，未取得 Flutter 与原型配对截图；窄宽模式断点、面板打开/关闭反馈和视觉几何仍需实机核验。

### 9.26 Reader 搜索输入响应与延迟（2026-11-17）

- 章内搜索改为使用 `MotionToken.fast` 防抖；12,000 字符及以上的原生端文本扫描通过 `compute` 放到后台 isolate，较短内容和 Web 仍走轻量同步扫描。输入变化时取消旧定时器，并用搜索代数丢弃过期结果；命中上限和原字符串偏移语义保持不变。
- 这项优化先降低了长章节扫描造成的输入延迟；整本书搜索随后由 9.28 增补。
- 验证：`dart format lib/features/reader/presentation/widgets/reader_find_panel.dart` 无格式变更；`flutter analyze --no-pub lib/features/reader/presentation/widgets/reader_find_panel.dart` 无问题。未运行测试；目前没有输入长章节的实际计时或 Windows profile 数据，也未做配对截图。

### 9.27 桌面 Web Reader 阅读模式（2026-11-17）

- 按用户确认，以桌面原型为准，覆盖原来的 D3 Web-only-scroll 决策。`supportsPageMode` 现在允许桌面浏览器及原生平台使用分页，Android/iOS 手机浏览器继续滚动模式；书本/漫画顶栏、底栏和阅读设置共用此平台能力判断。
- Web 分页使用现有 PageNavigator，不改变章节、进度或后端字段。大型章节的分页测量仍受 Web 单线程约束，实际卡顿程度需要在桌面浏览器运行态测量。
- 本批源码与 Reader 搜索优化一起验证：改动文件 `dart format` 无格式差异；全 `lib` 的 `flutter analyze --no-pub lib` 无问题；`git diff --check` 通过。未运行测试或浏览器截图。桌面 Web 分页的实际大章节滚动/分页负载、键鼠手势与几何仍需运行态核验。

### 9.28 Reader 整本书搜索（2026-11-17）

- 按参考面板文案开放整本书搜索，输入至少两个字符后逐章加载并搜索块模型纯文本；查询改变后以 generation 取消后续读取，最多展示 60 个命中，与原型数量上限一致。
- 命中只保存短上下文与源字符偏移，不把全文保留在结果里。阅读器为全书搜索增加 3 章、每章不超过 16,000 字的有界语料缓存；其余章节解析后释放，不触发布局测量。超长原生章节解析/扫描使用后台 isolate，桌面 Web 受 Flutter Web 单线程限制，首次全书检索的总等待时间仍需实测。
- 命中包含章节标题与段落上下文，点按会定位到同章偏移或切到目标章节后定位；读不到的章节会显示部分搜索提示。原型按动态分页后的一页一条命中并显示页码；Flutter 当前按出现位置列出、没有全书页码，仍有结果粒度差异。英文/中文搜索标题、输入提示和错误提示进入 ARB。
- 验证：改动 Dart 文件 `dart format --output=none --set-exit-if-changed ...` 无格式差异；`dart analyze lib` 无问题；中英文 ARB 用户文案键集合一致且新增键无重复；`git diff --check` 通过。`flutter gen-l10n` 未能运行：Flutter SDK 尝试创建 `D:\Development\flutter\bin\cache\lockfile` 时被文件系统权限拒绝，因此已按 ARB 手动同步生成的本地化接口并由 Dart 分析确认编译。未运行测试或浏览器配对截图；桌面 Web 的首次全书检索耗时仍需真实曲库测量。

### 9.29 Home 统计数据契约复核（2026-11-17）

- 参考首页 Library 副文案为 `+N today`，Listening 为本周小时数；当前 Flutter 使用真实的模块总量和最近播放条数，不是原型中的这两种口径。
- `MusicDashboardDto` 只有 `playHistoryCount`，没有按周汇总的实际秒数。前端起播时写入播放历史的 `playDuration` 默认值为 0，因此不能用现有计数推导聆听时长。各媒体 Dashboard 也没有跨模块的“今天新增”总计字段。
- 这些统计不能用播放次数乘曲目时长等方式估算；若要做成原型的实时生产数据，后续需要在播放会话结束/暂停路径记录实际播放秒数，并提供按时间窗聚合的后端字段，同时确定跨模块新增统计的时区边界。

### 9.30 Photos 缩放条与桌面进度滑块（2026-11-17）

- 对照 `src/desktop/Photos.tsx:22,54-58` 与 `desktop.css:93-99,338`：缩放范围为 150–320、初始值 210，轨道宽 120px、图标间距 10px；滑钮为常显强调色圆点与 4/7px 悬停光圈，缩放轨道不显示已填充段。原先 Flutter 把 0 当最小值，210 的滑钮落在约 66% 而非约 35%；现改为实际 min/max，并按滑钮半径 inset 映射可拖范围。
- 桌面 `DesktopSlider` 新增可配置范围、轨道填充、滑钮颜色/尺寸/常显/光圈及键盘步幅；原有进度滑块默认继续显示强调色已完成段、抬高的悬停轨道和悬停滑钮。`DesktopTheme` 为 `AppSlider` 明确设置强调色完成轨道、弱化未完成轨道、4px 轨道和白色滑钮，使未覆盖模块主题的拖拽进度条也有清晰进度层次；播放器和 Reader 保留各自明确的语义色。
- 验证：3 个改动 Dart 文件已格式化；全 `dart analyze lib` 无问题；`git diff --check` 通过。未运行测试，未取得运行态配对截图；窄窗口下整组页头操作的最终几何仍需实机核验。

### 9.31 Photos 分类栏与缩放条同排（2026-11-17）

- 用户指出 9.30 只校正了滑块内部位置，没有固定缩放条相对分类栏的位置。重新对照 `desktop.css:127,338` 后发现 `DesktopPageHead` 把 `.head-actions` 实现成 `Wrap`，并在宽屏 Row 中把标题与操作区各分配一半宽度，导致操作区内部再次换行，缩放条掉到分类栏下方。
- 操作区现用不换行 `Row`，在宽屏按内容宽度置于页头右侧；需要折行时只将整组（分类栏 + 缩放条）放到标题下方并靠右。组内顺序保持 Seg 后接缩放条，组间距 10px，符合原型 `.head-actions` 的单行布局。
- 验证：`desktop_surfaces.dart` 已格式化；全 `dart analyze lib` 无问题；`git diff --check` 通过。未运行测试或配对截图；运行窗口中的最终几何仍未实机确认。
