import 'package:flutter/material.dart';

/// Movies 模块新版设计令牌。
///
/// 参照「Redesign Movies Module」Figma 原型 1:1 落地：
/// 暖白/近黑双主题、陶土红主色、2px 直角、
/// Instrument Serif（拉丁展示）+ Noto Serif SC（中文展示）+
/// JetBrains Mono（数据）字体体系。
@immutable
class MovieRedesignPalette {
  const MovieRedesignPalette({
    required this.background,
    required this.card,
    required this.foreground,
    required this.muted,
    required this.mutedForeground,
    required this.border,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.secondaryForeground,
  });

  /// 页面背景（亮 #f4f3ef / 暗 #0d0d0d）。
  final Color background;

  /// 卡片背景。
  final Color card;

  /// 主文字。
  final Color foreground;

  /// 弱填充背景（筛选芯片、hover 底色）。
  final Color muted;

  /// 次要文字。
  final Color mutedForeground;

  /// 边框。
  final Color border;

  /// 陶土红主色。
  final Color primary;

  /// 主色上的文字。
  final Color onPrimary;

  /// 次级填充（继续观看卡片底色等）。
  final Color secondary;

  /// 次级填充上的文字。
  final Color secondaryForeground;

  /// 已匹配状态色（emerald-500）。
  static const Color statusMatched = Color(0xFF10B981);

  /// 待刮削状态色（amber-400）。
  static const Color statusPending = Color(0xFFFBBF24);

  /// 失败状态色（red-500）。
  static const Color statusFailed = Color(0xFFEF4444);

  /// 评分星星色（amber-500）。
  static const Color star = Color(0xFFF59E0B);

  /// 内嵌字幕徽标色（sky-500）。
  static const Color subtitleEmbedded = Color(0xFF0EA5E9);

  /// 全局直角半径（2px）。
  static const double radius = 2;

  static const BorderRadius borderRadius = BorderRadius.all(
    Radius.circular(radius),
  );

  /// 亮色主题调色板。
  static const MovieRedesignPalette light = MovieRedesignPalette(
    background: Color(0xFFF4F3EF),
    card: Color(0xFFFFFFFF),
    foreground: Color(0xFF111111),
    muted: Color(0xFFE8E6E0),
    mutedForeground: Color(0xFF777777),
    border: Color(0xFFD8D6D0),
    primary: Color(0xFFC84B2F),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFFECEAE4),
    secondaryForeground: Color(0xFF333333),
  );

  /// 暗色主题调色板。
  static const MovieRedesignPalette dark = MovieRedesignPalette(
    background: Color(0xFF0D0D0D),
    card: Color(0xFF161616),
    foreground: Color(0xFFF0EFE9),
    muted: Color(0xFF1A1A1A),
    mutedForeground: Color(0xFF888888),
    border: Color(0xFF2A2A2A),
    primary: Color(0xFFD95F3F),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF1E1E1E),
    secondaryForeground: Color(0xFFCCCCCC),
  );
}

/// 按当前主题亮度解析新版调色板。
extension MovieRedesignX on BuildContext {
  MovieRedesignPalette get movieRedesign =>
      Theme.of(this).brightness == Brightness.dark
          ? MovieRedesignPalette.dark
          : MovieRedesignPalette.light;
}

/// 新版三字体排版：衬线展示、正文与等宽数据。
@immutable
class MovieRedesignText {
  const MovieRedesignText(this.palette);

  final MovieRedesignPalette palette;

  /// 衬线展示标题：拉丁取 Instrument Serif，中文回退 Noto Serif SC。
  TextStyle display({double size = 30, Color? color, double height = 1.15}) {
    return TextStyle(
      fontFamily: 'InstrumentSerif',
      fontFamilyFallback: const ['NotoSerifSC'],
      fontSize: size,
      height: height,
      color: color ?? palette.foreground,
      fontWeight: FontWeight.w400,
    );
  }

  /// 正文样式。
  TextStyle body({
    double size = 14,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) {
    return TextStyle(
      fontSize: size,
      height: height,
      color: color ?? palette.foreground,
      fontWeight: weight,
    );
  }

  /// 等宽数据样式：拉丁与数字取 JetBrains Mono，中文回退 Noto Sans SC。
  TextStyle mono({
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'JetBrainsMono',
      fontFamilyFallback: const ['NotoSansSC'],
      fontSize: size,
      height: height,
      color: color ?? palette.mutedForeground,
      fontWeight: weight,
    );
  }
}

/// 按当前主题解析排版工具。
extension MovieRedesignTextX on BuildContext {
  MovieRedesignText get movieRedesignText => MovieRedesignText(movieRedesign);
}

/// 原型 main 区域四周留白：p-3 / sm:p-5 / lg:p-6（12 / 20 / 24）。
EdgeInsets movieRedesignPagePadding(double width) {
  final edge = width >= 1024 ? 24.0 : (width >= 640 ? 20.0 : 12.0);
  return EdgeInsets.all(edge);
}

/// 原型 sm: 断点（640px）判断，用于成对字号/间距切换。
bool movieRedesignAtSm(double width) => width >= 640;

/// 影片详情页暗色金调令牌（对应 Movies Module Design/components/Detail.tsx）。
class MovieDetailTheme {
  MovieDetailTheme._();

  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF111111);
  static const Color foreground = Color(0xFFF0F0F0);
  static const Color secondaryText = Color(0xFFA0A0A0);
  static const Color mutedText = Color(0xFF606060);
  static const Color border = Color(0xFF1E1E1E);
  static const Color accent = Color(0xFFC8A96E);
  static const Color statusPending = Color(0xFFFBBF24);
  static const Color statusFailed = Color(0xFFF87171);

  /// 展示衬线：拉丁取 Instrument Serif，中文回退 Noto Serif SC。
  static TextStyle serif(double size, {Color? color, double? height}) {
    return TextStyle(
      fontFamily: 'InstrumentSerif',
      fontFamilyFallback: const ['NotoSerifSC'],
      fontSize: size,
      height: height,
      color: color ?? foreground,
      fontWeight: FontWeight.w400,
    );
  }

  /// 等宽标签：拉丁与数字取 JetBrains Mono，中文回退 Noto Sans SC。
  static TextStyle mono(
    double size, {
    Color? color,
    double? height,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: 'JetBrainsMono',
      fontFamilyFallback: const ['NotoSansSC'],
      fontSize: size,
      height: height,
      color: color ?? mutedText,
      fontWeight: FontWeight.w400,
      letterSpacing: letterSpacing,
    );
  }

  /// 正文：Inter 拉丁，中文回退 Noto Sans SC。
  static TextStyle body(
    double size, {
    Color? color,
    double? height,
    FontWeight weight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: const ['NotoSansSC'],
      fontSize: size,
      height: height,
      color: color ?? foreground,
      fontWeight: weight,
    );
  }
}

/// 详情页族（影片/剧集/编辑抽屉）固定使用暗色调色板：
/// 页面底色硬编码暗色，不随应用主题切换。
extension MovieDetailFixedPaletteX on BuildContext {
  MovieRedesignPalette get movieDetailPalette => MovieRedesignPalette.dark;
  MovieRedesignText get movieDetailText =>
      MovieRedesignText(MovieRedesignPalette.dark);
}
