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
  group('ReaderVisualProgressMap 窗口相对回退（无锚点直构）', () {
    test('图片内部视觉进度严格单调递增', () {
      final entry = entryWithImage(id: 'c1');
      final geometry = snapshotFor([entry]);
      final layout = layoutFor(geometry);
      const resolver = ReaderPositionResolver();
      final map = ReaderVisualProgressMap.fromGeometry(geometry);

      var last = -1.0;
      // 图片章体区间 contentY 136..736。
      for (var y = 136.0; y <= 736.0; y += 5) {
        final position =
            resolver.resolve(
              scrollOffset: y - layout.viewport.anchorY,
              layout: layout,
              transactionId: 0,
            )!;
        final progress = map.progressAt(position.contentY)!;
        expect(progress, greaterThan(last), reason: 'contentY=$y');
        expect(progress, inInclusiveRange(0.0, 1.0));
        last = progress;
      }
    });

    test('多章窗口：章体物理区间与窗口体累计进度对应', () {
      final first = textEntry(id: 'c1', heights: const [100, 200, 300]);
      final second = textEntry(id: 'c2', heights: const [100, 200, 300]);
      final geometry = snapshotFor([first, second]);
      final layout = layoutFor(geometry);
      const resolver = ReaderPositionResolver();
      final map = ReaderVisualProgressMap.fromGeometry(geometry);

      // 窗口体 = 300 + 300 = 600；第二章章体起点 contentY = 420
      // （scrollOffset = 420 − anchorY 50）→ 进度恰为 0.5。
      final startOfSecond =
          resolver.resolve(
            scrollOffset: 370,
            layout: layout,
            transactionId: 0,
          )!;
      expect(map.progressAt(startOfSecond.contentY), closeTo(0.5, 0.001));

      final endOfSecond =
          resolver.resolve(
            scrollOffset: 670,
            layout: layout,
            transactionId: 0,
          )!;
      expect(map.progressAt(endOfSecond.contentY), closeTo(1.0, 0.001));
    });

    test('空几何映射查询返回 null', () {
      const empty = ReaderGeometrySnapshot(
        revision: 0,
        chapterIds: [],
        chapters: {},
      );
      final map = ReaderVisualProgressMap.fromGeometry(empty);
      expect(map.progressAt(0), isNull);
    });
  });

  group('ReaderVisualProgressMap 全书锚点（事务发布尺度）', () {
    test('锚点覆盖窗口章时进度按全书区间映射', () {
      final first = textEntry(id: 'c1', heights: const [100, 200, 300]);
      final second = textEntry(id: 'c2', heights: const [100, 200, 300]);
      final geometry = snapshotFor([first, second]);
      final map = ReaderVisualProgressMap.fromGeometry(
        geometry,
        // 全书共 10 章等高：窗口两章仅占全书 0.1-0.3 区间。
        bookAnchors: const {
          'c1': ReaderChapterProgressAnchor(start: 0.1, end: 0.2),
          'c2': ReaderChapterProgressAnchor(start: 0.2, end: 0.3),
        },
      );

      final header = 36.0;
      // c1 章体起点（窗口物理 0 + 章头之后）。
      expect(map.progressAt(header), closeTo(0.1, 0.001));
      // c1 章体中点。
      expect(map.progressAt(header + 150), closeTo(0.15, 0.001));
      // c2 章体起点（c1 占位 = 36 + 300 + 48 = 384）。
      expect(map.progressAt(384 + header), closeTo(0.2, 0.001));
      // c2 章体终点。
      expect(map.progressAt(384 + header + 300), closeTo(0.3, 0.001));
    });

    test('锚点缺失任一窗口章时整体回退窗口相对', () {
      final first = textEntry(id: 'c1', heights: const [100, 200, 300]);
      final second = textEntry(id: 'c2', heights: const [100, 200, 300]);
      final geometry = snapshotFor([first, second]);
      final map = ReaderVisualProgressMap.fromGeometry(
        geometry,
        bookAnchors: const {
          'c1': ReaderChapterProgressAnchor(start: 0.1, end: 0.2),
        },
      );

      // 缺 c2 锚点：不得出现 0.1 起点这种混合尺度，回退窗口 0 起点。
      final header = 36.0;
      expect(map.progressAt(header), closeTo(0.0, 0.001));
      expect(map.progressAt(384 + header + 300), closeTo(1.0, 0.001));
    });

    test('锚点区间内单调且夹在锚点边界内', () {
      final first = textEntry(id: 'c1', heights: const [100, 200, 300]);
      final geometry = snapshotFor([first]);
      final map = ReaderVisualProgressMap.fromGeometry(
        geometry,
        bookAnchors: const {
          'c1': ReaderChapterProgressAnchor(start: 0.4, end: 0.5),
        },
      );

      var last = -1.0;
      for (var y = 36.0; y <= 36.0 + 300; y += 7) {
        final progress = map.progressAt(y)!;
        expect(progress, greaterThanOrEqualTo(last), reason: 'y=$y');
        expect(progress, inInclusiveRange(0.4, 0.5), reason: 'y=$y');
        last = progress;
      }
    });
  });

  group('ReaderLogicalProgressProjection（方案 §47/§112）', () {
    test('图片内部逻辑进度不变而视觉进度递增', () {
      final entry = entryWithImage(id: 'c1');
      final geometry = snapshotFor([entry]);
      final layout = layoutFor(geometry);
      const resolver = ReaderPositionResolver();
      final visual = ReaderVisualProgressMap.fromGeometry(geometry);
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
        final v = visual.progressAt(position.contentY)!;
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
