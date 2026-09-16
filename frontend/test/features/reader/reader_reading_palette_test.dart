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
}
