import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/app/theme/mobile_app_theme.dart';

void main() {
  test('移动端深色主题保持根主题配置', () {
    final source = OmniNestTheme.dark();

    expect(MobileAppTheme.resolve(source), same(source));
  });

  test('移动端浅色主题统一模块表面和正文颜色（与桌面同色板）', () {
    final source = OmniNestTheme.light();
    final resolved = MobileAppTheme.resolve(source);
    final scheme = resolved.colorScheme;

    expect(scheme.surface, const Color(0xFFF7F8F6));
    expect(scheme.onSurface, const Color(0xFF1A1D1B));
    expect(scheme.primary, const Color(0xFF0B6B61));
    expect(resolved.textTheme.bodyMedium!.color, scheme.onSurface);
    expect(resolved.cardTheme.color, scheme.surfaceContainerLow);
    expect(resolved.extension<FilesColors>()!.surface, scheme.surface);
    expect(resolved.extension<PhotosColors>()!.onSurface, scheme.onSurface);
    expect(
      resolved.extension<ReaderColors>()!.onSurfaceVariant,
      scheme.onSurfaceVariant,
    );
    expect(
      resolved.extension<VideoColors>()!.surfaceContainerHigh,
      scheme.surfaceContainerHigh,
    );
    expect(
      resolved.extension<MusicColors>(),
      same(source.extension<MusicColors>()),
    );
  });
}
