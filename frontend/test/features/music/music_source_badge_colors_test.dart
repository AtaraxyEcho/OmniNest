import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 来源徽章配色契约：常规徽章为平台色实底 + 按亮度反差的前景文字，
/// 保证在低 alpha 玻璃卡与浅色壁纸上可读；覆盖形态沿用近实底表面
/// + 平台色文字描边。
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

  Color badgeFillColor(WidgetTester tester) {
    final decorated = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    return (decorated.decoration as BoxDecoration).color!;
  }

  testWidgets('浅色主题：平台色实底与白色前景保证对比度', (tester) async {
    await pumpBadge(tester, MusicPlatform.local, Brightness.light);
    expect(badgeFillColor(tester), const Color(0xFF356F8A));
    expect(badgeTextColor(tester), Colors.white);

    await pumpBadge(tester, MusicPlatform.netease, Brightness.light);
    expect(badgeFillColor(tester), const Color(0xFF9A3037));
    expect(badgeTextColor(tester), Colors.white);

    await pumpBadge(tester, MusicPlatform.qq, Brightness.light);
    expect(badgeFillColor(tester), const Color(0xFF735A08));
    expect(badgeTextColor(tester), Colors.white);
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色主题：亮色平台底配深色前景', (tester) async {
    await pumpBadge(tester, MusicPlatform.local, Brightness.dark);
    expect(badgeFillColor(tester), const Color(0xFF85D7DE));
    expect(badgeTextColor(tester), const Color(0xFF12211E));
    expect(tester.takeException(), isNull);
  });
}
