import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/feature/portal_mobile_theme.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_create_playlist_dialog.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_visual_widgets.dart';

void main() {
  testWidgets('Portal 调色板跟随根主题明暗', (tester) async {
    PortalVisualPalette? lightPalette;
    PortalVisualPalette? lightBackdropPalette;
    PortalVisualPalette? darkPalette;
    PortalVisualPalette? darkBackdropPalette;

    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey<String>('light-theme'),
        theme: OmniNestTheme.light(),
        home: Builder(
          builder: (context) {
            lightPalette = PortalVisualPalette.of(context);
            lightBackdropPalette = PortalVisualPalette.of(
              context,
              backdropActive: true,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey<String>('dark-theme'),
        theme: OmniNestTheme.dark(),
        home: Builder(
          builder: (context) {
            darkPalette = PortalVisualPalette.of(context);
            darkBackdropPalette = PortalVisualPalette.of(
              context,
              backdropActive: true,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(lightPalette, isNotNull);
    expect(lightBackdropPalette, isNotNull);
    expect(darkPalette, isNotNull);
    expect(lightPalette!.background, isNot(darkPalette!.background));
    expect(
      ThemeData.estimateBrightnessForColor(lightPalette!.background),
      Brightness.light,
    );
    expect(
      ThemeData.estimateBrightnessForColor(darkPalette!.background),
      Brightness.dark,
    );
    expect(lightPalette!.surface.a, lessThan(1));
    expect(lightPalette!.surface.a, inInclusiveRange(0.46, 0.50));
    expect(lightPalette!.surfaceStrong.a, inInclusiveRange(0.60, 0.64));
    expect(lightPalette!.surface.a, lessThan(darkPalette!.surface.a));
    expect(lightPalette!.clearStructuralSurfaces, isTrue);
    expect(lightPalette!.structuralSurface(), Colors.transparent);
    expect(
      lightPalette!.structuralStrongSurface(alpha: 0.80),
      Colors.transparent,
    );
    expect(darkPalette!.clearStructuralSurfaces, isFalse);
    expect(darkPalette!.structuralSurface(), darkPalette!.surface);
    // 深色无壁纸回落常规不透明暗面（避免烟熏色板压近黑舞台的整体灰暗），
    // 有壁纸时保持烟熏玻璃色板。
    expect(darkPalette!.surface.a, 1.0);
    expect(darkPalette!.background, isNot(const Color(0xFF071016)));
    expect(darkBackdropPalette!.background, const Color(0xFF071016));
    expect(darkBackdropPalette!.surface.a, closeTo(0.65, 0.01));
    expect(darkPalette!.text, OmniNestTheme.dark().colorScheme.onSurface);
    expect(
      ThemeData.estimateBrightnessForColor(darkBackdropPalette!.text),
      Brightness.light,
    );
    expect(lightBackdropPalette!.clearStructuralSurfaces, isFalse);
    expect(lightBackdropPalette!.surface.a, inInclusiveRange(0.28, 0.32));
    expect(
      lightBackdropPalette!
          .structuralSurface(
            alpha: lightBackdropPalette!.lightweightSurfaceAlpha,
          )
          .a,
      inInclusiveRange(0.16, 0.20),
    );
    expect(
      lightBackdropPalette!.structuralStrongSurface(alpha: 0.80).a,
      lessThanOrEqualTo(0.46),
    );
    expect(
      ThemeData.estimateBrightnessForColor(lightBackdropPalette!.text),
      Brightness.light,
    );
    expect(
      lightPalette!.surface.computeLuminance(),
      lessThan(
        OmniNestTheme.light().colorScheme.surfaceContainerLow
            .computeLuminance(),
      ),
    );
  });

  testWidgets('底部内容带使用单层网络封面', (tester) async {
    const palette = PortalVisualPalette(
      background: Color(0xFF101010),
      surface: Color(0xCC202020),
      surfaceStrong: Color(0xDD303030),
      clearStructuralSurfaces: false,
      lightweightSurfaceAlpha: 0.36,
      structuralAlphaCeiling: null,
      text: Colors.white,
      muted: Color(0xB3FFFFFF),
      accent: Color(0xFF80CBC4),
      accentAlt: Color(0xFFFFCC80),
      glow: Color(0x3380CBC4),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 120,
              child: PortalGradientCover(
                palette: palette,
                title: '标题',
                subtitle: '副标题',
                imageUrl: 'https://example.invalid/cover.jpg',
                directImage: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('移动端 Portal 动态背景主题使用烟熏透明表面', (tester) async {
    ThemeData? resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        home: Builder(
          builder: (context) {
            resolved = PortalMobileTheme.resolve(context, backdropActive: true);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolved, isNotNull);
    expect(
      resolved!.colorScheme.surfaceContainerLow.a,
      inInclusiveRange(0.30, 0.34),
    );
    expect(resolved!.colorScheme.surface.a, 0);
    expect(
      ThemeData.estimateBrightnessForColor(resolved!.colorScheme.onSurface),
      Brightness.light,
    );
  });

  testWidgets('Music 浅色主题不再使用深紫色主色', (tester) async {
    MusicColors? colors;
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        home: Builder(
          builder: (context) {
            colors = context.musicColors;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(colors, isNotNull);
    expect(colors!.primary, const Color(0xFF176B72));
  });

  for (final brightness in Brightness.values) {
    testWidgets('歌单对话框继承${brightness.name}根主题', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme:
              brightness == Brightness.light
                  ? OmniNestTheme.light()
                  : OmniNestTheme.dark(),
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showDialog<MusicDeckPlaylistDraft>(
                        context: context,
                        builder:
                            (context) => const MusicDeckCreatePlaylistDialog(),
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final fieldContext = tester.element(find.byType(TextField).first);
      expect(Theme.of(fieldContext).brightness, brightness);
      expect(tester.takeException(), isNull);
    });
  }
}
