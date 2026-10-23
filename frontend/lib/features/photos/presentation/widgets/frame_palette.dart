import 'package:flutter/material.dart';

/// Frame 风格暖纸色调色板（依据 Figma "Photos Library Model UI"）。
///
/// [FramePalette] 保存亮色基准值；组件实际取色应使用 `context.frameColors`，
/// 其按当前 Theme 亮度解析亮/暗两套色值。
abstract final class FramePalette {
  static const bg = Color(0xFFFAFAF8);
  static const ink = Color(0xFF1A1917);
  static const sub = Color(0xFF5A5754);
  static const muted = Color(0xFF8A8680);
  static const accent = Color(0xFFC07840);
  static const border = Color(0xFFE5E2DC);
  static const card = Color(0xFFEAE7E0);
  static const hover = Color(0xFFF0EDE6);
  static const hoverSoft = Color(0xFFF4F2EE);
  static const navBg = Color(0xFFFAFAF8);
  static const activeBg = Color(0xFFEDE9E1);
  static const chipActiveBg = Color(0xFFFDF4EC);
  static const selectActiveBg = Color(0xFFF5EFE6);
  static const dark = Color(0xFF1A1917);
  static const viewerBg = Color(0xFF0D0D0C);
  static const viewerPanel = Color(0xFF111110);
  static const white = Colors.white;

  /// 全屏查看舞台底色与上下淡出端色。
  static const stage = Color(0xFF050807);
  static const stageFadeStart = Color(0x00050807);
  static const stageFadeEnd = Color(0xA6050807);

  /// 批量操作条的压色底。
  static const batchScrim = Color(0x59000000);

  /// 分享影集的近黑遮罩。
  static const sharedAlbumScrim = Color(0xF2000000);

  /// 分组卡片底部渐变终点。
  static const groupsFadeEnd = Color(0xB3000000);

  /// 图片加载失败时的中性占位底色。
  static const placeholder = Color(0xFF222626);

  /// 设计稿标题字体 Instrument Serif；中文标题回退到内置 NotoSerifSC。
  static const serifFamily = 'InstrumentSerif';
  static const serifFallback = <String>['NotoSerifSC'];
}

/// Frame 组件在当前亮度下使用的色值组合。
@immutable
class FrameColors {
  const FrameColors({
    required this.bg,
    required this.ink,
    required this.sub,
    required this.muted,
    required this.accent,
    required this.border,
    required this.card,
    required this.hover,
    required this.navBg,
    required this.activeBg,
    required this.chipActiveBg,
    required this.selectActiveBg,
    required this.btnBg,
    required this.onBtn,
    required this.searchFill,
    required this.overlayTextDim,
  });

  /// 页面/侧栏/顶栏/底部导航背景。
  final Color bg;
  final Color navBg;

  /// 主文本。
  final Color ink;

  /// 次级文本。
  final Color sub;

  /// 弱化文本与未激活图标。
  final Color muted;

  /// 陶土色强调。
  final Color accent;

  final Color border;
  final Color card;
  final Color hover;
  final Color activeBg;
  final Color chipActiveBg;
  final Color selectActiveBg;

  /// 黑色主按钮底色；暗色模式反转为浅色。
  final Color btnBg;

  /// 黑色主按钮上的文字/图标颜色。
  final Color onBtn;

  /// 搜索框填充色。
  final Color searchFill;

  /// 图片遮罩内次级文字（日期）的弱化系数。
  final double overlayTextDim;

  /// 亮色（设计稿基准）。
  static const FrameColors light = FrameColors(
    bg: FramePalette.bg,
    navBg: FramePalette.navBg,
    ink: FramePalette.ink,
    sub: FramePalette.sub,
    muted: FramePalette.muted,
    accent: FramePalette.accent,
    border: FramePalette.border,
    card: FramePalette.card,
    hover: FramePalette.hover,
    activeBg: FramePalette.activeBg,
    chipActiveBg: FramePalette.chipActiveBg,
    selectActiveBg: FramePalette.selectActiveBg,
    btnBg: FramePalette.dark,
    onBtn: Colors.white,
    searchFill: Colors.white,
    overlayTextDim: 0.55,
  );

  /// 暗色（暖纸色的暗版，强调色提亮保证对比；悬停/激活底色与背景拉开差距）。
  static const FrameColors dark = FrameColors(
    bg: Color(0xFF191817),
    navBg: Color(0xFF191817),
    ink: Color(0xFFF2EFE9),
    sub: Color(0xFFB8B3AC),
    muted: Color(0xFF8A8680),
    accent: Color(0xFFCE8A52),
    border: Color(0xFF2E2C28),
    card: Color(0xFF242220),
    hover: Color(0xFF2E2C28),
    activeBg: Color(0xFF37342E),
    chipActiveBg: Color(0xFF3A2C1E),
    selectActiveBg: Color(0xFF3A2C1E),
    btnBg: Color(0xFFF2EFE9),
    onBtn: Color(0xFF1A1917),
    searchFill: Color(0xFF211F1D),
    overlayTextDim: 0.55,
  );

  /// 按当前主题亮度取色；主题未注册 Frame 扩展时同样生效。
  static FrameColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

extension FrameColorsX on BuildContext {
  /// 当前亮度下的 Frame 色值组合。
  FrameColors get frameColors => FrameColors.of(this);
}
