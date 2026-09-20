import 'package:flutter/material.dart';
import 'package:omninest/app/theme/backdrop_translucent_colors.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';

/// Music 在浅色主题动态背景上使用的局部主题。
abstract final class MusicBackdropTheme {
  /// Music 模块内文字按钮统一中性前景。
  ///
  /// 模块语境下的 colorScheme.primary 为深绿；按配色原则，绿色仅保留给
  /// 激活与选中语义，「查看全部」等文字动作一律使用中性次级色。
  /// 各 Music 路由入口统一套用，避免逐个按钮覆写产生漂移。
  static ThemeData withNeutralTextButtons(ThemeData source) {
    return source.copyWith(
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: source.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 动态背景启用时切换为烟熏透明表面，其他场景保持原主题。
  static ThemeData resolve(ThemeData source, {required bool backdropActive}) {
    if (!backdropActive || source.brightness != Brightness.light) {
      return source;
    }
    final scheme = source.colorScheme.copyWith(
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
    );
    return source.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: BackdropTranslucentColors.surface,
      cardColor: BackdropTranslucentColors.surface,
      textTheme: source.textTheme.apply(
        bodyColor: BackdropTranslucentColors.onSurface,
        displayColor: BackdropTranslucentColors.onSurface,
      ),
      iconTheme: source.iconTheme.copyWith(
        color: BackdropTranslucentColors.onSurface,
      ),
      cardTheme: source.cardTheme.copyWith(
        color: BackdropTranslucentColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: source.dialogTheme.copyWith(
        backgroundColor: BackdropTranslucentColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: source.bottomSheetTheme.copyWith(
        backgroundColor: BackdropTranslucentColors.surface,
        modalBackgroundColor: BackdropTranslucentColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: source.popupMenuTheme.copyWith(
        color: BackdropTranslucentColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(
          fontSize: 14,
          color: BackdropTranslucentColors.onSurface,
        ),
      ),
      extensions: source.extensions.values.map(
        (extension) => switch (extension) {
          MusicColors value => _resolveMusicColors(value),
          _ => extension,
        },
      ),
    );
  }

  static MusicColors _resolveMusicColors(MusicColors source) {
    return source.copyWith(
      surface: BackdropTranslucentColors.surfaceLow,
      background: BackdropTranslucentColors.canvas,
      surfaceContainer: BackdropTranslucentColors.surface,
      surfaceContainerHigh: BackdropTranslucentColors.surfaceHigh,
      primary: BackdropTranslucentColors.primary,
      onSurface: BackdropTranslucentColors.onSurface,
      onSurfaceVariant: BackdropTranslucentColors.onSurfaceVariant,
      outline: BackdropTranslucentColors.outlineVariant,
      heroGradientStart: BackdropTranslucentColors.canvas,
      heroGradientCenter: BackdropTranslucentColors.surfaceLow,
      heroGradientEnd: BackdropTranslucentColors.surface,
      heroTextColor: BackdropTranslucentColors.onSurface,
      heroTextSecondary: BackdropTranslucentColors.onSurfaceVariant,
      cardBorder: BackdropTranslucentColors.outlineVariant,
      cardBorderHover: BackdropTranslucentColors.outline,
      albumHoverOverlay: BackdropTranslucentColors.primary.withValues(
        alpha: 0.08,
      ),
      glassBorderStart: BackdropTranslucentColors.outline,
      glassBorderEnd: BackdropTranslucentColors.outlineVariant,
      selectedBg: BackdropTranslucentColors.primaryContainer,
      selectedBorder: BackdropTranslucentColors.primary.withValues(alpha: 0.42),
      selectedShadowColor: BackdropTranslucentColors.primary.withValues(
        alpha: 0.18,
      ),
      shadow: BackdropTranslucentColors.shadow,
      discBg: BackdropTranslucentColors.surfaceHighest,
      discCenter: BackdropTranslucentColors.surfaceHigh,
    );
  }
}
