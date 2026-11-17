import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_music_page.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMusic(WidgetTester tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: wrapDesktop(const DesktopMusicPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('首页主视觉读当前曲目与曲库计数', (tester) async {
    await pumpMusic(tester);

    expect(find.textContaining('2 TRACKS'), findsOneWidget);
    expect(find.text('Evening Drift'), findsWidgets);
    expect(find.textContaining('Aoi Trio'), findsWidgets);
    expect(find.text('PLAYING NOW'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('曲目页列出曲名、专辑与时长', (tester) async {
    await pumpMusic(tester);
    // 页头的分段控件在树里排在最前；首页曲目区的标题也叫 Tracks。
    await tester.tap(find.text('Tracks').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Slow Harbour'), findsWidgets);
    expect(find.text('Blue Hours'), findsWidgets);
    expect(find.text('4:14'), findsOneWidget);
    expect(find.text('3:18'), findsWidgets);
  });

  testWidgets('搜索按曲名/艺人/专辑过滤', (tester) async {
    await pumpMusic(tester);
    // 页头的分段控件在树里排在最前；首页曲目区的标题也叫 Tracks。
    await tester.tap(find.text('Tracks').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-music-search')),
      'harbour',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Slow Harbour'), findsWidgets);
    expect(find.text('Evening Drift'), findsNothing);
  });

  testWidgets('歌单分页列出歌单名与曲目数', (tester) async {
    await pumpMusic(tester);
    await tester.tap(find.text('Playlists').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Late night'), findsOneWidget);
    expect(find.text('12 songs'), findsOneWidget);
  });

  testWidgets('收藏页只留收藏曲目', (tester) async {
    await pumpMusic(tester);
    await tester.tap(find.text('Favorite').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Evening Drift'), findsWidgets);
    expect(find.text('Slow Harbour'), findsNothing);
  });
}
