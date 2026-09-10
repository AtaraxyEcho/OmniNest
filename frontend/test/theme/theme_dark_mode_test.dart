import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';

void main() {
  group('应用主题', () {
    test('浅色与深色主题使用独立表面和正确亮度', () {
      final light = OmniNestTheme.light();
      final dark = OmniNestTheme.dark();

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.colorScheme.surface, isNot(dark.colorScheme.surface));
    });

    test('主题注册全局语义颜色和模块颜色', () {
      final theme = OmniNestTheme.dark();
      final global = theme.extension<GlobalThemeColors>();
      final music = theme.extension<MusicColors>();
      final photos = theme.extension<PhotosColors>();
      final reader = theme.extension<ReaderColors>();

      expect(global, isNotNull);
      expect(global!.surface, AppThemePalette.dark.surface);
      expect(music?.surface, global.surface);
      expect(photos?.surface, global.surface);
      // Reader 自 b019beb 起使用固定纸感色板，不再与全局面同源。
      expect(reader?.surface, const Color(0xFF0F0E0C));
    });

    test('模块颜色从统一调色板派生', () {
      final music = MusicColors.fromGlobal(AppThemePalette.dark);
      final photos = PhotosColors.fromGlobal(AppThemePalette.light);
      final reader = ReaderColors.fromGlobal(AppThemePalette.dark);

      expect(music.surface, AppThemePalette.dark.surface);
      expect(photos.surface, AppThemePalette.light.surface);
      expect(reader.surface, const Color(0xFF0F0E0C));
    });

    test('主题插值同步更新模块扩展', () {
      final light = OmniNestTheme.light();
      final dark = OmniNestTheme.dark();
      final lerped = ThemeData.lerp(light, dark, 1);

      expect(
        lerped.extension<MusicColors>()?.surface,
        dark.extension<MusicColors>()?.surface,
      );
    });

    testWidgets('系统主题模式跟随平台亮度变化', (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: OmniNestTheme.light(),
          darkTheme: OmniNestTheme.dark(),
          themeMode: ThemeMode.system,
          home: Builder(
            builder:
                (context) => Text(
                  Theme.of(context).brightness.name,
                  key: const ValueKey('resolved-brightness'),
                ),
          ),
        ),
      );
      expect(find.text('light'), findsOneWidget);

      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      tester.binding.platformDispatcher.onPlatformBrightnessChanged?.call();
      await tester.pumpAndSettle();

      expect(find.text('dark'), findsOneWidget);
    });
  });
}
