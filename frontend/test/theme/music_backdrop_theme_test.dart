import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/backdrop_translucent_colors.dart';
import 'package:omninest/app/theme/feature/music_backdrop_theme.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

void main() {
  test('浅色 Music 动态背景主题使用烟熏透明表面和浅色文字', () {
    final resolved = MusicBackdropTheme.resolve(
      OmniNestTheme.light(),
      backdropActive: true,
    );
    final colors = resolved.extension<MusicColors>()!;

    expect(resolved.colorScheme.surface, BackdropTranslucentColors.canvas);
    expect(colors.surfaceContainer, BackdropTranslucentColors.surface);
    expect(colors.onSurface, BackdropTranslucentColors.onSurface);
    expect(colors.primary, BackdropTranslucentColors.primary);
    expect(
      ThemeData.estimateBrightnessForColor(colors.onSurface),
      Brightness.light,
    );
  });

  test('浅色 Music 动态背景主题同步改写弹出菜单配色', () {
    final resolved = MusicBackdropTheme.resolve(
      OmniNestTheme.light(),
      backdropActive: true,
    );

    expect(
      resolved.popupMenuTheme.color,
      BackdropTranslucentColors.surfaceHigh,
    );
    expect(
      resolved.popupMenuTheme.textStyle?.color,
      BackdropTranslucentColors.onSurface,
    );
  });

  test('未启用背景和深色主题保持原主题实例', () {
    final light = OmniNestTheme.light();
    final dark = OmniNestTheme.dark();

    expect(
      MusicBackdropTheme.resolve(light, backdropActive: false),
      same(light),
    );
    expect(MusicBackdropTheme.resolve(dark, backdropActive: true), same(dark));
  });

  testWidgets('Music 玻璃面板不会突破主题透明度上限', (tester) async {
    final theme = MusicBackdropTheme.resolve(
      OmniNestTheme.light(),
      backdropActive: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: MusicDeckGlass(
            opacity: 0.80,
            child: SizedBox.square(dimension: 40),
          ),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(MusicDeckGlass),
        matching: find.byType(Material),
      ),
    );

    expect(material.color!.a, BackdropTranslucentColors.surface.a);
    expect(tester.takeException(), isNull);
  });
}
