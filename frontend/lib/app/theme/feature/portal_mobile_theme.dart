import 'package:flutter/material.dart';
import 'package:omninest/app/theme/backdrop_translucent_colors.dart';

/// Portal 移动端在动态背景和纯色背景之间共享的主题派生规则。
abstract final class PortalMobileTheme {
  /// 返回仅作用于 Portal 内容树的浅层主题。
  static ThemeData resolve(
    BuildContext context, {
    required bool backdropActive,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final light = scheme.brightness == Brightness.light;
    if (light && backdropActive) {
      return theme.copyWith(
        colorScheme: scheme.copyWith(
          surface: BackdropTranslucentColors.canvas,
          surfaceContainerLow: BackdropTranslucentColors.surfaceLow,
          surfaceContainer: BackdropTranslucentColors.surface,
          surfaceContainerHigh: BackdropTranslucentColors.surfaceHigh,
          surfaceContainerHighest: BackdropTranslucentColors.surfaceHighest,
          primary: BackdropTranslucentColors.primary,
          primaryContainer: BackdropTranslucentColors.primaryContainer,
          onPrimary: BackdropTranslucentColors.onPrimary,
          onPrimaryContainer: BackdropTranslucentColors.onPrimaryContainer,
          tertiary: BackdropTranslucentColors.tertiary,
          onSurface: BackdropTranslucentColors.onSurface,
          onSurfaceVariant: BackdropTranslucentColors.onSurfaceVariant,
          outline: BackdropTranslucentColors.outline,
          outlineVariant: BackdropTranslucentColors.outlineVariant,
          shadow: BackdropTranslucentColors.shadow,
        ),
      );
    }
    final canvas =
        light
            ? Color.lerp(scheme.surface, scheme.primaryContainer, 0.08)!
            : scheme.surface;
    final surface =
        Color.lerp(
          light ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
          light ? scheme.primaryContainer : scheme.secondaryContainer,
          light ? 0.10 : 0.05,
        )!;
    final raised =
        Color.lerp(
          light ? scheme.surfaceContainerHighest : scheme.surfaceContainer,
          light ? scheme.secondaryContainer : scheme.primaryContainer,
          light ? 0.08 : 0.06,
        )!;
    final selected = Color.lerp(surface, scheme.primary, light ? 0.14 : 0.18)!;
    return theme.copyWith(
      colorScheme: scheme.copyWith(
        surface: canvas,
        surfaceContainerLow: surface.withValues(
          alpha: backdropActive ? (light ? 0.68 : 0.72) : 1,
        ),
        surfaceContainer: raised.withValues(
          alpha: backdropActive ? (light ? 0.76 : 0.78) : 1,
        ),
        primaryContainer: selected.withValues(alpha: backdropActive ? 0.84 : 1),
        outlineVariant: scheme.outlineVariant.withValues(
          alpha: backdropActive ? (light ? 0.58 : 0.72) : 1,
        ),
      ),
    );
  }
}
