import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_music_page.dart';
import 'package:omninest/app/desktop/widgets/desktop_tilt.dart';

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
    // 原型 `Music.tsx`：Playing from {album}。
    expect(find.text('PLAYING FROM BLUE HOURS'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    // v16 起音乐页头与影视/照片/阅读一致改为固定分类栏（DesktopStickySliver），
    // 滚动时只保留 26px 玻璃页头，不再把整块标题压住内容。
    expect(find.byType(SliverPersistentHeader), findsOneWidget);
  });

  testWidgets('专辑分区使用音乐文案且卡片不带指针柔光', (tester) async {
    await pumpMusic(tester);

    expect(find.text('Albums'), findsWidgets);
    expect(find.text('Playlists'), findsWidgets);
    expect(find.text('Favorites'), findsWidgets);
    // 音乐专辑误用照片模块的「相册」文案曾让页面看起来多出一个相册栏。
    expect(find.text('相册'), findsNothing);
    // 样例 `.album` 没有 `.tilt/.shine`，卡片 hover 不应出现光晕/大投影。
    expect(find.byType(DesktopTilt), findsNothing);
  });

  testWidgets('专辑分区点入后显示专辑曲目集合页', (tester) async {
    await pumpMusic(tester);
    await tester.tap(find.text('Albums').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-music-album-al-1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(
      find.byKey(const ValueKey<String>('desktop-music-album-detail-al-1')),
      findsOneWidget,
    );
    expect(find.text('Blue Hours'), findsWidgets);
    expect(find.text('Evening Drift'), findsOneWidget);
    expect(find.text('Slow Harbour'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
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
    await tester.tap(find.text('Favorites').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Evening Drift'), findsWidgets);
    expect(find.text('Slow Harbour'), findsNothing);
  });
}
