import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_resolver.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

import 'geometry_fixtures.dart';

void main() {
  group('ReaderPositionResolver（方案 §16-§17/§110/§113）', () {
    test(
      'same layout + same offset = same PositionSnapshot，且不受 Live 几何后续变化影响',
      () {
        final entry = textEntry(id: 'c1', heights: const [100, 200, 300]);
        final geometry = snapshotFor([entry]);
        final layout = layoutFor(geometry);
        const resolver = ReaderPositionResolver();

        final first =
            resolver.resolve(
              scrollOffset: 136,
              layout: layout,
              transactionId: 7,
            )!;
        final second =
            resolver.resolve(
              scrollOffset: 136,
              layout: layout,
              transactionId: 7,
            )!;
        expect(first, second);

        // 模拟后台测高替换 Live 几何：事务冻结布局的解析结果必须不变，
        // 且新布局下的解析结果确实不同（排除解析器缓存假阳性）。
        final mutatedGeometry = snapshotFor([
          textEntry(id: 'c1', heights: const [150, 300, 450]),
        ]);
        final mutatedLayout = ReaderLayoutSnapshot(
          geometry: mutatedGeometry,
          viewport: layout.viewport,
          windowRevision: layout.windowRevision,
        );
        final mutated =
            resolver.resolve(
              scrollOffset: 136,
              layout: mutatedLayout,
              transactionId: 7,
            )!;
        final frozenAgain =
            resolver.resolve(
              scrollOffset: 136,
              layout: layout,
              transactionId: 7,
            )!;
        expect(frozenAgain, first);
        expect(mutated, isNot(first));
      },
    );

    test('文本块：块索引、块内比例与 charOffset 一次到位', () {
      final entry = textEntry(id: 'c1', heights: const [100, 200, 300]);
      final layout = layoutFor(snapshotFor([entry]));
      const resolver = ReaderPositionResolver();

      // contentY = offset(136) + anchorY(50) = 186 = 章头(36) + 章体 150。
      final snapshot =
          resolver.resolve(
            scrollOffset: 136,
            layout: layout,
            transactionId: 1,
          )!;
      expect(snapshot.chapterId, 'c1');
      expect(snapshot.blockIndex, 1);
      expect(snapshot.blockRatio, closeTo(0.5, 0.001));
      expect(snapshot.charOffset, 150);
      expect(snapshot.chapterVisualCursor, closeTo(150, 0.001));
      expect(snapshot.contentY, closeTo(186, 0.001));
      expect(
        snapshot.layoutRevision.geometryRevision,
        layout.geometry.revision,
      );
      expect(snapshot.layoutRevision.windowRevision, 0);
      expect(snapshot.transactionId, 1);
    });

    test('章节边界：窗口坐标落入第二章体时解析到第二章', () {
      final first = textEntry(id: 'c1', heights: const [100, 200, 300]);
      final second = textEntry(id: 'c2', heights: const [100, 200, 300]);
      final layout = layoutFor(snapshotFor([first, second]));
      const resolver = ReaderPositionResolver();

      // 第二章前缀 = 36 + 300 + 48 = 384；章体起点 contentY = 384 + 36 = 420。
      // 锚线 contentY = scrollOffset + anchorY(50)。
      final inSecond =
          resolver.resolve(
            scrollOffset: 370,
            layout: layout,
            transactionId: 2,
          )!;
      expect(inSecond.chapterId, 'c2');
      expect(inSecond.charOffset, 0);

      final midSecond =
          resolver.resolve(
            scrollOffset: 420,
            layout: layout,
            transactionId: 2,
          )!;
      expect(midSecond.chapterId, 'c2');
      expect(midSecond.blockIndex, 0);
      expect(midSecond.charOffset, 50);

      // 第二章章头区域映射章首。
      final header =
          resolver.resolve(
            scrollOffset: 334,
            layout: layout,
            transactionId: 2,
          )!;
      expect(header.chapterId, 'c2');
      expect(header.charOffset, 0);
    });

    test('图片块：图内 charOffset 恒定，视觉游标随 Y 连续（方案 §45）', () {
      final entry = entryWithImage(id: 'c1');
      final layout = layoutFor(snapshotFor([entry]));
      const resolver = ReaderPositionResolver();

      // 图片章体区间 localY 100..700 → contentY 136..736。
      final top =
          resolver.resolve(scrollOffset: 87, layout: layout, transactionId: 3)!;
      final middle =
          resolver.resolve(
            scrollOffset: 386,
            layout: layout,
            transactionId: 3,
          )!;
      final bottom =
          resolver.resolve(
            scrollOffset: 685,
            layout: layout,
            transactionId: 3,
          )!;

      for (final snapshot in [top, middle, bottom]) {
        expect(snapshot.blockIndex, 1);
        expect(snapshot.charOffset, 100);
      }
      expect(middle.chapterVisualCursor, greaterThan(top.chapterVisualCursor));
      expect(
        bottom.chapterVisualCursor,
        greaterThan(middle.chapterVisualCursor),
      );
    });

    test('空几何返回 null，不抛异常', () {
      const empty = ReaderGeometrySnapshot(
        revision: 0,
        chapterIds: [],
        chapters: {},
      );
      final layout = ReaderLayoutSnapshot(
        geometry: empty,
        viewport: layoutFor(empty).viewport,
        windowRevision: 0,
      );
      const resolver = ReaderPositionResolver();
      expect(
        resolver.resolve(scrollOffset: 0, layout: layout, transactionId: 0),
        isNull,
      );
    });
  });
}
