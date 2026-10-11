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
    // 中性族仍与桌面同值；只有强调族在移动端单开：样例第 3 层的浅态 CTA 是
    // 深绿 `#1e5949` 填充配近白字 `#f8faef`，不再是薄荷填充配深墨字。
    expect(scheme.surfaceContainerHigh, const Color(0xFFDDE1DC));
    expect(scheme.primary, const Color(0xFF1E5949));
    expect(scheme.onPrimary, const Color(0xFFF8FAEF));
    expect(scheme.primaryContainer, const Color(0x0D243E33));
    expect(scheme.onPrimaryContainer, const Color(0xFF17231E));
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
