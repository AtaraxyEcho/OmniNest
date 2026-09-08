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

  /// 从全局主题色派生 Reader 模块专属色
  factory ReaderColors.fromGlobal(GlobalThemeColors base) {
    final isDark =
        ThemeData.estimateBrightnessForColor(base.surface) == Brightness.dark;
    return ReaderColors(
      surface: base.surface,
      surfaceContainerLow: base.surfaceContainerLow,
      surfaceContainer: base.surfaceContainer,
      surfaceContainerHigh: base.surfaceContainerHigh,
      surfaceContainerHighest: base.surfaceContainerHighest,
      outlineVariant: base.outlineVariant,
      primary: base.primary,
      onPrimaryContainer: base.onPrimaryContainer,
      primaryContainer: base.primaryContainer,
      sidebarSelectedBg: base.primary.withValues(alpha: isDark ? 0.20 : 0.12),
      sidebarSelectedBorder: base.primary,
      sidebarSelectedFg: base.primary,
      sidebarHoverBg: base.primary.withValues(alpha: isDark ? 0.12 : 0.07),
      tertiary: base.accentWarm,
      onSurface: base.onSurface,
      onSurfaceVariant: base.onSurfaceVariant,
      success: base.success,
      warning: base.warning,
      danger: base.error,
      overlay: base.overlay,
      overlayLight: base.overlayLight,
      badgeBg: base.badgeBg,
      badgeText: base.badgeText,
      star: base.star,
      comicBg: const Color(0xFF000000),
      comicText: const Color(0xFFFFFFFF),
      comicMuted: const Color(0xB3FFFFFF),
      coverGradientStart: base.surfaceContainerLowest,
      coverGradientEnd: base.primaryContainer,
      reading: isDark ? const Color(0xFFC8923E) : const Color(0xFFB87A35),
    );
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
