import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_photos_page.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPhotos(
    WidgetTester tester, {
    bool empty = false,
    List<Override> extra = const <Override>[],
  }) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [...desktopSeedOverrides(empty: empty), ...extra],
        child: wrapDesktop(const DesktopPhotosPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('图库按日分组并铺成等高一排', (tester) async {
    await pumpPhotos(tester);

    expect(find.textContaining('4382 PHOTOS'), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Favorites'), findsWidgets);
    expect(find.text('Albums'), findsWidgets);

    // 七张种子照片都没有拍摄时间，落到同一个「未知日期」分组里。
    expect(find.textContaining('7 items'), findsOneWidget);
    expect(find.text('Frame 1'), findsOneWidget);
  });

  testWidgets('Ctrl 点选进入选中态，再点第二张是切换而不是打开', (tester) async {
    await pumpPhotos(tester);

    // Ctrl + 点击第一张：进选中集（不跳大图）。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Frame 1'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('1 selected'), findsOneWidget);

    // 选中态下普通点击也是切换：不然一点就跳走，第二张永远选不中。
    await tester.tap(find.text('Frame 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('2 selected'), findsOneWidget);

    // 选中项外围有一圈主色（样例 `0 0 0 3px`）。
    final shadows =
        tester
            .widgetList<AnimatedContainer>(
              find.ancestor(
                of: find.text('Frame 1'),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .map((widget) => (widget.decoration as BoxDecoration?)?.boxShadow)
            .whereType<List<BoxShadow>>()
            .expand((value) => value)
            .toList();
    expect(shadows, isNotEmpty);

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('1 selected'), findsNothing);
    expect(find.text('2 selected'), findsNothing);
  });

  testWidgets('收藏页只列收藏的照片', (tester) async {
    await pumpPhotos(tester);
    await tester.tap(find.text('Favorites').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Golden hour'), findsWidgets);
    expect(find.text('Frame 1'), findsNothing);
  });

  testWidgets('地点按 GPS 聚合，卡片给出地名与张数', (tester) async {
    await pumpPhotos(
      tester,
      extra: [
        photoLocationGroupsProvider.overrideWith(
          (ref) async => [
            PhotoGroup(
              groupKey: 'Kyoto',
              photoCount: 12,
              photos: [seededPhoto],
            ),
          ],
        ),
      ],
    );

    await tester.tap(find.text('Places').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    // 地点列表与下方选中地点的标题各出现一次。
    expect(find.text('Kyoto'), findsWidgets);
    expect(find.text('12 photos'), findsWidgets);
  });

  testWidgets('回收站分区给出保留期说明', (tester) async {
    await pumpPhotos(tester);

    await tester.tap(find.text('Trash').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(
      find.textContaining('kept until you delete them permanently'),
      findsWidgets,
    );
  });

  testWidgets('相册页列出相册名与张数', (tester) async {
    await pumpPhotos(tester);
    await tester.tap(find.text('Albums').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Golden hour'), findsOneWidget);
    expect(find.text('42 items'), findsOneWidget);
  });

  testWidgets('空库时落到空态', (tester) async {
    await pumpPhotos(tester, empty: true);

    expect(find.text('No photos yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
