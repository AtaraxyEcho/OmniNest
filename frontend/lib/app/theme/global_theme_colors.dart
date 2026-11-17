import 'package:flutter/material.dart';

/// 全局主题颜色集。
///
/// 浅色与深色调色板均使用该扩展承载语义颜色。
class GlobalThemeColors extends ThemeExtension<GlobalThemeColors> {
  const GlobalThemeColors({
    required this.surface,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.primary,
    required this.primaryContainer,
    required this.onPrimary,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.secondaryContainer,
    required this.tertiary,
    required this.tertiaryContainer,
    required this.error,
    required this.onError,
    required this.outline,
    required this.outlineVariant,
    // 模块派生色
    required this.accentWarm,
    required this.accentCool,
    required this.success,
    required this.warning,
    required this.info,
    // 交互态
    required this.hoverOverlay,
    required this.selectedOverlay,
    required this.focusRing,
    // 覆盖层
    required this.overlay,
    required this.overlayLight,
    required this.shadow,
    // 特殊
    required this.star,
    required this.badgeBg,
    required this.badgeText,
  });

  final Color surface;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color primary;
  final Color primaryContainer;
  final Color onPrimary;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color secondaryContainer;
  final Color tertiary;
  final Color tertiaryContainer;
  final Color error;
  final Color onError;
  final Color outline;
  final Color outlineVariant;
  final Color accentWarm;
  final Color accentCool;
  final Color success;
  final Color warning;
  final Color info;
  final Color hoverOverlay;
  final Color selectedOverlay;
  final Color focusRing;
  final Color overlay;
  final Color overlayLight;
  final Color shadow;
  final Color star;
  final Color badgeBg;
  final Color badgeText;

  @override
  GlobalThemeColors copyWith() => this;

  /// 反转明暗（用于主题切换动画）
  @override
  GlobalThemeColors lerp(GlobalThemeColors? other, double t) {
    if (other == null) return this;
    return GlobalThemeColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceContainerLowest:
          Color.lerp(surfaceContainerLowest, other.surfaceContainerLowest, t)!,
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
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant:
          Color.lerp(onSurfaceVariant, other.onSurfaceVariant, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryContainer:
          Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      onPrimaryContainer:
          Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondaryContainer:
          Color.lerp(secondaryContainer, other.secondaryContainer, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      tertiaryContainer:
          Color.lerp(tertiaryContainer, other.tertiaryContainer, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineVariant: Color.lerp(outlineVariant, other.outlineVariant, t)!,
      accentWarm: Color.lerp(accentWarm, other.accentWarm, t)!,
      accentCool: Color.lerp(accentCool, other.accentCool, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      hoverOverlay: Color.lerp(hoverOverlay, other.hoverOverlay, t)!,
      selectedOverlay: Color.lerp(selectedOverlay, other.selectedOverlay, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      overlayLight: Color.lerp(overlayLight, other.overlayLight, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      star: Color.lerp(star, other.star, t)!,
      badgeBg: Color.lerp(badgeBg, other.badgeBg, t)!,
      badgeText: Color.lerp(badgeText, other.badgeText, t)!,
    );
  }
}

extension GlobalThemeContext on BuildContext {
  /// 返回当前主题注册的全局语义颜色。
  GlobalThemeColors get globalColors {
    return Theme.of(this).extension<GlobalThemeColors>()!;
  }
}
