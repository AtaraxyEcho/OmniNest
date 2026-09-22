// Dart 脚本：将硬编码颜色替换为 ThemeExtension 访问
// 用法: dart run tool/theme_migrator.dart

import 'dart:convert';
import 'dart:io';

void main() {
  final base = Directory('lib/features');

  // ─── 替换规则 ───
  // Video 模块
  final videoReplacements = <String, String>{
    'movieSurfaceContainerHighest':
        'context.videoColors.surfaceContainerHighest',
    'movieSurfaceContainerHigh': 'context.videoColors.surfaceContainerHigh',
    'movieSurfaceContainerLow': 'context.videoColors.surfaceContainerLow',
    'movieSurfaceContainer': 'context.videoColors.surfaceContainer',
    'movieSurface': 'context.videoColors.surface',
    'moviePrimaryContainer': 'context.videoColors.primaryContainer',
    'moviePrimary': 'context.videoColors.primary',
    'movieOnPrimaryContainer': 'context.videoColors.onPrimaryContainer',
    'movieOnPrimary': 'context.videoColors.onPrimary',
    'movieOnSurfaceVariant': 'context.videoColors.onSurfaceVariant',
    'movieOnSurface': 'context.videoColors.onSurface',
    'movieTertiary': 'context.videoColors.tertiary',
    'movieOutlineVariant': 'context.videoColors.outlineVariant',
    'moviePlayerBarBg': 'context.videoColors.playerBarBg',
    'movieSubtitleBg': 'context.videoColors.subtitleBg',
  };

  // Reader 模块
  final readerReplacements = <String, String>{
    'readerSurfaceContainerHighest':
        'context.readerColors.surfaceContainerHighest',
    'readerSurfaceContainerHigh': 'context.readerColors.surfaceContainerHigh',
    'readerSurfaceContainerLow': 'context.readerColors.surfaceContainerLow',
    'readerSurfaceContainer': 'context.readerColors.surfaceContainer',
    'readerSurface': 'context.readerColors.surface',
    'readerPrimaryContainer': 'context.readerColors.primaryContainer',
    'readerOnPrimaryContainer': 'context.readerColors.onPrimaryContainer',
    'readerOnSurfaceVariant': 'context.readerColors.onSurfaceVariant',
    'readerOnSurface': 'context.readerColors.onSurface',
    'readerOutlineVariant': 'context.readerColors.outlineVariant',
    'readerTertiary': 'context.readerColors.tertiary',
    'readerSuccess': 'context.readerColors.success',
    'readerWarning': 'context.readerColors.warning',
    'readerDanger': 'context.readerColors.danger',
  };

  // Photos 模块
  final photosReplacements = <String, String>{
    'photosSurfaceContainerHighest':
        'context.photosColors.surfaceContainerHighest',
    'photosSurfaceContainerHigh': 'context.photosColors.surfaceContainerHigh',
    'photosSurfaceContainerLow': 'context.photosColors.surfaceContainerLow',
    'photosSurfaceContainer': 'context.photosColors.surfaceContainer',
    'photosSurface': 'context.photosColors.surface',
    'photosPrimaryContainer': 'context.photosColors.primaryContainer',
    'photosOnPrimaryContainer': 'context.photosColors.onPrimaryContainer',
    'photosOnSurfaceVariant': 'context.photosColors.onSurfaceVariant',
    'photosOnSurface': 'context.photosColors.onSurface',
    'photosOutlineVariant': 'context.photosColors.outlineVariant',
    'photosTertiary': 'context.photosColors.tertiary',
    'photosSuccess': 'context.photosColors.success',
    'photosDanger': 'context.photosColors.danger',
    'photosTimelineDivider': 'context.photosColors.timelineDivider',
    'photosAlbumCardShadow': 'context.photosColors.albumCardShadow',
  };

  // Music 模块
  final musicReplacements = <String, String>{
    'MusicColors.surfaceContainerHigh':
        'context.musicColors.surfaceContainerHigh',
    'MusicColors.surfaceContainer': 'context.musicColors.surfaceContainer',
    'MusicColors.background': 'context.musicColors.background',
    'MusicColors.surface': 'context.musicColors.surface',
    'MusicColors.primary': 'context.musicColors.primary',
    'MusicColors.onSurfaceVariant': 'context.musicColors.onSurfaceVariant',
    'MusicColors.onSurface': 'context.musicColors.onSurface',
    'MusicColors.outline': 'context.musicColors.outline',
    'MusicColors.brandRed': 'context.musicColors.brandRed',
  };

  // ─── 模块 → 文件映射 ───
  final moduleConfigs = <String, Map<String, String>>{
    'video': videoReplacements,
    'reader': readerReplacements,
    'photos': photosReplacements,
    'music': musicReplacements,
  };

  // ─── 排除的文件 ───
  final excludeFiles = {
    'movie_shell.dart', // 定义颜色常量
    'movie_styles.dart', // 顶层函数，无 context
    'reader_styles.dart', // 定义颜色常量
    'photos_styles.dart', // 定义颜色常量
    'music_colors.dart', // 定义颜色常量
    'movie_theme_colors.dart',
    'reader_theme_colors.dart',
    'photos_theme_colors.dart',
    'music_theme_colors.dart',
    'viz_mock_data.dart',
    'ink_wash_noise.dart',
    'ink_wash_scene.dart',
    'ink_wash_viz.dart',
    'viz_album_wall.dart',
    'viz_paper_fold.dart',
    'music_viz_ink_test_page.dart',
    'music_viz_test_page.dart',
    'music_viz_paper_test_page.dart',
  };

  // ─── 模块对应的 import 路径 ───
  final moduleImports = <String, String>{
    'video': "import 'package:omninest/app/theme/feature/video_colors.dart';",
    'reader': "import 'package:omninest/app/theme/feature/reader_colors.dart';",
    'photos': "import 'package:omninest/app/theme/feature/photos_colors.dart';",
    'music': "import 'package:omninest/app/theme/feature/music_colors.dart';",
  };

  var totalFiles = 0;

  for (final entry in moduleConfigs.entries) {
    final moduleName = entry.key;
    final replacements = entry.value;
    final importLine = moduleImports[moduleName]!;

    final moduleDir = Directory('${base.path}/$moduleName/presentation');
    if (!moduleDir.existsSync()) continue;

    final files =
        moduleDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !excludeFiles.any((ex) => f.path.endsWith(ex)))
            .toList();

    for (final file in files) {
      var content = file.readAsStringSync();
      var changed = false;

      // 第一轮：替换颜色常量（最长匹配优先）
      final sortedKeys =
          replacements.keys.toList()
            ..sort((a, b) => b.length.compareTo(a.length));

      for (final key in sortedKeys) {
        if (content.contains(key)) {
          // 避免 context.context. 双重问题
          content = content.replaceAll(key, replacements[key]!);
          changed = true;
        }
      }

      if (!changed) continue;

      // 第二轮：修复 context.context. 双重问题
      content = content.replaceAll('context.context.', 'context.');

      // 第三轮：移除包含 context.xxxColors 的 const 构造器中的 const
      final lines = content.split('\n');
      final newLines = <String>[];

      for (var i = 0; i < lines.length; i++) {
        var line = lines[i];

        // 检查这行是否有 const（包括行中间的 const，如 "icon: const Icon("）
        if (line.contains(RegExp(r'\bconst\s'))) {
          var hasThemeColor = false;
          for (var j = i; j < i + 15 && j < lines.length; j++) {
            if (lines[j].contains(
              RegExp(
                r'context\.(musicColors|videoColors|readerColors|photosColors)',
              ),
            )) {
              hasThemeColor = true;
              break;
            }
            // 遇到闭合括号停止
            if (RegExp(r'^\s*\);').hasMatch(lines[j])) break;
          }
          if (hasThemeColor) {
            // 移除行中间的 const
            line = line.replaceFirst(RegExp(r'\bconst\s'), '');
          }
        }
        newLines.add(line);
      }

      content = newLines.join('\n');

      // 第四轮：添加 import（如果不存在）
      if (!content.contains(importLine)) {
        // 在第一个 import 之后插入
        final firstImport = content.indexOf("import 'package:");
        if (firstImport != -1) {
          final endOfLine = content.indexOf('\n', firstImport);
          content =
              '${content.substring(0, endOfLine + 1)}$importLine\n${content.substring(endOfLine + 1)}';
        }
      }

      // 写入文件（UTF-8 无 BOM）
      file.writeAsStringSync(content, encoding: utf8);
      totalFiles++;
      // ignore: avoid_print
      print('Updated: ${file.path.split('/').last}');
    }
  }

  // ignore: avoid_print
  print('\nDone: $totalFiles files updated');
}
