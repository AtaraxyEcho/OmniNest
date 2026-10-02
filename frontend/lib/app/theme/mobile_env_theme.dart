import 'package:flutter/material.dart';

import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';

/// 移动壳层专属的模块调色板映射。
///
/// 移动端与桌面端样式完全隔离：托管在移动壳层中的 Reader/Files 页面把
/// 各自的主题扩展重绑到环境调色板（MobileEnvColors），模块组件无需
/// 感知宿主即可整体换肤；桌面端继续使用原始模块调色板，互不影响。
abstract final class MobileEnvTheme {
  /// Reader 托管态调色板：纸感主题重绑为环境暗色玻璃族。
  static ReaderColors readerInEnv(ReaderColors source) {
    return source.copyWith(
      surface: Colors.transparent,
      surfaceContainerLow: const Color(0x8F111816),
      surfaceContainer: const Color(0xB8121918),
      surfaceContainerHigh: const Color(0xE6121918),
      surfaceContainerHighest: MobileEnvColors.sheetSolid,
      outlineVariant: const Color(0x12FFFFFF),
      primary: MobileEnvColors.accent,
      onPrimaryContainer: MobileEnvColors.onAccent,
      primaryContainer: const Color(0x24D5F17D),
      sidebarSelectedBg: MobileEnvColors.accent,
      sidebarSelectedBorder: const Color(0x42D5F17D),
      sidebarSelectedFg: MobileEnvColors.onAccent,
      sidebarHoverBg: const Color(0x0AFFFFFF),
      tertiary: MobileEnvColors.inkMuted,
      onSurface: MobileEnvColors.ink,
      onSurfaceVariant: MobileEnvColors.inkMuted,
      coverPlaceholder: MobileEnvColors.readerCoverBg,
      reading: MobileEnvColors.accent,
    );
  }

  /// Files 托管态调色板：工位主题重绑为环境暗色玻璃族 + 六组类型色。
  static FilesColors filesInEnv(FilesColors source) {
    return source.copyWith(
      surface: Colors.transparent,
      surfaceContainerLow: const Color(0x8F111816),
      surfaceContainer: const Color(0xB8121918),
      surfaceContainerHigh: const Color(0xE6121918),
      surfaceContainerHighest: MobileEnvColors.sheetSolid,
      onSurface: MobileEnvColors.ink,
      onSurfaceVariant: MobileEnvColors.inkMuted,
      outlineVariant: const Color(0x12FFFFFF),
      primary: MobileEnvColors.accent,
      primaryContainer: const Color(0x24D5F17D),
      tertiary: MobileEnvColors.storageCloud,
      brandTeal: MobileEnvColors.accent,
      sidebarSelectedBg: const Color(0x0FD5F17D),
      sidebarSelectedBorder: const Color(0x42D5F17D),
      sidebarSelectedFg: MobileEnvColors.onAccent,
      sidebarOnSurfaceVariant: MobileEnvColors.inkMuted,
      sidebarHoverBg: const Color(0x0AFFFFFF),
      storageAccent: MobileEnvColors.storageCloud,
      selectedBg: const Color(0x0FD5F17D),
      selectedBorder: const Color(0x42D5F17D),
    );
  }

  /// 以环境扩展替换当前主题中的模块扩展，返回新的 ThemeData。
  static ThemeData withReaderInEnv(BuildContext context) {
    final theme = Theme.of(context);
    final reader = theme.extension<ReaderColors>();
    if (reader == null) {
      return theme;
    }
    return theme.copyWith(extensions: {readerInEnv(reader)});
  }

  static ThemeData withFilesInEnv(BuildContext context) {
    final theme = Theme.of(context);
    final files = theme.extension<FilesColors>();
    if (files == null) {
      return theme;
    }
    return theme.copyWith(extensions: {filesInEnv(files)});
  }
}
