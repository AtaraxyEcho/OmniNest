import 'package:flutter/material.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';

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

  /// 移动壳层下的面板配色：整组取自环境极性表。
  ///
  /// 壳层的 `surfaceContainerHigh` 在浅主题 + 壁纸在场时是 52% 烟熏值，
  /// 面板直接铺上去会让页面从设置面板底下透出来；壳层的其余抽屉与面板
  /// 都是 `sheetSolid` 实底，这里按同一规则整组换掉，不混用两套配色。
  factory AppBackdropPalette.fromEnv(MobileEnvPalette env) {
    return AppBackdropPalette(
      text: env.ink,
      muted: env.inkMuted,
      accent: env.accentInk,
      accentAlt: env.accentInk,
      surface: env.sheetSolid,
      surfaceContainer: env.surfaceRaised,
      outline: env.line09,
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
