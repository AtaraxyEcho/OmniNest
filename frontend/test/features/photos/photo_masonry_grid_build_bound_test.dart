import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_masonry_grid.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

/// 网格构建量必须与列表规模无关。
///
/// 起因：分段改成跟手分页后，邻页在**拖动起手**时才第一次构建。照片段的邻页
/// 就是这张瀑布流网格，所以它一次构建多少瓦片，直接决定起手那一帧会不会掉帧。
/// 真机验不了这一条（开发库没有素材），于是把它换成一个确定性的形状断言：
/// 60 条与 600 条在同一视口里构建的瓦片数必须相同。
///
/// 用计数而不是耗时做断言：时间预算在 widget 测试里会随机器负载漂（那正是
/// photo_slideshow_page_test 假红的成因），计数不会。
void main() {
  List<PhotoItem> photos(int count) => [
    for (var i = 0; i < count; i++)
      PhotoItem(
        id: 'p$i',
        fileNodeId: 'f$i',
        title: 'Photo $i',
        format: 'JPEG',
        // coverUrl 留空：瓦片走占位分支，不触发网络解码，断言只测构建规模。
        fileSize: 1024,
        metadataStatus: 'READY',
        favorite: false,
        createdAt: DateTime(2024, 11, 12),
      ),
  ];

  Future<int> mountedTiles(WidgetTester tester, List<PhotoItem> items) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: SizedBox(
              width: 411,
              height: 914,
              child: FrameMasonryGrid(photos: items, onOpenPhoto: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return find.byType(PhotoGridTile).evaluate().length;
  }

  testWidgets('首屏构建的瓦片数不随列表规模增长', (tester) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final small = await mountedTiles(tester, photos(60));
    final large = await mountedTiles(tester, photos(600));

    expect(small, greaterThan(0), reason: '网格没构建任何瓦片，断言就失去意义');
    expect(
      large,
      equals(small),
      reason:
          '视口不变时 60 条构建 $small 个瓦片、600 条构建 $large 个：'
          '构建量随列表线性增长，分页起手那一帧就会掉帧',
    );
    expect(large, lessThan(120), reason: '视口 + 预取窗口应当远小于整表，否则裁剪没生效');
  });

  testWidgets('滚到表尾时构建量仍然是有界的', (tester) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final items = photos(600);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: SizedBox(
              width: 411,
              height: 914,
              child: FrameMasonryGrid(photos: items, onOpenPhoto: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 拖到接近表尾：瀑布流的分帧卸载（hysteresis）会让滞后集短暂多留几个瓦片，
    // 所以这里断"有界"而不是"等于首屏数"。
    final scrollable = find.byType(CustomScrollView);
    for (var i = 0; i < 12; i++) {
      await tester.drag(scrollable, const Offset(0, -900));
      await tester.pump();
    }
    await tester.pump();

    final built = find.byType(PhotoGridTile).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(160), reason: '表尾仍在构建整表，说明按视口裁剪没生效');
    expect(built, lessThan(items.length), reason: '构建数应小于总条目数，否则等于没有裁剪');
  });
}
