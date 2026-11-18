# OmniNest 前端原型对齐交接文档

- 日期：2026-11-18
- 范围：OmniNest Flutter 桌面前端与指定 React 原型的剩余差异处理
- 总体状态：**尚未完成一比一对齐；源码层已有多批修复，但全量运行态验收未完成。**

## 1. 权威基准与任务约束

- 唯一视觉/交互基准：`D:\Development\Project Collection\UI Design\OmniNest Desktop UI UX`。
- 源码核对范围：`src/desktop/*.tsx`、`desktop.css`、`extra.css`、`setup.css`、`ui.tsx` 及对应组件样式。参考项目必须从源码目录运行 `npm run dev`；不使用 `dist` 作为视觉基准。
- 被审实现：本仓库 `frontend/` 下 Flutter Web/Desktop 页面和共享桌面壳层。需要同步或处理内容字节/API 参数时，可以按用户先前授权修改后端。
- 页面视觉对齐不能以“数据来自生产接口”作为跳过布局/字段/反馈差异的理由；同时不得用虚构统计数据补足原型占位。
- 已确认的产品决定：认证保留真实服务端流程和 TOTP；Reader 桌面 Web 按原型开放 Book/Swipe；Photos 分享抽屉保留但需按原型样式；照片查看器保留既有编辑入口；Files 长按拖动是额外要求；Movies 保留“为你推荐、电影、剧集、动漫、收藏夹、待看清单、历史”七项分类，按用户本轮明确要求执行。
- Movies 分类按 `src/desktop/Movies.tsx:20,67` 和 `imgs/dark/45-movies-category.png` 保留七项分段；Flutter 已补齐分类返回入口、区块标题/数量操作与初始骨架位置，仍需配对运行态截图验收几何与切换反馈。

## 2. 当前仓库状态与已完成项

- 最近的 UI 代码基线：`d3a4e2840 Keep Photos header actions on one line`；前一项相关提交：`8e0589734 Align Photos zoom and desktop progress sliders`。交接文档初次提交：`01db400b0 Add frontend parity handoff checklist`。
- 当前工作区有 `frontend/lib/app/l10n/app_localizations.dart` 的既存本地修改。接手时先审阅其 diff，避免覆盖或误提交。
- Photos 缩放条已按原型设置 150–320 范围、120px 轨道、两侧 10px 间距和常显强调色滑钮；默认 210 映射约 35%。页头分类栏与缩放条为不可拆分单行组，宽屏靠右，窄屏整组移到标题下方。
- 桌面通用 `DesktopSlider` 已支持非零最小值、不同轨道填充和滑钮样式；`AppSlider` 桌面默认主题明确区分强调色已完成轨道与低对比剩余轨道。播放器/Reader 显式指定的语义颜色保留。
- 底部音乐播放器依 `04-music.png` / `more.css` 对齐为 66px 高、最大 1080px 可视宽；≤1180px 收至 860px 且隐藏音量滑块，≤860px 压缩曲目/中心列并隐藏艺人副标题，≥1360px 才显示频谱。收藏、右侧控件间距与 36px 时间标签已调整；仍需在断点尺寸取得配对截图确认实际排布。
- Movies 页已按 `Movies.tsx` 和 `desktop.css:308-315` 补齐分类返回入口、For you 分区标题/数量/See all 数量操作、Hero 响应式文案坐标与正确底边距、真实继续观看进度标签，并将分类骨架固定在内容原位；Photos 新建相册卡已改为网格末尾透明虚线占位，无图片卡 hover 光晕。
- Movies、Photos、Music 页头均有样例 Import 入口；Reader Import 按钮使用 upload 图标并位于 Overview/Library 左侧。媒体导入弹窗本轮按 `21-import-movies.png` 修正为最大 760px，候选列表按样例 CSS 自然展开并在 340px 后滚动；导入来源、后台任务和元数据匹配继续接真实 API。
- 阶段 9.58 将 Movies、Photos、Music 的设备文件导入改为异步队列：选择后显示 queued Toast 和 View tasks 动作，逐文件进度、取消和失败重试进入顶部任务面板；页面离开后仍继续，登录会话切换时取消本地上传。Photos 移除照片卡片指针跟随 shine 和透视倾斜。阶段 9.60 重新核对原型最终 CSS 后，按样例恢复未选中卡片的黑色悬停投影；保留图片缩放、选择/标题反馈，不添加彩色外发光。
- 阶段 9.59 对齐 Settings Security 的 Active sessions 行：当前设备置顶，展示设备名、平台及相对活跃时间，使用样例的 This device/Sign out 标签和直接下线反馈；动作仍调用真实会话撤销接口。实机行高、窄窗口和 API 失败状态仍待截图验收。
- 前端多模块已完成部分源码修复：Movies 空态/详情动作及分类结构、Photos 相册详情与查看器操作、Music Home/Tracks/Queue、Reader 桌面阅读模式和元数据、Files 分享策略与拖动、Settings Profile/Appearance/Weather、Admin Identity/Storage 信息架构、Setup/Login 窗口控件等。具体实现证据以[差异报告](UI_DESIGN_DIFF_REPORT.md)第 3、4、9 节为准。
- 上述代码修复多数尚无同视口 Flutter/原型成对截图；不得据源码存在对应控件就标记为像素/交互通过。
- Home Listening 与 Library 今日新增已接入真实 Dashboard 汇总（阶段 9.54–9.55）；Library 总量仍不含 Files，首页四卡及全页仍未通过运行态配对验收。
- 阶段 9.56 将 Movies/Photos/Music 导入弹窗改为 760px 最大宽度和 340px 最大候选列表高度；`flutter analyze --no-pub lib` 无问题，Windows Debug 构建成功。启动窗口因缺少 `OMNINEST_API_BASE_URL` 抛出 `Bad state: 服务器地址未配置`，尚未进入媒体页。
- 阶段 9.60 再读 `ImportDialog.tsx` 确认排队 Toast/任务入口后，将通用桌面导入入口一并切到后台文件队列，清除旧式阻塞进度 Dialog；移动紧凑布局仍使用进度 Sheet。Photos 悬停已按 `polish.css` 最终规则补回黑色阴影（非发光）。定向分析 9 个源文件通过，配对截图和真实上传仍待验收。
- 阶段 9.61 Photos Library 日期组、Favorites 和 Album 加入长按拖动排序、选中项成组移动、FLIP、边缘滚动和日期组 Reset order；顺序按账号保存在本地。阶段 9.62 补上约 420ms 的 Overlay ghost 落位/取消回位动画，并为 Library/Favorites 接入每页 50 项的触底续载。阶段 9.63 修正 Viewer：Library 从任一日期组打开后按全图库排序浏览；前进至当前末项时继续取下一页，收藏亦可续页；胶片条展示已加载项。阶段 9.64 将 Settings Storage 图例固定为样例的 Video/Photos/Music/Documents 四类，并把其它文件类别真实字节合并到 Documents，不使用样例演示数值。全量 `flutter analyze --no-pub lib` 通过，Photos 交互、分页与真实账号储存图例仍待运行态截图验收。
- 阶段 9.65 将 Admin Storage 的实例级 OAuth 配置改为 Google Drive、OneDrive、Dropbox 逐项 Configure/Edit，使用 460px 抽屉并回填公开字段；密钥留空时沿用服务端密文。阶段 9.66 按最新产品规则完成管理员新建账号首次改密流程；自助注册不要求改密，普通账号自行选择是否启用 2FA，仅 SUPER_ADMIN 强制注册。V003 为账号首次改密状态增加持久化字段，并将旧强制 2FA 角色配置收敛为 SUPER_ADMIN。`flutter gen-l10n`、`flutter analyze --no-pub lib` 和 `mvn -f backend/pom.xml -pl omninest-app -am -DskipTests compile` 均通过；未运行测试、真实数据库迁移或交互截图。
- 阶段 9.65 将 Admin Storage 的实例级 OAuth 配置改为 Google Drive、OneDrive、Dropbox 逐项 Configure/Edit，使用 460px 抽屉并回填公开字段；密钥留空时沿用服务端密文。S3/WebDAV 继续作为用户级连接账户展示。`flutter gen-l10n` 与全量 `flutter analyze --no-pub lib` 通过；管理页交互和配对截图仍待验收。

## 3. 待处理差异清单

### P0：建立可信的逐屏验收基线

- [ ] 在原型目录启动源码版 `npm run dev`，确认服务实际打开的是用户指定目录的当前版本；遇到端口占用或 Vite 临时配置问题时，选空闲端口/runner 配置继续从源码运行，不能转用 `dist`。
- [ ] 启动 Flutter 目标桌面端或桌面 Web；确认截图来自当前仓库构建，而非旧窗口、旧端口或其他工作目录。
- [ ] 固定并记录相同窗口宽高、DPI/缩放、语言、主题、强调色、字体加载、数据状态与滚动位置。逐页保存原型/Flutter 成对截图及关键组件 bounding box。
- [ ] 建立状态矩阵：default、hover、focus、pressed、selected、disabled、loading、empty、error、success、undo；抽屉/菜单还要记录打开、滚动、关闭和焦点返回。
- [ ] 以 `imgs/dark/45-movies-category.png` 和 `src/desktop/Movies.tsx` 的七项分类为基准，检查 Flutter 的分类栏尺寸、位置、选中态、空态及分类切换运行反馈。
- [ ] Photos 缩放条刚修复了操作组结构，但没有运行态截图；确认宽屏/窗口化/窄宽三种尺寸下分类栏右侧紧接缩放条，没有换行、遮挡或裁切。
- 本轮再次从指定原型目录启动 Vite 源码，runner 模式报告 `VITE ready`；Edge 与本机只读 HTTP 请求访问 `localhost:5173` / `127.0.0.1:5173` 均连接超时。Windows Debug 客户端已重新构建并启动，但当前构建没有配置 `OMNINEST_API_BASE_URL`，启动页显示 `ProviderException: Bad state: 服务器地址未配置`，无法进入媒体页。P0 配对截图与几何测量仍未完成，不能据源码变更给全量视觉通过结论。

### P1：有明确业务/数据契约缺口的项

| 模块 | 尚未完成 | 后端/API 影响与约束 |
|---|---|---|
| Home | Listening 显示服务端本周累计时长，Library 显示服务端今日新增；Library 总量仍不含 Files。页面几何仍未运行态验收。 | 音乐播放时长由会话 API 更新已有 `music_play_history.play_duration`；四个媒体 Dashboard 增加 `itemsAddedToday`，Home 汇总 Movies/Photos/Music/Reader。Photos 使用配置时区，其他三个使用系统时区；部署需保持一致或接受日界差异。旧播放历史不回填，真实数据库结果和运行截图未验。 |
| Movies | 本轮源码补齐七项分类内容结构、Hero 坐标、For you 轨道标题/计数/See all 与加载占位；播放器音轨/字幕/设置/全屏、错误状态和运行态几何未验，系列已看/Watchlist 状态仍需逐态对照。 | 详情和主要动作已接真实 API；不要用演示数据替代生产媒体信息。以指定源码和 `45-movies-category.png` 为分类栏参考。 |
| Photos | Import 弹窗现按样例接受照片与视频，并按所有者及 SHA-256 跳过重复媒体；视频条目、封面和详情播放链路已补，仍待实际上传/API/窗口运行验收。日期组、收藏和相册的拖动排序已接入账号隔离本地存储；Library/Favorites 已按 50 项分页触底续载，Viewer 从日期组打开时按全图库顺序跨日浏览并在末尾续页。AI labels 内容与来源、分享弹窗、批量操作、失败占位、Undo 与删除/恢复反馈也未全态核验。 | 视频复用 `photo_items.format` 与 `provider_metadata`，不新增迁移；`PHOTO` 导入任务登记 Photos 条目并异步提取 poster 与尺寸。重复检查在事务锁内复核，旧视频对象缺少摘要时通过受权限校验的内容流计算。ffmpeg/ffprobe 不可用时视频仍可入库，但 poster/尺寸可缺失；本地照片排序依原型 `useStored`，无需 API。 |
| Music | 桌面列表与 Now Playing 共用样例结构的元数据抽屉，宽度现为 480px 且遮罩可关闭；播放状态/队列动作缺全状态截图。移动共享 Music Deck 仍有 Genre、文件封面、歌词导入/在线匹配等扩展操作，属于另一套移动管理流程。 | 桌面编辑仍使用 Title、Artist、Album、Cover image URL、Lyrics 字段并保存真实服务端元数据；本周播放秒数现由会话接口累计到已有字段。API/数据库运行态与配对截图仍待验。 |
| Reader | 全书搜索结果按动态页码映射仍未实现；原型全书页码范围和剩余分钟缺可靠数据来源；沉浸阅读顶/底栏、设置、跳转反馈待运行态核验。 | 当前后端没有全书页数/实际阅读速度统计。若要求真实值，需要明确数据契约；不要估算或伪造。桌面 Web 已按原型允许 Book/Swipe/Scroll，手机浏览器仍保留 Scroll。 |
| Files | `originalQuality=false` 尚未提供网页尺寸副本；`includeLocation=false` 尚未从内容字节剥除 EXIF/GPS。拖入上传、悬停展开、移动文件、选择/批量反馈尚未全态验收。 | 两项分享策略目前可持久化/同步，但内容管线未执行处理，不能视为完成。允许改造后端；需覆盖原图、格式不支持、无元数据、权限拒绝和失败反馈。 |
| Settings | Security 密码字段规格与强度反馈已按样例补齐；Notifications、Storage、Connected services、Backdrop、About/updates 的保存状态和失败态仍未逐项运行态核对。Storage 图例现固定为 Video/Photos/Music/Documents 四类，数值来自真实账号 API；Find duplicates 接真实 SHA-256 汇总并对缺少摘要文件发出提示，仍待 API 数据库运行验证和成对截图。Connected services 源码已恢复为 Music platforms/Other 两卡；Last.fm 无服务端能力，继续显示未配置说明。 | Profile 显示名 UI 限 40 字、DTO 可接收至 120 字；前端已按原型收紧。密码按钮按样例提供强度门槛，但仍走真实服务端改密 API及长度限制。两步验证保留真实注册流程。Last.fm 和其它表单字段不能声称全部一致。重复扫描仅覆盖个人空间当前活动文件，排除共享空间、回收站、历史版本及无已验证摘要的内容；未验证大库性能。 |
| Admin | 用户/角色/权限/配额抽屉、权限矩阵、危险确认、Operations 各页签、Configuration Review/Save/Rollback 仍未逐项运行态验收。Storage 新建位置抽屉已按 460px 样例结构呈现 Mount key、Display name、Visible to；OAuth 配置按 Google Drive、OneDrive、Dropbox 逐项提供 Configure/Edit 抽屉，密钥不回显。Overview 已恢复样例的四张 KPI、14 日上传图与重新计算卡；Storage KPI 使用当前登录账号的既有文件存储统计 API，与桌面侧栏/首页共用同一配额数据。新建/编辑用户抽屉已补真实配额、资料、状态字段；创建账户时可要求首次登录修改临时密码（默认开启），自助注册不要求改密；普通用户自行开启 2FA，仅 SUPER_ADMIN 强制注册。V003 增加首次改密状态字段并收敛旧强制 2FA 角色配置；既有数据库待执行迁移。管理员重置临时密码入口未实现。 | Admin Configuration API 补充默认值与敏感字段标志，恢复默认值进入草稿后通过现有 Review/Save；敏感默认值不返回明文。Storage Usage 分类按对象 MIME 字节聚合，不用种子值。OAuth 应用继续使用现有加密凭据 API；S3/WebDAV 为用户级连接账号，保留真实账号列表。Operations/System Logs 已接入受权限保护的当前 API 进程内存日志环（最多 10,000 条，重启清空，不汇总 Worker/Scheduler 或其它实例）；待 API 运行验证脱敏、授权、搜索和导出。系统仍没有在线会话数。首次改密和 2FA 挑战的完整交互、API 失败态及其余字段/权限/API DTO 仍需逐项运行态核对。 |
| Movies / Photos / Music / Reader | Movies、Photos、Music 页头已增加样例 Import 入口和双来源导入弹窗；Reader Import 使用 upload 图标、软按钮并移到 Overview/Library 左侧。导入弹窗最大宽度及候选列表上限已按样例 CSS 修正；Movies/Photos/Music 设备导入现按原型排入后台队列，含逐文件进度、取消、失败重试和任务面板入口，页面切换不终止上传，换登录会话会取消本地队列。Photos 移除了照片卡片指针跟随光晕和透视倾斜，保留样例黑色 hover 阴影；排序按日期组、收藏、相册分别存储在账号本地偏好中，Library/Favorites 自动续载当前分页。仍待同条件桌面运行截图核对队列、排序、失败反馈和悬停状态。 | `POST /api/v1/files/media-imports` 检查归属、生命周期、个人空间与媒体格式，所选目录展开后经 Outbox 创建最多 500 个识别任务。Photos 视频走现有任务总线，`photo_items.format` 识别类型，无 schema 变更；后端从有界本地暂存提取 poster 和尺寸，ffmpeg/ffprobe 不可用时允许条目无封面/尺寸。设备上传和媒体自动导入继续使用既有上传会话与服务端任务接口，未增加后端接口。 |
| Auth / Setup | Login 左侧已换用用户提供的照片、移除样例没有的光晕，并按样例 CSS 增加 30 秒 kenburns 缓推；本轮补上 `.auth-art` 等效裁切，限制放大壁纸在左侧画幅内，并按 900px 断点及 420–560px 列宽重做表单区自适应。登录表单、TOTP、Setup 各步骤仍未运行态逐屏验收。Dart 格式和登录页静态分析通过；Windows Debug 构建此前无输出挂起并已中断，没有明确 OmniNest 窗口可供截图。原生端时区回退列表不含完整浏览器 IANA 列表。 | 同一照片已成为内置默认壁纸资源，内置素材 ID 不变；保持真实后端认证与 TOTP。安装请求字段已静态映射，但全部状态/API 约束仍需核验；不要将其改成预览认证。 |

### P2：全局视觉、反馈、响应式和性能

- [ ] 壳层：侧栏/Dock/标题栏/详情 Dock、存储卡、搜索和命令入口、账户/任务/通知浮层、Context menu、Toasts/Undo，逐项比较位置、层级、尺寸、滚动与关闭方式。
- [ ] 底部播放器已按源 CSS 更新宽度断点和控件密度；详情坞现固定 348px 内部布局并裁切收放动画区域，修复中间帧挤压页签行引起的 RenderFlex 溢出。仍需在 1360、1180、860px 附近及窗口化高度实机核对可视宽度、控件间距、字幕隐藏与详情坞动画。
- [ ] 颜色与材质：深浅主题及 Sage/Mist/Copper/Iris 强调色下，校验背景叠层、透明度、动态壁纸对比度、文字、选中/禁用/悬停/按下状态；电影/剧集/书籍详情的全站壁纸遮挡已按源码修复，仍需切换“全站/首页与音乐”并覆盖静态/视频壁纸运行态。照片/海报和错误占位也要覆盖。
- [ ] 桌面共用输入框已由 `DesktopTextField` 实现样例字段的 40px 高度、10px 圆角、raise/raise2 填充、强调色边线及 4px/18% 焦点外环；管理台顶栏 32px 搜索、OAuth 应用抽屉、维护表单和用户配额弹窗已接入。移动端继续使用原有输入控件。继续扫描剩余桌面页字段，保留命令搜索、OTP 和自定义歌词编辑等样例专用控件，并用窗口态验证焦点外环未被裁切。
- [ ] Storage 的「查找重复文件」现可查询当前个人空间的服务端 SHA-256 汇总，并报告未核验文件数；按真实账号数据验证扫描范围和耗时仍待执行。
- [ ] 字体与布局：确认字体真实加载和中文回退，比较字号、字重、行距、标题基线、文本截断、卡片比例、列数、滚动区域高度、弹层锚点和裁切。
- [ ] 窗口/平台：参考页面自行绘制窗口与任务栏，Flutter 使用原生窗口行为；记录这项平台差异的视觉影响，单独验收原生 Windows/Linux/macOS 控件以及 Web/移动端隐藏规则。
- [ ] 响应式：逐页检查宽桌面、窗口化、窄窗口、低高度、DPI/系统缩放及字体缩放组合。Files 1180px 断点已有源码修复但仍需截图；其余页面断点尚未全量核验。
- [ ] 加载态：桌面 Admin 指标、用户和数据列表已经改为区域骨架占位；仍需按 Home、Movies、Photos、Music、Reader、Files、Settings、Auth 的真实异步区域逐屏比较骨架位置、长宽、扫光与 reduced-motion 状态。
- [ ] 性能：已有启动依赖并行化和首页 provider 订阅缩减，但没有 profile 数据。测冷启动耗时、首帧、滚动掉帧、Photos 大型图库、Movies 卡片加载和 Reader 大章节搜索/分页；每项记录设备、数据量与前后测量，确保视觉不变。

## 4. 交接执行顺序

1. 阅读根级 `AGENTS.md`、`frontend/AGENTS.md` 和[差异报告](UI_DESIGN_DIFF_REPORT.md)；先保全当前本地化文件 diff。
2. 启动原型源码与当前 Flutter 程序，核实进程、URL/路由、工作目录和版本。先完成 P0 基线，尤其确认 Movies 参考版本和 Photos 页头同排结果。
3. 按模块逐页记录截图对照：Home → Movies → Photos → Music → Reader → Files → Settings → Admin → Auth/Setup。每页先主态，再抽屉/菜单/表单/错误/撤销状态。
4. 先按原型结构修复布局和控件，再处理颜色、字体、反馈及动效；每个批次重新取得同参数成对截图。只凭源码注释不能将差异标为通过。
5. 涉及同步或媒体字节处理时，列清 UI 字段 → Flutter DTO → API 请求/响应 → 后端 DTO/持久化/执行效果；部署/数据库影响一并记录。
6. 更新差异报告的“当前判定、证据、未验证项”，保留未完成项；格式化并静态分析改动。未执行的构建、测试、接口运行或截图检查须明确记为未执行。

## 5. 关闭标准

- 8.2 页面/组件矩阵中的每项均有原型与 Flutter 同条件截图，且 8.3 的颜色、几何、字体、图标、状态/动效、响应式和表单参数均有通过证据或明确记录的业务例外。
- 所有可见交互有操作前后截图或录制证据；失败、加载、空状态、禁用、Undo、键盘和拖拽状态不以默认态代替。
- 所有原型字段与实际请求参数有逐项映射；后端无法提供的数据或操作被标为数据契约/业务缺口，不用静态演示值伪装已同步。
- 对无法跨平台复刻的原生窗口/系统任务栏差异明确记录；Web/移动/桌面条件分支符合产品目标。
- 最终报告不再以“源码中有对应控件”推导为完全一致；只有清单全部验收后才可给全量通过结论。
