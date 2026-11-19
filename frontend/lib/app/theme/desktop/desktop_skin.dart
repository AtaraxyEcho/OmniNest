import 'package:flutter/material.dart';

import 'package:omninest/app/theme/desktop/desktop_palette.dart';

/// 桌面壳层与桌面页面消费的材质令牌。
///
/// 字段逐一对应样例 `desktop.css` 的 CSS 变量：`--bg/--panel/--raise*/
/// --line*/--text*/--accent/--warm/--veil`。以 ThemeExtension 承载，
/// 桌面之外的形态不注入本扩展，`of` 取不到时回落暗色基准，
/// 因此单独 pump 桌面组件的测试无需搭壳。
@immutable
class DesktopSkin extends ThemeExtension<DesktopSkin> {
  const DesktopSkin({
    required this.isDark,
    required this.bg,
    required this.bg2,
    required this.panel,
    required this.panelSolid,
    required this.pop,
    required this.raise,
    required this.raise2,
    required this.raise3,
    required this.line,
    required this.line2,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentInk,
    required this.warm,
    required this.veil,
    required this.ambientOpacity,
    required this.shadow,
  });

  factory DesktopSkin.resolve({
    required bool isDark,
    required DesktopAccent accent,
  }) {
    final tint = accent.resolve(isDark: isDark);
    final raiseBase =
        isDark ? DesktopPalette.raiseBaseDark : DesktopPalette.raiseBaseLight;
    return DesktopSkin(
      isDark: isDark,
      bg: isDark ? DesktopPalette.bgDark : DesktopPalette.bgLight,
      bg2: isDark ? DesktopPalette.bg2Dark : DesktopPalette.bg2Light,
      panel: (isDark
              ? DesktopPalette.panelSolidDark
              : DesktopPalette.panelBaseLight)
          .withValues(alpha: 0.66),
      panelSolid:
          isDark
              ? DesktopPalette.panelSolidDark
              : DesktopPalette.panelSolidLight,
      pop: (isDark ? DesktopPalette.popBaseDark : DesktopPalette.popBaseLight)
          .withValues(alpha: isDark ? 0.90 : 0.92),
      raise: raiseBase.withValues(alpha: isDark ? 0.040 : 0.045),
      raise2: raiseBase.withValues(alpha: isDark ? 0.075 : 0.080),
      raise3: raiseBase.withValues(alpha: isDark ? 0.120 : 0.130),
      line: raiseBase.withValues(alpha: isDark ? 0.075 : 0.090),
      line2: raiseBase.withValues(alpha: isDark ? 0.150 : 0.180),
      text: isDark ? DesktopPalette.textDark : DesktopPalette.textLight,
      text2: isDark ? DesktopPalette.text2Dark : DesktopPalette.text2Light,
      text3: isDark ? DesktopPalette.text3Dark : DesktopPalette.text3Light,
      accent: tint,
      accentInk:
          isDark ? DesktopPalette.accentInkDark : DesktopPalette.accentInkLight,
      warm: isDark ? DesktopPalette.warmDark : DesktopPalette.warmLight,
      // `--veil` 自身带 .72/.8 alpha；`.amb-veil` 再以 .86/.7 作为整层
      // opacity 合成，两个值不能互相替代。
      veil: (isDark ? DesktopPalette.veilDark : DesktopPalette.veilLight)
          .withValues(alpha: isDark ? 0.72 : 0.80),
      ambientOpacity: isDark ? 1 : 0.55,
      shadow: [
        BoxShadow(
          color:
              isDark ? DesktopPalette.shadowDark : DesktopPalette.shadowLight,
          blurRadius: 60,
          offset: const Offset(0, 24),
          spreadRadius: isDark ? -18 : -20,
        ),
        BoxShadow(
          color:
              isDark
                  ? DesktopPalette.shadowSoftDark
                  : DesktopPalette.shadowSoftLight,
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  final bool isDark;
  final Color bg;
  final Color bg2;
  final Color panel;
  final Color panelSolid;
  final Color pop;
  final Color raise;
  final Color raise2;
  final Color raise3;
  final Color line;
  final Color line2;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accentInk;
  final Color warm;
  final Color veil;
  final double ambientOpacity;
  final List<BoxShadow> shadow;

  /// 样例反复出现的 `color-mix(in oklab, var(--accent) N%, transparent)`。
  Color accentWash(double fraction) => accent.withValues(alpha: fraction);

  /// 语义色在深色/浅色下的可读档：浅底需要压深，直接沿用暗色值会发白。
  Color get ok =>
      isDark
          ? DesktopPalette.ok
          : Color.lerp(DesktopPalette.okSeed, DesktopPalette.textLight, 0.35)!;
  Color get warn =>
      isDark
          ? DesktopPalette.warn
          : Color.lerp(DesktopPalette.warn, DesktopPalette.textLight, 0.32)!;
  Color get bad =>
      isDark
          ? DesktopPalette.bad
          : Color.lerp(DesktopPalette.badSeed, DesktopPalette.textLight, 0.22)!;
  Color get info =>
      isDark
          ? DesktopPalette.info
          : Color.lerp(DesktopPalette.info, DesktopPalette.textLight, 0.34)!;
  Color get liked =>
      isDark
          ? DesktopPalette.liked
          : Color.lerp(DesktopPalette.liked, DesktopPalette.badSeed, 0.45)!;

  /// 沉浸舞台（播放器/查看器/阅读器）恒为暗底，文字不跟随主题极性。
  Color get onStage => DesktopPalette.onStage;
  Color onStageWash(double alpha) =>
      DesktopPalette.onStage.withValues(alpha: alpha);

  static DesktopSkin of(BuildContext context) {
    return Theme.of(context).extension<DesktopSkin>() ??
        DesktopSkin.resolve(isDark: true, accent: DesktopAccent.sage);
  }

  @override
  DesktopSkin copyWith({
    bool? isDark,
    Color? bg,
    Color? bg2,
    Color? panel,
    Color? panelSolid,
    Color? pop,
    Color? raise,
    Color? raise2,
    Color? raise3,
    Color? line,
    Color? line2,
    Color? text,
    Color? text2,
    Color? text3,
    Color? accent,
    Color? accentInk,
    Color? warm,
    Color? veil,
    double? ambientOpacity,
    List<BoxShadow>? shadow,
  }) {
    return DesktopSkin(
      isDark: isDark ?? this.isDark,
      bg: bg ?? this.bg,
      bg2: bg2 ?? this.bg2,
      panel: panel ?? this.panel,
      panelSolid: panelSolid ?? this.panelSolid,
      pop: pop ?? this.pop,
      raise: raise ?? this.raise,
      raise2: raise2 ?? this.raise2,
      raise3: raise3 ?? this.raise3,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      warm: warm ?? this.warm,
      veil: veil ?? this.veil,
      ambientOpacity: ambientOpacity ?? this.ambientOpacity,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  DesktopSkin lerp(ThemeExtension<DesktopSkin>? other, double t) {
    if (other is! DesktopSkin) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return DesktopSkin(
      isDark: t < 0.5 ? isDark : other.isDark,
      bg: mix(bg, other.bg),
      bg2: mix(bg2, other.bg2),
      panel: mix(panel, other.panel),
      panelSolid: mix(panelSolid, other.panelSolid),
      pop: mix(pop, other.pop),
      raise: mix(raise, other.raise),
      raise2: mix(raise2, other.raise2),
      raise3: mix(raise3, other.raise3),
      line: mix(line, other.line),
      line2: mix(line2, other.line2),
      text: mix(text, other.text),
      text2: mix(text2, other.text2),
      text3: mix(text3, other.text3),
      accent: mix(accent, other.accent),
      accentInk: mix(accentInk, other.accentInk),
      warm: mix(warm, other.warm),
      veil: mix(veil, other.veil),
      ambientOpacity:
          ambientOpacity + (other.ambientOpacity - ambientOpacity) * t,
      shadow: t < 0.5 ? shadow : other.shadow,
    );
  }
}

/// 桌面几何令牌，逐值取自样例的固定像素。
abstract final class DesktopMetrics {
  /// `.titlebar` 高度。
  static const double titleBarHeight = 46;

  /// `desktop.css:500`：窗口低于该宽度时标题栏改为 auto / 1fr / auto。
  static const double titleBarCompactBreakpoint = 1180;

  /// `.sidebar` 展开宽度。
  static const double sidebarWidth = 232;

  /// `.sidebar.slim` 折叠宽度。
  static const double sidebarSlimWidth = 64;

  /// `.dock.open` 宽度。
  static const double dockWidth = 348;

  /// `.playerbar`（more.css 终值）高度与最大宽度。
  ///
  /// `width: min(1080px, calc(100% - 40px))` 的 1080 是**描边面板本身**的宽度。
  /// 玻璃层必须和它共用同一个盒子；若在玻璃里再塞 margin，模糊背板会比面板
  /// 宽 40px，视觉上就是「播放器底下又垫了一层玻璃」。
  static const double playerBarHeight = 66;
  static const double playerBarMaxWidth = 1080;
  static const double playerBarCompactMaxWidth = 860;
  static const double playerBarWideMargin = 20;
  static const double playerBarCompactMargin = 14;
  static const double playerBarCompactBreakpoint = 1180;
  static const double playerBarNarrowBreakpoint = 860;
  static const double playerBarVisualizerBreakpoint = 1360;
  static const double playerBarWideTrackWidth = 270;
  static const double playerBarCompactTrackWidth = 200;
  static const double playerBarNarrowTrackWidth = 150;
  static const double playerBarWideCenterMinWidth = 280;
  static const double playerBarCompactCenterMinWidth = 200;
  static const double playerBarNarrowCenterMinWidth = 120;
  static const double playerBarCenterMaxWidth = 600;
  static const double playerBarWideSectionGap = 12;
  static const double playerBarNarrowSectionGap = 8;
  static const double playerBarControlGap = 6;
  static const double playerBarSeekTimeWidth = 36;
  static const double playerBarSeekGap = 8;
  static const double playerBarSeekHeight = 14;
  static const double playerBarBottom = 14;

  /// `.root --pb-space`：所有页面为浮动播放条预留的底部空间。
  ///
  /// polish.css:138 终值 116 = 66px 条高 + 14px 底距 + 36px 呼吸空间；
  /// extra.css:16 的 104 已被 polish.css 覆盖，别再退回去。
  static const double playerBarClearance = 116;

  /// `.page` 最大宽度与上下内边距。
  static const double pageMaxWidth = 1560;
  static const double pageTopPadding = 22;
  static const double pageTopPaddingCompact = 14;
  static const double pageHorizontalMin = 24;
  static const double pageHorizontalMax = 52;
  static const double pageHeadSplitBreakpoint = 980;

  /// `.nav-item` 高度（常规 / 紧凑密度 / 次级）。
  static const double navItemHeight = 38;
  static const double navItemHeightCompact = 33;
  static const double navItemSubHeight = 32;

  /// `.btn` / `.btn.lg` / `.tb-btn` / `.tb-btn.big`。
  static const double buttonHeight = 34;
  static const double buttonLargeHeight = 42;
  static const double iconButtonSize = 32;
  static const double iconButtonBigSize = 40;
  static const double iconButtonSmallSize = 24;

  /// `.field input` 与 `.sbox` 高度。
  static const double fieldHeight = 40;
  static const double searchBoxHeight = 36;

  /// 圆角三档 `--r-sm/--r/--r-lg` 与样例中的专用圆角。
  static const double radiusSmall = 8;
  static const double radius = 12;
  static const double radiusLarge = 18;
  static const double radiusButton = 10;
  static const double radiusButtonLarge = 12;
  static const double radiusIconButton = 9;

  /// `.vtoggle button` 的内块圆角（`extra.css:454` 的 `7px`）。
  static const double radiusToggle = 7;
  static const double radiusCard = 18;
  static const double radiusHero = 26;
  static const double radiusDialog = 20;
  static const double radiusPop = 14;
  static const double radiusPlayerBar = 20;

  /// 胶囊圆角：样例 `.chip-btn` / `.tag` / `.dotc` 一律 `99px`。
  static const double radiusPill = 99;

  /// 超胶囊：样例只在 `.dd-pill`、`.np-qpill`、`.nps-*`、`.sf-demo` 四处写 `999px`。
  static const double radiusCapsule = 999;

  /// 图标边长（样例 `<Icon size>` 的常用三档）。
  static const double iconSmall = 15;
  static const double iconMedium = 18;
  static const double iconLarge = 22;

  /// 描边宽度：样例统一 1px 发丝线，选中态 1.5px。
  static const double hairline = 1;
  static const double hairlineStrong = 1.5;

  /// `.rail` 卡片间距与 `.poster-grid` 网格间距。
  static const double railGap = 18;
  static const double gridGap = 22;

  /// `.sect` 区块下间距（常规 / 紧凑）。
  static const double sectionGap = 40;
  static const double sectionGapCompact = 28;
}
