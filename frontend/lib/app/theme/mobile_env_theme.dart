import 'package:flutter/material.dart';

import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';

/// 移动壳层专属的模块调色板映射。
///
/// 移动端与桌面端样式完全隔离：托管在移动壳层中的 Reader/Files 页面把
/// 各自的主题扩展重绑到环境配色表，模块组件无需感知宿主即可整体换肤；
/// 桌面端继续使用原始模块调色板，互不影响。
///
/// 重绑取值来自 [MobileEnvPalette.of]，因此环境面的明极性会一并传导进
/// 模块扩展（纸面/墨色/强调色角色），不再写死暗值。
abstract final class MobileEnvTheme {
  /// Reader 托管态调色板：纸感主题重绑为环境玻璃族。
  static ReaderColors readerInEnv(ReaderColors source, MobileEnvPalette env) {
    return source.copyWith(
      surface: Colors.transparent,
      surfaceContainerLow: env.surfaceRaised,
      surfaceContainer: env.surfaceGlass,
      surfaceContainerHigh: env.surfaceGlass.withValues(alpha: 0.9),
      surfaceContainerHighest: env.sheetSolid,
      outlineVariant: env.line07,
      primary: env.accent,
      onPrimaryContainer: env.onAccent,
      primaryContainer: env.accentInk.withValues(alpha: 0.14),
      sidebarSelectedBg: env.accent,
      sidebarSelectedBorder: env.accentInk.withValues(alpha: 0.26),
      sidebarSelectedFg: env.onAccent,
      sidebarHoverBg: env.surfaceTint,
      tertiary: env.inkMuted,
      onSurface: env.ink,
      onSurfaceVariant: env.inkMuted,
      coverPlaceholder: env.readerCoverBg,
      reading: env.accentInk,
    );
  }

  /// Files 托管态调色板：工位主题重绑为环境玻璃族 + 六组类型色。
  static FilesColors filesInEnv(FilesColors source, MobileEnvPalette env) {
    return source.copyWith(
      surface: Colors.transparent,
      surfaceContainerLow: env.surfaceRaised,
      surfaceContainer: env.surfaceGlass,
      surfaceContainerHigh: env.surfaceGlass.withValues(alpha: 0.9),
      surfaceContainerHighest: env.sheetSolid,
      onSurface: env.ink,
      onSurfaceVariant: env.inkMuted,
      outlineVariant: env.line07,
      primary: env.accent,
      primaryContainer: env.accentInk.withValues(alpha: 0.14),
      tertiary: env.storageCloud,
      brandTeal: env.accent,
      sidebarSelectedBg: env.accentInk.withValues(alpha: 0.06),
      sidebarSelectedBorder: env.accentInk.withValues(alpha: 0.26),
      sidebarSelectedFg: env.onAccent,
      sidebarOnSurfaceVariant: env.inkMuted,
      sidebarHoverBg: env.surfaceTint,
      storageAccent: env.storageCloud,
      selectedBg: env.accentInk.withValues(alpha: 0.06),
      selectedBorder: env.accentInk.withValues(alpha: 0.26),
    );
  }

  /// 以环境扩展替换当前主题中的模块扩展，返回新的 ThemeData。
  ///
  /// `copyWith(extensions:)` 整体替换扩展集，所以必须带上既有扩展，
  /// 否则会把环境配色表和别的模块调色板一起抹掉。
  static ThemeData withReaderInEnv(BuildContext context) {
    return _rebind(context, (theme, env) {
      final reader = theme.extension<ReaderColors>();
      return reader == null ? null : readerInEnv(reader, env);
    });
  }

  static ThemeData withFilesInEnv(BuildContext context) {
    return _rebind(context, (theme, env) {
      final files = theme.extension<FilesColors>();
      return files == null ? null : filesInEnv(files, env);
    });
  }

  static ThemeData _rebind(
    BuildContext context,
    ThemeExtension<dynamic>? Function(ThemeData, MobileEnvPalette) build,
  ) {
    final theme = Theme.of(context);
    final replacement = build(theme, MobileEnvPalette.of(context));
    if (replacement == null) {
      return theme;
    }
    return theme.copyWith(
      extensions: [...theme.extensions.values, replacement],
    );
  }
}
