import 'package:flutter/material.dart';

/// 应用背景设置面板使用的颜色。
class AppBackdropPalette {
  const AppBackdropPalette({
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentAlt,
    required this.surface,
    required this.surfaceContainer,
    required this.outline,
  });

  /// 从应用主题派生面板配色,保证浅色/深色主题下文字与面板底色可读。
  factory AppBackdropPalette.fromScheme(ColorScheme scheme) {
    return AppBackdropPalette(
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      accent: scheme.primary,
      accentAlt: scheme.tertiary,
      surface: scheme.surfaceContainerHigh,
      surfaceContainer: scheme.surfaceContainerHighest,
      outline: scheme.outlineVariant,
    );
  }

  final Color text;
  final Color muted;
  final Color accent;
  final Color accentAlt;
  final Color surface;
  final Color surfaceContainer;
  final Color outline;
}
