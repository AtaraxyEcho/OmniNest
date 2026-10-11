import 'package:flutter/material.dart';

/// 移动环境配色的两极性表。
///
/// [MobileEnvPalette.dark] 逐值等于 `MobileEnvColors`（环境基准不变，迁移期两处并存）；
/// [MobileEnvPalette.light] 是同一批角色的纸面同位物，一手数值取自
/// `UI Design/优化浅色模式适配/src/light-theme.css` 的**最终生效层**（1-982 机械反相段
/// 与 986-1064 语义段的后者）。
///
/// 取值规则只有两条，避免再自创换算：
/// ① 样例在最终生效层给了字面量的角色一律照抄（含 α 与色族——样例自己混用两族
///   中性色：语义段 token 是 `rgba(25,32,29,…)`/`#19201d`，机械段字面量是
///   `rgba(26,29,27,…)`/`#1a1d1b`，哪个选择器写的就是哪个，不顺手统一）；
/// ② 样例没点名的角色保留暗档 α，只换墨族到 token 族 `#19201d`。
/// 走②的都是一个角色服务多处调用点的共享档（`line07/09/10`、`white43/70`、
/// `ink40`，兼作分隔线填充与 `outlineVariant`），把某一个选择器的字面量套到
/// 全部调用点上属于新的自作主张。
/// 逐角色机器核对脚本见 docs/2026-10-09/008 §二（58 个可 1:1 定位的角色零差异）。
///
/// 角色约定（浅色分支的硬约束）：
/// - 填充与其上的文字必须成对使用（`buttonInk`/`onButtonInk`、`selectionBar`/`onSelectionBar`），
///   只翻其中一侧会得到"深底深字"；
/// - [accent] 只做填充，永远配 [onAccent] 深字；文字/图标/发丝线/细进度条用 [accentInk]，
///   因为薄荷绿在纸面上只有 1.34:1。
@immutable
class MobileEnvPalette extends ThemeExtension<MobileEnvPalette> {
  const MobileEnvPalette({
    required this.brightness,
    required this.stage,
    required this.stageSolid,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.groupLabelInk,
    required this.eyebrowInk,
    required this.ink40,
    required this.white52,
    required this.white46,
    required this.white43,
    required this.white70,
    required this.white78,
    required this.line13,
    required this.line10,
    required this.line07,
    required this.line09,
    required this.line15,
    required this.line25,
    required this.line12,
    required this.accent,
    required this.accentInk,
    required this.onAccent,
    required this.onAccentDeep,
    required this.segmentBg,
    required this.actionFill,
    required this.actionFillInk,
    required this.segmentActiveBg,
    required this.appearanceOptionBg,
    required this.appearanceOptionBorder,
    required this.appearanceOptionInk,
    required this.microLabelInk,
    required this.settingIconBg,
    required this.segmentActiveInk,
    required this.segmentBorder,
    required this.switchOn,
    required this.switchOff,
    required this.switchKnobOff,
    required this.switchKnobOn,
    required this.iconButtonGlass,
    required this.posterPlayBg,
    required this.posterPlayFg,
    required this.searchOverlayBg,
    required this.modalScrim,
    required this.surfaceGlass,
    required this.surfaceRaised,
    required this.surfaceTint,
    required this.elevShadow,
    required this.navGlass,
    required this.miniPlayer,
    required this.sheetSolid,
    required this.sheetGlow,
    required this.focusGradientStart,
    required this.focusGradientEnd,
    required this.sceneVeilTop,
    required this.sceneVeilBottom,
    required this.heroGlow,
    required this.featureHeroStart,
    required this.featureHeroEnd,
    required this.featureHeroLine,
    required this.featureHeroIconBg,
    required this.metricCell,
    required this.cardGlow,
    required this.pillGlow,
    required this.artworkGlow,
    required this.avatarBg,
    required this.avatarFg,
    required this.bookMiniBg,
    required this.bookMiniFg,
    required this.bookMiniSpine,
    required this.folderGlyph,
    required this.folderGlyphBg,
    required this.storageProgressFill,
    required this.storageCloud,
    required this.storageCloudBg,
    required this.readerCoverBg,
    required this.readerCoverSpine,
    required this.readerCoverFg,
    required this.selectionBar,
    required this.onSelectionBar,
    required this.buttonInk,
    required this.onButtonInk,
  });

  /// 该极性的明暗档，供第三方编辑器等需要 ThemeData.brightness 的场合使用。
  final Brightness brightness;
  final Color stage;

  /// 无壁纸时的实底舞台：暗态比 stage 提亮一档，避免玻璃卡片叠纯黑整体过暗；
  /// 浅态即纸面画布。必须由极性表给出，取根主题的容器色会在"暗极性 + 浅根主题"
  /// 下把内容底铺成白。
  final Color stageSolid;
  final Color ink;

  /// 次级说明文字。浅态取 `--muted` 的色相，但 α 从样例的 .62 提到 .639：
  /// 样例那一档压在浅纸上只有 4.34-4.47，六张承载面全都不过 AA，而 α 提 2 个
  /// 点在视觉上不可辨。暗态取主文字 75%（实测 ≥9.2）。
  /// 见 `mobile_env_palette_test` 的 α 偏离账目——事实表闸门只判 RGB 通道，
  /// 这类偏离不会被它抓到。
  final Color inkMuted;

  /// 眉标与小号标签文字。浅态按样例 `.eyebrow` 的字面量取 rgba(26,29,27,.72)，
  /// 比 [inkMuted] 更实一档；暗态仍是主文字里更淡的一档。
  final Color inkFaint;

  /// 分组眉标（样例 `.notif-group` / `.notif-group-label`）专用淡墨：
  /// 样例是暗 `rgba(246,246,242,.43)`、浅 `rgba(26,29,27,.58)`，实测两极性都只有
  /// 4.0 左右，压在实底面板上更低。α 各提到暗 .486 / 浅 .623 才过 AA 4.5，
  /// 幅度分别是 5.6 与 4.3 个百分点。同 [inkMuted]，属刻意的 α 偏离。
  final Color groupLabelInk;

  /// 眉标（样例 `.eyebrow`）专用墨：暗态是主墨 58% 的中性淡墨，浅态被第 4 层
  /// 整体翻成深青 `--accent-ink`。首页子树另取照片上的近白 82%。
  final Color eyebrowInk;
  final Color ink40;
  final Color white52;
  final Color white46;
  final Color white43;
  final Color white70;
  final Color white78;
  final Color line13;
  final Color line10;
  final Color line07;
  final Color line09;
  final Color line15;

  /// 强中性叠加：把手、加号舱描边这类需要明显可见的 25% 档。
  final Color line25;
  final Color line12;
  final Color accent;

  /// 强调色的"墨"用法：暗态仍是酸绿，浅态换成深青（`AppThemePalette.light.primary`）。
  final Color accentInk;
  final Color onAccent;
  final Color onAccentDeep;
  final Color segmentBg;

  /// 主行动钮的填充与字色。样例的 CTA 族（`.login-enter`、`.accent-square-btn`、
  /// `.empty-action button`）两态都是强调色填充 + 深字，[buttonInk] 那一族
  /// （横幅里的实心钮）才按极性翻转填充与标签。
  final Color actionFill;
  final Color actionFillInk;

  /// 分段控件选中滑块：两态都用强调色填充，浅态即薄荷底深字。
  final Color segmentActiveBg;

  /// 设置页选项组（样例 `.appearance-options`）的容器底与描边。
  ///
  /// 与底部分段导航 [.segmented] 是样例里两个不同组件：分段是贴合内容的胶囊、
  /// 选项组是等分三列的网格，浅态两者底色恰好同值，暗态一个是深色实底、
  /// 一个是白 5% 的浅叠，不能共用一档。
  final Color appearanceOptionBg;
  final Color appearanceOptionBorder;

  /// 选项组未选中项的字色（样例 `.appearance-options button` 取 `--muted`
  /// 与浅态 `--text-secondary`，都比 [inkMuted] 更实一档）。
  final Color appearanceOptionInk;

  /// 微型标签档字色（7-10px 的指标格标签/明细、逐时时刻、预报行天况）。
  ///
  /// 样例这些格子写的是 `--muted`（浅态 rgba(23,35,30,.62)，实测压在指标格上
  /// 只有 4.68），在 7-8px 上整层发灰——设备截图上除了大数字几乎看不清。
  /// 这里改用样例**自己**的标签档 `--text-secondary`（浅态 .72，实测 6.06）：
  /// 浅层第 4 层已经把 `.poster small`/`.file-list small` 那一族小型标签
  /// 整体换成这个 token，天气抽屉只是没被列进那份清单，所以这是把样例的
  /// 既有意图补全，不是另造一档。暗态维持 `--muted`（.749，本来就够）。
  final Color microLabelInk;

  /// 设置行左侧图标舱（样例 `.notif-icon`）：暗态强调色 8% 的淡底，浅态是
  /// 薄荷 34%，不是把暗态的透明度套到浅态字色上。
  final Color settingIconBg;

  /// 分段控件选中段的字色：暗态是压在酸绿上的深墨 `#151c13`，浅态换成
  /// 压在近白胶囊上的深绿 `#17372c`，与 [onAccentDeep] 那一族不是同一档。
  final Color segmentActiveInk;

  /// 分段控件容器描边（样例 `.segmented` 的 `border`）。
  final Color segmentBorder;

  /// 开关轨道的开启色与旋钮色。浅态轨道换成薄荷、旋钮保持白色加一层淡投影，
  /// 与样例 `.env-switch.on` 与语义段的 `#fff` 一致。
  final Color switchOn;

  /// 开关轨道的关闭档（样例 `.env-switch` 底：暗态白 15%、浅态 rgba(26,29,27,.18)）。
  final Color switchOff;
  final Color switchKnobOff;
  final Color switchKnobOn;
  final Color iconButtonGlass;
  final Color posterPlayBg;
  final Color posterPlayFg;
  final Color searchOverlayBg;

  /// 模态遮罩：暗态是 45% 黑，浅态是 32% 的深绿黑——遮罩自身仍带一层模糊，
  /// 面板只压暗背景而不把整屏涂黑。
  final Color modalScrim;
  final Color surfaceGlass;
  final Color surfaceRaised;

  /// 低透明表面着色：列表行底、格内图标片。
  final Color surfaceTint;

  /// 抬升投影色。浅态只留一档淡影：玻璃面自身半透明，暗态那档投影透上来
  /// 会把纸面卡片染成灰板。
  final Color elevShadow;

  /// 首页续接卡的投影（样例 `.focus-feature` 暗态黑 20%、浅态 `rgba(26,29,27,.07)`）。
  final Color cardGlow;

  /// 底栏选中胶囊的投影（样例 `.segmented button.active` 暗态黑 18%、浅态 6%）。
  final Color pillGlow;

  /// 封面/相册类浮起卡的投影（样例 `.album > span` 暗态黑 22%、浅态 `rgba(26,29,27,.08)`）。
  final Color artworkGlow;
  final Color navGlass;

  /// 迷你播放条底：与底栏同为玻璃面（样例两处的 `--surface` 同一档）。
  final Color miniPlayer;

  /// 贴底抽屉与覆盖层的底（样例 `--surface` 在浅态是半透明白，暗态是深色实底）。
  final Color sheetSolid;

  /// 贴底抽屉往上抛的那团阴影：暗态是 54% 黑，浅态换成极淡的绿相阴影，
  /// 否则纸面上方会挂一道黑灰。
  final Color sheetGlow;
  final Color focusGradientStart;
  final Color focusGradientEnd;

  /// 天气抽屉场景带的一层压色：暗态是 5% 到实底的渐变，浅态两端同值即平涂
  /// rgba(15,33,25,.14)（取样例第 4 层，不再是洗白渐变）。
  final Color sceneVeilTop;
  final Color sceneVeilBottom;

  /// 首页大时钟与眉标的一层光晕：暗态把字从亮照片里拉出来，浅态换成白色光晕，
  /// 否则深墨字压在照片上没有承载面。样例 `.time-block` 的 text-shadow。
  final Color heroGlow;

  /// 次级分区页身份块（样例 `.feature-hero`）：115° 渐变两端、描边与图标舱底。
  final Color featureHeroStart;
  final Color featureHeroEnd;
  final Color featureHeroLine;
  final Color featureHeroIconBg;

  /// 天气指标格单元格的表面（样例 `.weather-metrics>div`，比抽屉底更实一档）。
  final Color metricCell;
  final Color avatarBg;
  final Color avatarFg;
  final Color bookMiniBg;
  final Color bookMiniFg;
  final Color bookMiniSpine;
  final Color folderGlyph;
  final Color folderGlyphBg;
  final Color storageProgressFill;
  final Color storageCloud;
  final Color storageCloudBg;
  final Color readerCoverBg;
  final Color readerCoverSpine;
  final Color readerCoverFg;
  final Color selectionBar;
  final Color onSelectionBar;
  final Color buttonInk;
  final Color onButtonInk;

  /// 与 `MobileEnvColors` 逐值相同的环境基准。
  static const MobileEnvPalette dark = MobileEnvPalette(
    brightness: Brightness.dark,
    stage: Color(0xFF0B1110),
    stageSolid: Color(0xFF171A18),
    ink: Color(0xFFF6F6F2),
    inkMuted: Color(0xBFF6F6F2),
    inkFaint: Color(0x94F6F6F2),
    groupLabelInk: Color(0x7CF6F6F2),
    eyebrowInk: Color(0x94F6F6F2),
    ink40: Color(0x66F6F6F2),
    white52: Color(0x85FFFFFF),
    white46: Color(0x75FFFFFF),
    white43: Color(0x6EFFFFFF),
    white70: Color(0xB3FFFFFF),
    white78: Color(0xC7FFFFFF),
    line13: Color(0x21FFFFFF),
    line10: Color(0x1AFFFFFF),
    line07: Color(0x12FFFFFF),
    line09: Color(0x17FFFFFF),
    line15: Color(0x26FFFFFF),
    line25: Color(0x40FFFFFF),
    line12: Color(0x1FFFFFFF),
    accent: Color(0xFFD5F17D),
    accentInk: Color(0xFFD5F17D),
    onAccent: Color(0xFF172014),
    onAccentDeep: Color(0xFF151C13),
    segmentBg: Color(0xB8141C1A),
    actionFill: Color(0xFFD5F17D),
    actionFillInk: Color(0xFF172014),
    segmentActiveBg: Color(0xFFD5F17D),
    appearanceOptionBg: Color(0x0DFFFFFF),
    appearanceOptionBorder: Color(0x21FFFFFF),
    appearanceOptionInk: Color(0x9EF6F6F2),
    microLabelInk: Color(0xBFF6F6F2),
    settingIconBg: Color(0x14D5F17D),
    segmentActiveInk: Color(0xFF151C13),
    segmentBorder: Color(0x17FFFFFF),
    switchOn: Color(0xFFD5F17D),
    // 暗值就是改动前那句 line15。
    switchOff: Color(0x26FFFFFF),
    switchKnobOff: Color(0xFFF6F6F2),
    switchKnobOn: Color(0xFF151C13),
    iconButtonGlass: Color(0x52121817),
    posterPlayBg: Color(0xE6F9F9F4),
    posterPlayFg: Color(0xFF101513),
    searchOverlayBg: Color(0xF00A0F0E),
    modalScrim: Color(0x73000000),
    surfaceGlass: Color(0xB8121918),
    surfaceRaised: Color(0x8F111816),
    surfaceTint: Color(0x0BFFFFFF),
    elevShadow: Color(0x59000000),
    // 暗值就是改动前那句 Colors.black.withValues(alpha: 0.2 / 0.18)。
    cardGlow: Color(0x33000000),
    pillGlow: Color(0x2E000000),
    // 暗值就是改动前那句 Color(0x38444444)。
    artworkGlow: Color(0x38444444),
    navGlass: Color(0xC70E1413),
    miniPlayer: Color(0xE8121817),
    sheetSolid: Color(0xFF171E1C),
    sheetGlow: Color(0x8A000000),
    focusGradientStart: Color(0xC2101615),
    focusGradientEnd: Color(0x7D1B2421),
    sceneVeilTop: Color(0x0D080F0E),
    sceneVeilBottom: Color(0xFF17201E),
    // 暗值就是改动前那句字面量：Colors.black54 与 sheetSolid 的 95% 叠加。
    heroGlow: Color(0x87000000),
    featureHeroStart: Color(0x1AD5F17D),
    featureHeroEnd: Color(0x09FFFFFF),
    featureHeroLine: Color(0x29D5F17D),
    featureHeroIconBg: Color(0x17D5F17D),
    metricCell: Color(0xF2171E1C),
    avatarBg: Color(0xFFD6C0A9),
    avatarFg: Color(0xFF2C211A),
    bookMiniBg: Color(0xFFD8CFB5),
    bookMiniFg: Color(0xFF27261F),
    bookMiniSpine: Color(0xFF948F7D),
    folderGlyph: Color(0xFF91BAF2),
    folderGlyphBg: Color(0x2B4C84D2),
    storageProgressFill: Color(0xFF8FB6EC),
    storageCloud: Color(0xFFB9D2FF),
    storageCloudBg: Color(0x295D8EE0),
    readerCoverBg: Color(0xFFD5CCAD),
    readerCoverSpine: Color(0xFF827D6C),
    readerCoverFg: Color(0xFF2C2C26),
    selectionBar: Color(0xFFD9EF91),
    onSelectionBar: Color(0xFF162014),
    buttonInk: Color(0xFFF6F6F2),
    onButtonInk: Color(0xFF141A18),
  );

  /// 浅实例：一手数值见类注释的取值规则。中性族是**带绿相**的墨与线
  /// （`25,32,29` 系），不是纯灰；强调族按语义段换成薄荷填充 + 深青墨。
  static const MobileEnvPalette light = MobileEnvPalette(
    brightness: Brightness.light,
    stage: Color(0xFFF4F6F3),
    stageSolid: Color(0xFFE9EEE7),
    ink: Color(0xFF17231E),
    inkMuted: Color(0xA317231E),
    // 样例浅极性只给 `--ink` 与 `--muted` 两档 token，但眉标 `.eyebrow` 在
    // 机械段写了字面量 rgba(26,29,27,.72)，语义段没有覆盖它，所以照抄。
    inkFaint: Color(0xB817231E),
    groupLabelInk: Color(0x9F1A1D1B),
    eyebrowInk: Color(0xFF225F4E),
    ink40: Color(0x6617231E),
    // `.weather-line i`（分隔圆点）在浅态是 rgba(26,29,27,.70)。
    white52: Color(0xB317231E),
    // `.bottom-nav button` 未选中态在浅态是 rgba(26,29,27,.61)。
    white46: Color(0x9C17231E),
    white43: Color(0x6E17231E),
    white70: Color(0xB317231E),
    // 样例 `.weather-line` 在浅态是 rgba(26,29,27,.88)，比暗态的白 78% 更实。
    white78: Color(0xC217231E),
    line13: Color(0x1F243E33),
    line10: Color(0x1A243E33),
    line07: Color(0x12243E33),
    line09: Color(0x17243E33),
    // 卡片描边在语义段被统一改写成 var(--line)，与 line13 同值；暗态仍按原 15%。
    line15: Color(0x21243E33),
    // `.sheet-handle` 的字面量是 rgba(26,29,27,.31)。
    line25: Color(0x4F243E33),
    // `.bottom-nav`、各 sheet 的上描边在语义段统一改写成 --line（13%），
    // 与 line13 同值；暗态仍按各自原字面量（12%）。
    line12: Color(0x21243E33),
    accent: Color(0xFFDCEBA8),
    accentInk: Color(0xFF225F4E),
    // `.focus-play`、`.login-enter` 的标签字面量是 #1a1d1b。
    onAccent: Color(0xFF17231E),
    onAccentDeep: Color(0xFF17231E),
    segmentBg: Color(0x121F3E32),
    actionFill: Color(0xFF1E5949),
    actionFillInk: Color(0xFFF8FAEF),
    segmentActiveBg: Color(0xE6FFFFFC),
    appearanceOptionBg: Color(0x121F3E32),
    appearanceOptionBorder: Color(0x2B243E33),
    appearanceOptionInk: Color(0xB817231E),
    microLabelInk: Color(0xB817231E),
    settingIconBg: Color(0x57DAEAA6),
    segmentActiveInk: Color(0xFF17372C),
    segmentBorder: Color(0x1228463A),
    switchOn: Color(0xFF2A6957),
    switchOff: Color(0x2E243E33),
    switchKnobOff: Color(0xFFFFFFFF),
    switchKnobOn: Color(0xFFFFFFFF),
    iconButtonGlass: Color(0x94FAFCF6),
    posterPlayBg: Color(0xFFFFFFFF),
    posterPlayFg: Color(0xFF17231E),
    searchOverlayBg: Color(0xFFEDF1E9),
    modalScrim: Color(0x47192821),
    // --surface 在语义段是 rgba(255,255,255,.82)：底栏、迷你播放条、分段与各
    // sheet 共用同一档玻璃面，模糊层保留（样例仍写着 backdrop-filter）。
    surfaceGlass: Color(0xD1FAFCF6),
    surfaceRaised: Color(0x8FF8FAF4),
    surfaceTint: Color(0x0D243E33),
    // 三档投影在样例浅态都写 rgba(26,29,27,…)：底栏 12%、卡片 7%、胶囊 6%。
    elevShadow: Color(0x1F243E33),
    cardGlow: Color(0x12243E33),
    pillGlow: Color(0x0F243E33),
    artworkGlow: Color(0x141A1D1B),
    navGlass: Color(0xFFF2F5EE),
    miniPlayer: Color(0xFFF2F5EE),
    sheetSolid: Color(0xFFF1F4ED),
    // 样例 `.weather-sheet` 浅态上抛阴影是 rgba(26,29,27,.16)。
    sheetGlow: Color(0x1F2D4639),
    focusGradientStart: Color(0xEBECEFE6),
    focusGradientEnd: Color(0x7DECEFE6),
    sceneVeilTop: Color(0x240F2119),
    sceneVeilBottom: Color(0x240F2119),
    heroGlow: Color(0x75FFFFFF),
    featureHeroStart: Color(0x1AD5F17D),
    featureHeroEnd: Color(0x0A1A1D1B),
    // 浅态描边样例写成 color-mix(#0b6b61 16%, transparent)：取混合前的深青本色，
    // 透明度按 16% 落进 alpha 通道。
    featureHeroLine: Color(0x290B6B61),
    featureHeroIconBg: Color(0x17D5F17D),
    metricCell: Color(0xFFEEF2EB),
    avatarBg: Color(0x94FAFCF6),
    avatarFg: Color(0xFF17231E),
    bookMiniBg: Color(0xFFD8CFB5),
    bookMiniFg: Color(0xFF17231E),
    bookMiniSpine: Color(0xFF948F7D),
    folderGlyph: Color(0xFF91BAF2),
    folderGlyphBg: Color(0x2B4C84D2),
    storageProgressFill: Color(0xFF8FB6EC),
    storageCloud: Color(0xFFB9D2FF),
    storageCloudBg: Color(0x295D8EE0),
    readerCoverBg: Color(0xFFD5CCAD),
    readerCoverSpine: Color(0xFF827D6C),
    readerCoverFg: Color(0xFF17231E),
    // 多选条按样例保持浅柠实底（`.selection-bar` 在语义段未被覆盖）。
    selectionBar: Color(0xFFDCE9AE),
    onSelectionBar: Color(0xFF17372C),
    // 浅态的近白实底钮翻成深墨底近白字（`.library-feature-copy button`）。
    buttonInk: Color(0xFFDCE9AE),
    onButtonInk: Color(0xFF17372C),
  );

  /// 浅态摄影档用：只换首页子树需要偏离画布档的几项，其余沿用本实例。
  MobileEnvPalette withOverrides({
    Brightness? brightness,
    Color? stage,
    Color? stageSolid,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? groupLabelInk,
    Color? eyebrowInk,
    Color? ink40,
    Color? white52,
    Color? white46,
    Color? white43,
    Color? white70,
    Color? white78,
    Color? line13,
    Color? line10,
    Color? line07,
    Color? line09,
    Color? line15,
    Color? line25,
    Color? line12,
    Color? accent,
    Color? accentInk,
    Color? onAccent,
    Color? onAccentDeep,
    Color? segmentBg,
    Color? actionFill,
    Color? actionFillInk,
    Color? segmentActiveBg,
    Color? appearanceOptionBg,
    Color? appearanceOptionBorder,
    Color? appearanceOptionInk,
    Color? microLabelInk,
    Color? settingIconBg,
    Color? segmentActiveInk,
    Color? segmentBorder,
    Color? switchOn,
    Color? switchOff,
    Color? switchKnobOff,
    Color? switchKnobOn,
    Color? iconButtonGlass,
    Color? posterPlayBg,
    Color? posterPlayFg,
    Color? searchOverlayBg,
    Color? modalScrim,
    Color? surfaceGlass,
    Color? surfaceRaised,
    Color? surfaceTint,
    Color? elevShadow,
    Color? cardGlow,
    Color? pillGlow,
    Color? artworkGlow,
    Color? navGlass,
    Color? miniPlayer,
    Color? sheetSolid,
    Color? sheetGlow,
    Color? focusGradientStart,
    Color? focusGradientEnd,
    Color? sceneVeilTop,
    Color? sceneVeilBottom,
    Color? heroGlow,
    Color? featureHeroStart,
    Color? featureHeroEnd,
    Color? featureHeroLine,
    Color? featureHeroIconBg,
    Color? metricCell,
    Color? avatarBg,
    Color? avatarFg,
    Color? bookMiniBg,
    Color? bookMiniFg,
    Color? bookMiniSpine,
    Color? folderGlyph,
    Color? folderGlyphBg,
    Color? storageProgressFill,
    Color? storageCloud,
    Color? storageCloudBg,
    Color? readerCoverBg,
    Color? readerCoverSpine,
    Color? readerCoverFg,
    Color? selectionBar,
    Color? onSelectionBar,
    Color? buttonInk,
    Color? onButtonInk,
  }) {
    return MobileEnvPalette(
      brightness: brightness ?? this.brightness,
      stage: stage ?? this.stage,
      stageSolid: stageSolid ?? this.stageSolid,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      groupLabelInk: groupLabelInk ?? this.groupLabelInk,
      eyebrowInk: eyebrowInk ?? this.eyebrowInk,
      ink40: ink40 ?? this.ink40,
      white52: white52 ?? this.white52,
      white46: white46 ?? this.white46,
      white43: white43 ?? this.white43,
      white70: white70 ?? this.white70,
      white78: white78 ?? this.white78,
      line13: line13 ?? this.line13,
      line10: line10 ?? this.line10,
      line07: line07 ?? this.line07,
      line09: line09 ?? this.line09,
      line15: line15 ?? this.line15,
      line25: line25 ?? this.line25,
      line12: line12 ?? this.line12,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      onAccent: onAccent ?? this.onAccent,
      onAccentDeep: onAccentDeep ?? this.onAccentDeep,
      segmentBg: segmentBg ?? this.segmentBg,
      actionFill: actionFill ?? this.actionFill,
      actionFillInk: actionFillInk ?? this.actionFillInk,
      segmentActiveBg: segmentActiveBg ?? this.segmentActiveBg,
      appearanceOptionBg: appearanceOptionBg ?? this.appearanceOptionBg,
      appearanceOptionBorder:
          appearanceOptionBorder ?? this.appearanceOptionBorder,
      appearanceOptionInk: appearanceOptionInk ?? this.appearanceOptionInk,
      microLabelInk: microLabelInk ?? this.microLabelInk,
      settingIconBg: settingIconBg ?? this.settingIconBg,
      segmentActiveInk: segmentActiveInk ?? this.segmentActiveInk,
      segmentBorder: segmentBorder ?? this.segmentBorder,
      switchOn: switchOn ?? this.switchOn,
      switchOff: switchOff ?? this.switchOff,
      switchKnobOff: switchKnobOff ?? this.switchKnobOff,
      switchKnobOn: switchKnobOn ?? this.switchKnobOn,
      iconButtonGlass: iconButtonGlass ?? this.iconButtonGlass,
      posterPlayBg: posterPlayBg ?? this.posterPlayBg,
      posterPlayFg: posterPlayFg ?? this.posterPlayFg,
      searchOverlayBg: searchOverlayBg ?? this.searchOverlayBg,
      modalScrim: modalScrim ?? this.modalScrim,
      surfaceGlass: surfaceGlass ?? this.surfaceGlass,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceTint: surfaceTint ?? this.surfaceTint,
      elevShadow: elevShadow ?? this.elevShadow,
      cardGlow: cardGlow ?? this.cardGlow,
      pillGlow: pillGlow ?? this.pillGlow,
      artworkGlow: artworkGlow ?? this.artworkGlow,
      navGlass: navGlass ?? this.navGlass,
      miniPlayer: miniPlayer ?? this.miniPlayer,
      sheetSolid: sheetSolid ?? this.sheetSolid,
      sheetGlow: sheetGlow ?? this.sheetGlow,
      focusGradientStart: focusGradientStart ?? this.focusGradientStart,
      focusGradientEnd: focusGradientEnd ?? this.focusGradientEnd,
      sceneVeilTop: sceneVeilTop ?? this.sceneVeilTop,
      sceneVeilBottom: sceneVeilBottom ?? this.sceneVeilBottom,
      heroGlow: heroGlow ?? this.heroGlow,
      featureHeroStart: featureHeroStart ?? this.featureHeroStart,
      featureHeroEnd: featureHeroEnd ?? this.featureHeroEnd,
      featureHeroLine: featureHeroLine ?? this.featureHeroLine,
      featureHeroIconBg: featureHeroIconBg ?? this.featureHeroIconBg,
      metricCell: metricCell ?? this.metricCell,
      avatarBg: avatarBg ?? this.avatarBg,
      avatarFg: avatarFg ?? this.avatarFg,
      bookMiniBg: bookMiniBg ?? this.bookMiniBg,
      bookMiniFg: bookMiniFg ?? this.bookMiniFg,
      bookMiniSpine: bookMiniSpine ?? this.bookMiniSpine,
      folderGlyph: folderGlyph ?? this.folderGlyph,
      folderGlyphBg: folderGlyphBg ?? this.folderGlyphBg,
      storageProgressFill: storageProgressFill ?? this.storageProgressFill,
      storageCloud: storageCloud ?? this.storageCloud,
      storageCloudBg: storageCloudBg ?? this.storageCloudBg,
      readerCoverBg: readerCoverBg ?? this.readerCoverBg,
      readerCoverSpine: readerCoverSpine ?? this.readerCoverSpine,
      readerCoverFg: readerCoverFg ?? this.readerCoverFg,
      selectionBar: selectionBar ?? this.selectionBar,
      onSelectionBar: onSelectionBar ?? this.onSelectionBar,
      buttonInk: buttonInk ?? this.buttonInk,
      onButtonInk: onButtonInk ?? this.onButtonInk,
    );
  }

  /// 浅态摄影档：样例把首页留在摄影面（`.home-space` 作用域），
  /// 其余空间才是纸面画布。值全部取样例第 4 层对 `.home-space` 的最终声明。
  ///
  /// 卡片本体与描边也必须在这张表里覆盖：样例的首页卡片在两极性都是
  /// `rgba(13,28,22,.74)` 的深玻璃，只覆盖 `surfaceGlass` 会漏掉读
  /// `surfaceRaised` / `focusGradient*` 的文件夹卡与焦点卡，浅态就塌成近白。
  static final MobileEnvPalette lightPhotographic = light.withOverrides(
    ink: Color(0xFFF4F7F1),
    inkMuted: Color(0x9EF4F7F1),
    inkFaint: Color(0x9EF4F7F1),
    eyebrowInk: Color(0xD1F7F9F3),
    white70: Color(0xD1F7F9F3),
    white78: Color(0xD1F7F9F3),
    white52: Color(0x9EF4F7F1),
    white46: Color(0x8FF4F7F1),
    line13: Color(0x2EFFFFFF),
    line15: Color(0x1FFFFFFF),
    // 卡片描边：样例 `.home-space .recent-folder` 与 `.quick-line button`
    // 都翻成白 12%，浅态不再用画布档的墨色描边。
    line10: Color(0x1FFFFFFF),
    line09: Color(0x1FFFFFFF),
    iconButtonGlass: Color(0x470D1B15),
    surfaceGlass: Color(0xBD0D1C16),
    // 首页卡片族：文件夹卡读 surfaceRaised，焦点卡读渐变；样例第 4 层
    // 把两者都压成同一块深玻璃，因此渐变两端同值。
    surfaceRaised: Color(0xBD0D1C16),
    focusGradientStart: Color(0xBD0D1C16),
    focusGradientEnd: Color(0xBD0D1C16),
    // 中性叠加没有对应的样例 `.home-space` 选择器：卡片底下的占位板
    // 在深玻璃上只能走暗档的白 4%，按画布档的墨 5% 会整块看不见。
    surfaceTint: Color(0x0BFFFFFF),
    cardGlow: Color(0x24050D0A),
    actionFill: Color(0xFFDCE9AE),
    actionFillInk: Color(0xFF18382D),
    heroGlow: Color(0x57050D0A),
  );

  /// 按极性与「是否摄影面」取表。摄影面只在浅态需要偏离，暗态两极同表。
  static MobileEnvPalette resolveFor({
    required Brightness brightness,
    bool photographic = false,
  }) {
    if (brightness != Brightness.light) {
      return dark;
    }
    return photographic ? lightPhotographic : light;
  }

  static MobileEnvPalette resolve(Brightness brightness) {
    return brightness == Brightness.light ? light : dark;
  }

  /// 只认宿主显式注册的实例；未注册一律取暗基准。
  ///
  /// 不按亮度推断：桌面端与媒体托管页在浅色根主题下同样会读到 light，
  /// 而它们的字面量尚未接入极性表，翻转会留下浅底暗字的混合态。
  static MobileEnvPalette of(BuildContext context) {
    return Theme.of(context).extension<MobileEnvPalette>() ?? dark;
  }

  /// 令牌表按整体切换，不做逐色插值：亮度过渡期取任一档都不会出现"深底深字"的中间态。
  @override
  MobileEnvPalette copyWith() => this;

  @override
  MobileEnvPalette lerp(covariant MobileEnvPalette? other, double t) {
    if (other == null) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

extension MobileEnvPaletteContext on BuildContext {
  /// 当前极性的环境配色表。
  MobileEnvPalette get env => MobileEnvPalette.of(this);
}

/// 注册极性表到主题，并把模态遮罩接到同一档。
///
/// `ThemeData.copyWith(extensions:)` 整体替换扩展集，因此必须带上既有扩展，
/// 否则模块调色板（Photos/Files/Reader 等）会被抹掉。
///
/// 遮罩必须在这里一起接：`showModalBottomSheet` 未显式传 `barrierColor` 时读的是
/// `bottomSheetTheme.modalBarrierColor`，再退到 `Colors.black54`（54% 纯黑）。
/// 全仓 32 处调用里有 29 处没传参，浅态因此比样例的 `rgba(19,24,21,.32)` 重一档半，
/// 且丢掉墨绿色相。桌面端不注册极性表，保持 Flutter 默认。
extension MobileEnvPaletteTheme on ThemeData {
  ThemeData withEnvPalette(MobileEnvPalette palette) {
    return copyWith(
      extensions: [...extensions.values, palette],
      bottomSheetTheme: bottomSheetTheme.copyWith(
        modalBarrierColor: palette.modalScrim,
      ),
    );
  }
}
