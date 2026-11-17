import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';

void main() {
  group('Music theme tokens', () {
    test('MusicColors.fromGlobal uses system token surface colors', () {
      final base = AppThemePalette.dark;
      final musicColors = MusicColors.fromGlobal(base);
      expect(musicColors.surface, equals(base.surface));
      expect(musicColors.primary, equals(base.primary));
      expect(musicColors.onSurface, equals(base.onSurface));
    });

    test('浅色 Music 表面使用低饱和度主题色调而不是纯白', () {
      final base = AppThemePalette.light;
      final musicColors = MusicColors.fromGlobal(base);
      expect(musicColors.surface, isNot(base.surface));
      expect(musicColors.background, isNot(base.surfaceContainerLowest));
      expect(musicColors.surfaceContainer, isNot(base.surfaceContainer));
      expect(
        musicColors.surfaceContainer.computeLuminance(),
        lessThan(base.surfaceContainer.computeLuminance()),
      );
      expect(
        ThemeData.estimateBrightnessForColor(musicColors.surfaceContainer),
        Brightness.light,
      );
    });

    test('copyWith preserves existing fields', () {
      final base = AppThemePalette.dark;
      final musicColors = MusicColors.fromGlobal(base);
      final modified = musicColors.copyWith(cardBorderRadius: 20);
      expect(modified.cardBorderRadius, 20);
      expect(modified.surface, musicColors.surface);
    });

    test('lerp between light and dark system tokens interpolates', () {
      final dark = MusicColors.fromGlobal(AppThemePalette.dark);
      final light = MusicColors.fromGlobal(AppThemePalette.light);
      final result = dark.lerp(light, 0.5);
      expect(result.surface, isNot(dark.surface));
      expect(result.surface, isNot(light.surface));
    });

    test('lerp at t=0 returns source', () {
      final dark = MusicColors.fromGlobal(AppThemePalette.dark);
      final light = MusicColors.fromGlobal(AppThemePalette.light);
      final result = dark.lerp(light, 0.0);
      expect(result.surface, dark.surface);
    });

    test('lerp at t=1 returns target', () {
      final dark = MusicColors.fromGlobal(AppThemePalette.dark);
      final light = MusicColors.fromGlobal(AppThemePalette.light);
      final result = dark.lerp(light, 1.0);
      expect(result.surface, light.surface);
    });
  });
}
