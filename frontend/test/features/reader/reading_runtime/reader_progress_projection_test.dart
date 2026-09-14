import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_revision.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_resolver.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_projection.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

import 'geometry_fixtures.dart';

ReaderPositionSnapshot _manualPosition({String chapterId = 'c1'}) {
  return ReaderPositionSnapshot(
    transactionId: 0,
    layoutRevision: const ReaderLayoutRevision(
      geometryRevision: 0,
      windowRevision: 0,
    ),
    scrollOffset: 0,
    contentY: 0,
    chapterId: chapterId,
    blockIndex: 0,
    blockRatio: 0,
    charOffset: 0,
    chapterVisualCursor: 0,
  );
}

void main() {
  group('ReaderVisualProgressProjection（方案 §46/§111）', () {
    test('图片内部视觉进度严格单调递增', () {
      final entry = entryWithImage(id: 'c1');
      final geometry = snapshotFor([entry]);
      final layout = layoutFor(geometry);
      const resolver = ReaderPositionResolver();
      final projection = ReaderVisualProgressProjection();

      var last = -1.0;
      // 图片章体区间 contentY 136..736。
      for (var y = 136.0; y <= 736.0; y += 5) {
        final position =
            resolver.resolve(
              scrollOffset: y - layout.viewport.anchorY,
              layout: layout,
              transactionId: 0,
            )!;
        final progress = projection.project(position, geometry);
        expect(progress, greaterThan(last), reason: 'contentY=$y');
        expect(progress, inInclusiveRange(0.0, 1.0));
        last = progress;
      }
    });

    test('多章窗口：章体物理区间与全书体累计进度对应', () {
      final first = textEntry(id: 'c1', heights: const [100, 200, 300]);
      final second = textEntry(id: 'c2', heights: const [100, 200, 300]);
      final geometry = snapshotFor([first, second]);
      final layout = layoutFor(geometry);
      const resolver = ReaderPositionResolver();
      final projection = ReaderVisualProgressProjection();

      // 全书体 = 300 + 300 = 600；第二章章体起点 contentY = 420
      // （scrollOffset = 420 − anchorY 50）→ 进度恰为 0.5。
      final startOfSecond =
          resolver.resolve(
            scrollOffset: 370,
            layout: layout,
            transactionId: 0,
          )!;
      expect(projection.project(startOfSecond, geometry), closeTo(0.5, 0.001));

      final endOfSecond =
          resolver.resolve(
            scrollOffset: 670,
            layout: layout,
            transactionId: 0,
          )!;
      expect(projection.project(endOfSecond, geometry), closeTo(1.0, 0.001));
    });

    test('空几何投影为 0', () {
      const empty = ReaderGeometrySnapshot(
        revision: 0,
        chapterIds: [],
        chapters: {},
      );
      final projection = ReaderVisualProgressProjection();
      expect(projection.project(_manualPosition(), empty), 0.0);
    });
  });

  group('ReaderLogicalProgressProjection（方案 §47/§112）', () {
    test('图片内部逻辑进度不变而视觉进度递增', () {
      final entry = entryWithImage(id: 'c1');
      final geometry = snapshotFor([entry]);
      final layout = layoutFor(geometry);
      const resolver = ReaderPositionResolver();
      final visual = ReaderVisualProgressProjection();
      const logical = ReaderLogicalProgressProjection();

      double? logicalAtImageTop;
      var lastVisual = -1.0;
      for (final contentY in const [137.0, 300.0, 436.0, 600.0, 735.0]) {
        final position =
            resolver.resolve(
              scrollOffset: contentY - layout.viewport.anchorY,
              layout: layout,
              transactionId: 0,
            )!;
        final v = visual.project(position, geometry);
        final l = logical.project(position, geometry);
        expect(v, greaterThan(lastVisual), reason: 'contentY=$contentY');
        lastVisual = v;
        // 图片块零字符：charOffset 恒为块首字符 100 → 逻辑进度恒 0.5。
        expect(l, closeTo(0.5, 0.0001), reason: 'contentY=$contentY');
        logicalAtImageTop ??= l;
      }
      expect(logicalAtImageTop, closeTo(0.5, 0.0001));
    });

    test('未知章节或零字符章投影为 0', () {
      const empty = ReaderGeometrySnapshot(
        revision: 0,
        chapterIds: [],
        chapters: {},
      );
      const projection = ReaderLogicalProgressProjection();
      expect(projection.project(_manualPosition(), empty), 0.0);
      expect(
        projection.project(_manualPosition(chapterId: 'ghost'), empty),
        0.0,
      );
    });
  });
}
