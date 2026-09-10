import 'package:flutter/material.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';

/// 移动端壳层使用的主题组合器。
///
/// 深色主题保持根主题配置，浅色主题统一各模块的中性表面和正文颜色，
/// 模块强调色继续由对应主题扩展维护。
abstract final class MobileAppTheme {
  static const GlobalThemeColors _lightColors = GlobalThemeColors(
    surface: Color(0xFFF4F7F5),
    surfaceContainerLowest: Color(0xFFFBFCFB),
    surfaceContainerLow: Color(0xFFEDF2EF),
    surfaceContainer: Color(0xFFE5ECE8),
    surfaceContainerHigh: Color(0xFFDAE3DE),
    surfaceContainerHighest: Color(0xFFCEDAD3),
    onSurface: Color(0xFF17201C),
    onSurfaceVariant: Color(0xFF4F5E56),
    primary: Color(0xFF0C6F64),
    primaryContainer: Color(0xFFD4ECE6),
    onPrimary: Color(0xFFFFFFFF),
    onPrimaryContainer: Color(0xFF153D36),
    secondary: Color(0xFF4D6470),
    secondaryContainer: Color(0xFFDCE8EB),
    tertiary: Color(0xFF8A6035),
    tertiaryContainer: Color(0xFFF0E2D3),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    outline: Color(0xFF7D8B83),
    outlineVariant: Color(0xFFC3CFC8),
    accentWarm: Color(0xFF8A6035),
    accentCool: Color(0xFF4D6470),
    success: Color(0xFF217A45),
    warning: Color(0xFF8B6508),
    info: Color(0xFF356A91),
    hoverOverlay: Color(0x0A0C6F64),
    selectedOverlay: Color(0x170C6F64),
    focusRing: Color(0x660C6F64),
    overlay: Color(0x66000000),
    overlayLight: Color(0x14000000),
    shadow: Color(0x2417201C),
    star: Color(0xFF8B6508),
    badgeBg: Color(0xFF33423C),
    badgeText: Color(0xFFFFFFFF),
  );

  /// 根据根主题返回移动端局部主题。
  static ThemeData resolve(ThemeData source) {
    if (source.brightness == Brightness.dark) {
      return source;
    }
    final colors = _lightColors;
    final scheme = source.colorScheme.copyWith(
      surface: colors.surface,
      surfaceContainerLowest: colors.surfaceContainerLowest,
      surfaceContainerLow: colors.surfaceContainerLow,
      surfaceContainer: colors.surfaceContainer,
      surfaceContainerHigh: colors.surfaceContainerHigh,
      surfaceContainerHighest: colors.surfaceContainerHighest,
      onSurface: colors.onSurface,
      onSurfaceVariant: colors.onSurfaceVariant,
      primary: colors.primary,
      primaryContainer: colors.primaryContainer,
      onPrimary: colors.onPrimary,
      onPrimaryContainer: colors.onPrimaryContainer,
      secondary: colors.secondary,
      secondaryContainer: colors.secondaryContainer,
      tertiary: colors.tertiary,
      tertiaryContainer: colors.tertiaryContainer,
      error: colors.error,
      onError: colors.onError,
      outline: colors.outline,
      outlineVariant: colors.outlineVariant,
      shadow: colors.shadow,
    );
    return source.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      cardColor: colors.surfaceContainerLow,
      dividerColor: colors.outlineVariant,
      textTheme: source.textTheme.apply(
        bodyColor: colors.onSurface,
        displayColor: colors.onSurface,
      ),
      primaryTextTheme: source.primaryTextTheme.apply(
        bodyColor: colors.onSurface,
        displayColor: colors.onSurface,
      ),
      iconTheme: source.iconTheme.copyWith(color: colors.onSurfaceVariant),
      appBarTheme: source.appBarTheme.copyWith(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: source.appBarTheme.titleTextStyle?.copyWith(
          color: colors.onSurface,
        ),
      ),
      cardTheme: source.cardTheme.copyWith(
        color: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: source.bottomSheetTheme.copyWith(
        backgroundColor: colors.surfaceContainerLow,
        modalBackgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: source.dialogTheme.copyWith(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: source.navigationBarTheme.copyWith(
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.primaryContainer,
      ),
      navigationRailTheme: source.navigationRailTheme.copyWith(
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.primaryContainer,
      ),
      inputDecorationTheme: source.inputDecorationTheme.copyWith(
        // 浅色模式避免纯白输入框。
        fillColor: colors.surfaceContainerLow,
        labelStyle: source.inputDecorationTheme.labelStyle?.copyWith(
          color: colors.onSurfaceVariant,
        ),
        hintStyle: source.inputDecorationTheme.hintStyle?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      listTileTheme: source.listTileTheme.copyWith(
        iconColor: colors.onSurfaceVariant,
        textColor: colors.onSurface,
      ),
      dividerTheme: source.dividerTheme.copyWith(color: colors.outlineVariant),
      extensions: source.extensions.values.map(
        (extension) => _adaptExtension(extension, colors),
      ),
    );
  }

  static ThemeExtension<dynamic> _adaptExtension(
    ThemeExtension<dynamic> extension,
    GlobalThemeColors colors,
  ) {
    return switch (extension) {
      GlobalThemeColors() => colors,
      AdminColors value => value.copyWith(
        surface: colors.surface,
        surfaceContainerLowest: colors.surfaceContainerLowest,
        surfaceContainerLow: colors.surfaceContainerLow,
        surfaceContainer: colors.surfaceContainer,
        surfaceContainerHigh: colors.surfaceContainerHigh,
        surfaceContainerHighest: colors.surfaceContainerHighest,
        onSurface: colors.onSurface,
        onSurfaceVariant: colors.onSurfaceVariant,
        outlineVariant: colors.outlineVariant,
      ),
      MusicColors value => value,
      VideoColors value => value.copyWith(
        surface: colors.surface,
        surfaceContainerLow: colors.surfaceContainerLow,
        surfaceContainer: colors.surfaceContainer,
        surfaceContainerHigh: colors.surfaceContainerHigh,
        surfaceContainerHighest: colors.surfaceContainerHighest,
        onSurface: colors.onSurface,
        onSurfaceVariant: colors.onSurfaceVariant,
        outlineVariant: colors.outlineVariant,
      ),
      ReaderColors value => value.copyWith(
        surface: colors.surface,
        surfaceContainerLow: colors.surfaceContainerLow,
        surfaceContainer: colors.surfaceContainer,
        surfaceContainerHigh: colors.surfaceContainerHigh,
        surfaceContainerHighest: colors.surfaceContainerHighest,
        onSurface: colors.onSurface,
        onSurfaceVariant: colors.onSurfaceVariant,
        outlineVariant: colors.outlineVariant,
      ),
      PhotosColors value => value.copyWith(
        surface: colors.surface,
        surfaceContainerLow: colors.surfaceContainerLow,
        surfaceContainer: colors.surfaceContainer,
        surfaceContainerHigh: colors.surfaceContainerHigh,
        surfaceContainerHighest: colors.surfaceContainerHighest,
        onSurface: colors.onSurface,
        onSurfaceVariant: colors.onSurfaceVariant,
        outlineVariant: colors.outlineVariant,
      ),
      FilesColors value => value.copyWith(
        surface: colors.surface,
        surfaceContainerLow: colors.surfaceContainerLow,
        surfaceContainer: colors.surfaceContainer,
        surfaceContainerHigh: colors.surfaceContainerHigh,
        surfaceContainerHighest: colors.surfaceContainerHighest,
        onSurface: colors.onSurface,
        onSurfaceVariant: colors.onSurfaceVariant,
        outlineVariant: colors.outlineVariant,
        sidebarOnSurfaceVariant: colors.onSurfaceVariant,
      ),
      _ => extension,
    };
  }
}
