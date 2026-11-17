import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 来源徽章配色契约：常规徽章为胶囊描边形态——中性微底 + 平台色描边
/// 与平台色文字；覆盖形态沿用近实底表面 + 平台色文字描边。
void main() {
  Future<void> pumpBadge(
    WidgetTester tester,
    MusicPlatform platform,
    Brightness brightness, {
    bool overlay = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme:
            brightness == Brightness.light
                ? OmniNestTheme.light()
                : OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Center(
            child: MusicDeckSourceBadge(platform: platform, overlay: overlay),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Color badgeTextColor(WidgetTester tester) {
    final text = tester.widget<Text>(find.byType(Text));
    return text.style!.color!;
  }

  BoxDecoration badgeDecoration(WidgetTester tester) {
    final decorated = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    return decorated.decoration as BoxDecoration;
  }

  Color expectedBadgeColor(MusicPlatform platform, bool light) {
    return switch (platform) {
      MusicPlatform.local =>
        light ? const Color(0xFF58605B) : const Color(0xFFC4CCC8),
      MusicPlatform.netease =>
        light ? const Color(0xFF9A3037) : const Color(0xFFF28C8C),
    };
  }

  void expectRegularBadge(
    WidgetTester tester,
    MusicPlatform platform,
    Brightness brightness,
  ) {
    final color = expectedBadgeColor(platform, brightness == Brightness.light);
    final decoration = badgeDecoration(tester);
    expect(decoration.borderRadius, BorderRadius.circular(999));
    expect(decoration.border, Border.all(color: color.withValues(alpha: 0.55)));
    expect(badgeTextColor(tester), color);
  }

  testWidgets('浅色主题：常规徽章为胶囊描边 + 平台色文字', (tester) async {
    for (final platform in MusicPlatform.values) {
      await pumpBadge(tester, platform, Brightness.light);
      expectRegularBadge(tester, platform, Brightness.light);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色主题：常规徽章为胶囊描边 + 平台色文字', (tester) async {
    for (final platform in MusicPlatform.values) {
      await pumpBadge(tester, platform, Brightness.dark);
      expectRegularBadge(tester, platform, Brightness.dark);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('覆盖形态保持近实底表面与平台色文字', (tester) async {
    await pumpBadge(
      tester,
      MusicPlatform.local,
      Brightness.dark,
      overlay: true,
    );
    final decoration = badgeDecoration(tester);
    expect(decoration.borderRadius, BorderRadius.circular(4));
    expect(decoration.border, isNotNull);
    expect(badgeTextColor(tester), const Color(0xFFC4CCC8));
    expect(tester.takeException(), isNull);
  });
}
