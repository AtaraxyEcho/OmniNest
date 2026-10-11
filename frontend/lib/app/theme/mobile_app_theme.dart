import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/feature/command_palette_colors.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';

/// 移动端壳层使用的主题组合器。
///
/// 深色主题保持根主题配置，浅色主题统一各模块的中性表面和正文颜色
/// （取桌面端同一份 AppThemePalette.light，三端不另立移动色板），
/// 模块强调色继续由对应主题扩展维护。
///
/// 例外只有强调族：浅态的 primary/primaryContainer 取环境极性表，因为设计稿
/// 的浅态主行动钮与桌面浅主题的深青不是同一族绿。
abstract final class MobileAppTheme {
  static const GlobalThemeColors _lightColors = AppThemePalette.light;

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
      // 主行动色在移动端单开：样例浅态的 CTA 族是薄荷填充配深墨字
      //（`.login-enter`、`.accent-square-btn`、`.segmented button.active`），
      // 软性动作是 5% 中性叠加配墨字，与桌面共享的那份深青 primary 不同族。
      primary: MobileEnvPalette.light.actionFill,
      onPrimary: MobileEnvPalette.light.actionFillInk,
      primaryContainer: MobileEnvPalette.light.surfaceTint,
      onPrimaryContainer: MobileEnvPalette.light.ink,
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
      // 无壁纸时的画布必须与环境层同色，否则"有壁纸/无壁纸"两态会露出
      // 一层接缝；样例的浅态画布是 #f4f6f3。
      scaffoldBackgroundColor: MobileEnvPalette.light.stageSolid,
      canvasColor: MobileEnvPalette.light.stageSolid,
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
      CommandPaletteColors value => value,
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
