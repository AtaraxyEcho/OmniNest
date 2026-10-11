import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  test('legacy theme index migrates to a stable palette id', () {
    final settings = ReaderViewSettings.fromJson(const {
      'version': 3,
      'themeIndex': 0,
    });

    expect(settings.paletteId, ReaderReadingPalette.light.id);
    expect(settings.themeIndex, 0);
    expect(settings.toJson()['version'], 5);
    expect(settings.toJson()['paletteId'], 'light');
  });

  test('unknown palette falls back to dark', () {
    final settings = ReaderViewSettings.fromJson(const {
      'version': 4,
      'paletteId': 'missing',
    });

    expect(settings.paletteId, ReaderReadingPalette.dark.id);
    expect(settings.isDark, isTrue);
  });

  test('control surface is opaque in every palette', () {
    // 面板框、顶/底栏和弹出菜单直接压在正文上：半透明的控制层会让正文从控件
    // 底下透出来，而 .withValues(alpha: .97) 覆盖的是 alpha 本身，会把 8% 白
    // 变成 97% 白。
    for (final palette in ReaderReadingPalette.values) {
      expect(palette.controlSurface.a, 1.0, reason: '${palette.id} 的控制层必须是实底');
    }
  });
}
