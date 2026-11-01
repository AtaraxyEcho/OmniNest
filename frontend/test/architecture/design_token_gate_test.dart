import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 展示层硬编码颜色闸门。
///
/// 模块自己的主题表（`presentation/theme/*`）与设计稿调色板（`*_palette` /
/// 设计规格）是颜色的合法来源，登记在此；其余展示层源码出现 `Color(0x`
/// 即失败，必须收敛到 AppThemeColors 或所在模块的 ThemeExtension。
const _paletteSources = <String>{
  'lib/features/library/presentation/theme/library_space_colors.dart',
  'lib/features/music/presentation/player/music_immersive_layout_spec.dart',
  'lib/features/music/presentation/player/music_immersive_lyric_spec.dart',
  'lib/features/music/presentation/player/music_immersive_style.dart',
  'lib/features/music/presentation/theme/music_visual_swatches.dart',
  'lib/features/photos/presentation/widgets/frame_palette.dart',
  'lib/features/portal/presentation/theme/weather_atmospheres.dart',
  'lib/features/reader/presentation/theme/reader_space_colors.dart',
  'lib/features/reader/presentation/widgets/reader_reading_palette.dart',
  'lib/features/search/presentation/theme/search_overlay_colors.dart',
  'lib/features/video/presentation/theme/movie_redesign_theme.dart',
};

void main() {
  test('展示层不得散落 Color(0x 字面量', () {
    final violations = <String>[];
    for (final entity in Directory('lib/features').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      if (!path.contains('/presentation/') || _paletteSources.contains(path)) {
        continue;
      }
      final count = 'Color(0x'.allMatches(entity.readAsStringSync()).length;
      if (count > 0) {
        violations.add('$path: $count');
      }
    }
    violations.sort();

    expect(
      violations,
      isEmpty,
      reason:
          '展示层出现硬编码颜色。请收敛到 AppThemeColors 或模块 ThemeExtension；'
          '确属独立调色板/设计规格时登记到 _paletteSources：\n'
          '${violations.join('\n')}',
    );
  });
}
