import 'package:flutter/material.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';

@immutable
class ReaderColors extends ThemeExtension<ReaderColors> {
  const ReaderColors({
    required this.surface,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.outlineVariant,
    required this.primary,
    required this.onPrimaryContainer,
    required this.primaryContainer,
    required this.sidebarSelectedBg,
    required this.sidebarSelectedBorder,
    required this.sidebarSelectedFg,
    required this.sidebarHoverBg,
    required this.tertiary,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.success,
    required this.warning,
    required this.danger,
    required this.overlay,
    required this.overlayLight,
    required this.badgeBg,
    required this.badgeText,
    required this.star,
    required this.comicBg,
    required this.comicText,
    required this.comicMuted,
    required this.coverGradientStart,
    required this.coverGradientEnd,
    required this.reading,
  });

  final Color surface;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color outlineVariant;
  final Color primary;
  final Color onPrimaryContainer;
  final Color primaryContainer;
  final Color sidebarSelectedBg;
  final Color sidebarSelectedBorder;
  final Color sidebarSelectedFg;
  final Color sidebarHoverBg;
  final Color tertiary;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color success;
  final Color warning;
  final Color danger;
  final Color overlay;
  final Color overlayLight;
  final Color badgeBg;
  final Color badgeText;
  final Color star;
  final Color comicBg;
  final Color comicText;
  final Color comicMuted;
  final Color coverGradientStart;
  final Color coverGradientEnd;

  /// 阅读强调色（琥珀棕），用于进度线、完成徽标等阅读语义元素
  final Color reading;

  /// 参考设计纸感亮色 token（米白纸面 / 墨黑前景 / 琥珀强调）
  static const ReaderColors _light = ReaderColors(
    surface: Color(0xFFF6F5F1),
    surfaceContainerLow: Color(0xFFFDFCF9),
    surfaceContainer: Color(0xFFF1EFE9),
    surfaceContainerHigh: Color(0xFFECEAE5),
    surfaceContainerHighest: Color(0xFFE2DFD9),
    outlineVariant: Color(0xFFE2DFD9),
    primary: Color(0xFF0F0E0C),
    onPrimaryContainer: Color(0xFFF6F5F1),
    primaryContainer: Color(0xFFECEAE5),
    sidebarSelectedBg: Color(0xFF0F0E0C),
    sidebarSelectedBorder: Color(0xFF0F0E0C),
    sidebarSelectedFg: Color(0xFFF6F5F1),
    sidebarHoverBg: Color(0x140F0E0C),
    tertiary: Color(0xFFB87A35),
    onSurface: Color(0xFF0F0E0C),
    onSurfaceVariant: Color(0xFF87847C),
    success: Color(0xFF4C8C72),
    warning: Color(0xFFB08830),
    danger: Color(0xFFA8452E),
    overlay: Color(0xFF0F0E0C),
    overlayLight: Color(0x140F0E0C),
    badgeBg: Color(0xFFECEAE5),
    badgeText: Color(0xFF0F0E0C),
    star: Color(0xFFB87A35),
    comicBg: Color(0xFF000000),
    comicText: Color(0xFFFFFFFF),
    comicMuted: Color(0xB3FFFFFF),
    coverGradientStart: Color(0xFFFDFCF9),
    coverGradientEnd: Color(0xFFECEAE5),
    reading: Color(0xFFB87A35),
  );

  /// 参考设计纸感暗色 token（暖黑纸面 / 米白前景 / 琥珀强调）
  static const ReaderColors _dark = ReaderColors(
    surface: Color(0xFF0F0E0C),
    surfaceContainerLow: Color(0xFF1A1916),
    surfaceContainer: Color(0xFF171511),
    surfaceContainerHigh: Color(0xFF252320),
    surfaceContainerHighest: Color(0xFF2C2925),
    outlineVariant: Color(0xFF2C2925),
    primary: Color(0xFFEEEDE9),
    onPrimaryContainer: Color(0xFF0F0E0C),
    primaryContainer: Color(0xFF252320),
    sidebarSelectedBg: Color(0xFFEEEDE9),
    sidebarSelectedBorder: Color(0xFFEEEDE9),
    sidebarSelectedFg: Color(0xFF0F0E0C),
    sidebarHoverBg: Color(0x14EEEDE9),
    tertiary: Color(0xFFC8923E),
    onSurface: Color(0xFFEEEDE9),
    onSurfaceVariant: Color(0xFF6E6C64),
    success: Color(0xFF5A9C7E),
    warning: Color(0xFFC8923E),
    danger: Color(0xFFC45A3D),
    overlay: Color(0xFF000000),
    overlayLight: Color(0x14000000),
    badgeBg: Color(0xFF252320),
    badgeText: Color(0xFFEEEDE9),
    star: Color(0xFFC8923E),
    comicBg: Color(0xFF000000),
    comicText: Color(0xFFFFFFFF),
    comicMuted: Color(0xB3FFFFFF),
    coverGradientStart: Color(0xFF1A1916),
    coverGradientEnd: Color(0xFF252320),
    reading: Color(0xFFC8923E),
  );

  /// Reader 模块固定使用参考设计的纸感配色，全局主题只决定亮暗方向。
  factory ReaderColors.fromGlobal(GlobalThemeColors base) {
    final isDark =
        ThemeData.estimateBrightnessForColor(base.surface) == Brightness.dark;
    return isDark ? _dark : _light;
  }

  static const List<ReaderColors> values = [];

  @override
  ReaderColors copyWith({
    Color? surface,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? outlineVariant,
    Color? primary,
    Color? onPrimaryContainer,
    Color? primaryContainer,
    Color? sidebarSelectedBg,
    Color? sidebarSelectedBorder,
    Color? sidebarSelectedFg,
    Color? sidebarHoverBg,
    Color? tertiary,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? success,
    Color? warning,
    Color? danger,
    Color? overlay,
    Color? overlayLight,
    Color? badgeBg,
    Color? badgeText,
    Color? star,
    Color? comicBg,
    Color? comicText,
    Color? comicMuted,
    Color? coverGradientStart,
    Color? coverGradientEnd,
    Color? reading,
  }) {
    return ReaderColors(
      surface: surface ?? this.surface,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      primary: primary ?? this.primary,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      sidebarSelectedBg: sidebarSelectedBg ?? this.sidebarSelectedBg,
      sidebarSelectedBorder:
          sidebarSelectedBorder ?? this.sidebarSelectedBorder,
      sidebarSelectedFg: sidebarSelectedFg ?? this.sidebarSelectedFg,
      sidebarHoverBg: sidebarHoverBg ?? this.sidebarHoverBg,
      tertiary: tertiary ?? this.tertiary,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      overlay: overlay ?? this.overlay,
      overlayLight: overlayLight ?? this.overlayLight,
      badgeBg: badgeBg ?? this.badgeBg,
      badgeText: badgeText ?? this.badgeText,
      star: star ?? this.star,
      comicBg: comicBg ?? this.comicBg,
      comicText: comicText ?? this.comicText,
      comicMuted: comicMuted ?? this.comicMuted,
      coverGradientStart: coverGradientStart ?? this.coverGradientStart,
      coverGradientEnd: coverGradientEnd ?? this.coverGradientEnd,
      reading: reading ?? this.reading,
    );
  }

  @override
  ReaderColors lerp(ReaderColors? other, double t) {
    if (other is! ReaderColors) return this;
    return ReaderColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceContainerLow:
          Color.lerp(surfaceContainerLow, other.surfaceContainerLow, t)!,
      surfaceContainer:
          Color.lerp(surfaceContainer, other.surfaceContainer, t)!,
      surfaceContainerHigh:
          Color.lerp(surfaceContainerHigh, other.surfaceContainerHigh, t)!,
      surfaceContainerHighest:
          Color.lerp(
            surfaceContainerHighest,
            other.surfaceContainerHighest,
            t,
          )!,
      outlineVariant: Color.lerp(outlineVariant, other.outlineVariant, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimaryContainer:
          Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      primaryContainer:
          Color.lerp(primaryContainer, other.primaryContainer, t)!,
      sidebarSelectedBg:
          Color.lerp(sidebarSelectedBg, other.sidebarSelectedBg, t)!,
      sidebarSelectedBorder:
          Color.lerp(sidebarSelectedBorder, other.sidebarSelectedBorder, t)!,
      sidebarSelectedFg:
          Color.lerp(sidebarSelectedFg, other.sidebarSelectedFg, t)!,
      sidebarHoverBg: Color.lerp(sidebarHoverBg, other.sidebarHoverBg, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant:
          Color.lerp(onSurfaceVariant, other.onSurfaceVariant, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      overlayLight: Color.lerp(overlayLight, other.overlayLight, t)!,
      badgeBg: Color.lerp(badgeBg, other.badgeBg, t)!,
      badgeText: Color.lerp(badgeText, other.badgeText, t)!,
      star: Color.lerp(star, other.star, t)!,
      comicBg: Color.lerp(comicBg, other.comicBg, t)!,
      comicText: Color.lerp(comicText, other.comicText, t)!,
      comicMuted: Color.lerp(comicMuted, other.comicMuted, t)!,
      coverGradientStart:
          Color.lerp(coverGradientStart, other.coverGradientStart, t)!,
      coverGradientEnd:
          Color.lerp(coverGradientEnd, other.coverGradientEnd, t)!,
      reading: Color.lerp(reading, other.reading, t)!,
    );
  }
}

extension ReaderColorsX on BuildContext {
  ReaderColors get readerColors => Theme.of(this).extension<ReaderColors>()!;
}
