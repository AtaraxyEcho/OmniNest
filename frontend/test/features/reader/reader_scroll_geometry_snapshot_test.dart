import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

ContinuousChapterEntry _entry({
  required String id,
  required List<double> heights,
  int totalChars = 300,
}) {
  return ContinuousChapterEntry(
    chapterId: id,
    title: id,
    blockCount: heights.length,
    cumulativeHeights: heights,
    totalHeight: heights.last,
    totalChars: totalChars,
    isReady: true,
    blocks: List<ContentBlock>.generate(heights.length, (i) {
      return ParagraphBlock(
        lines: [
          LineData(spans: [ReaderInlineSpan(text: 'block $i of $id')]),
        ],
      );
    }),
    blockCharPrefixes: List<int>.generate(
      heights.length + 1,
      (i) => (totalChars / heights.length).round() * i,
    ),
  );
}

ReaderContinuousScrollController _controller(
  Map<String, ContinuousChapterEntry> entries, {
  required String anchor,
  required List<String> window,
}) {
  final controller = ReaderContinuousScrollController();
  controller.rebuild(
    anchorChapterId: anchor,
    allChapterIds: window,
    resolve: (id) => entries[id],
  );
  return controller;
}

void main() {
  group('ReaderScrollGeometrySnapshot 几何快照', () {
    test('快照是深冻结复制：Live 几何原地变化不穿透快照', () {
      final heights = [100.0, 200.0, 300.0];
      final entries = {'c1': _entry(id: 'c1', heights: heights)};
      final controller = _controller(
        entries,
        anchor: 'c1',
        window: const ['c1'],
      );
      final snapshot = controller.buildGeometrySnapshot();

      // 模拟后台精测原地更新累积高度。
      heights[0] = 999;
      entries['c1']!.cumulativeHeights[0] = 999;

      expect(
        snapshot.chapterOf('c1')!.cumulativeHeights[0],
        100,
        reason: '快照必须与 Live 几何的后续变化隔离',
      );
      expect(snapshot.chapterOf('c1')!.totalHeight, 300);
    });

    test('快照包含窗口章节顺序与前缀', () {
      final entries = {
        'c0': _entry(id: 'c0', heights: const [50, 100], totalChars: 100),
        'c1': _entry(id: 'c1', heights: const [100, 200, 300]),
      };
      final controller = _controller(
        entries,
        anchor: 'c1',
        window: const ['c0', 'c1'],
      );
      final snapshot = controller.buildGeometrySnapshot();

      expect(snapshot.chapterIds, ['c0', 'c1']);
      expect(snapshot.prefixOf('c1'), greaterThan(0));
      expect(snapshot.prefixOf('c0'), 0);
      expect(snapshot.contains('c1'), isTrue);
      expect(snapshot.contains('c9'), isFalse);
    });
  });

  group('Resolver 快照来源（方案 §41-42）', () {
    test('等价性：几何未变化时快照解析与 Live 解析一致', () {
      final entries = {
        'c1': _entry(id: 'c1', heights: const [100, 200, 300]),
      };
      final controller = _controller(
        entries,
        anchor: 'c1',
        window: const ['c1'],
      );
      final resolver = controller.resolver;
      final snapshot = controller.buildGeometrySnapshot();

      const y = 36.0 + 150;
      final live = resolver.resolveContentY(y)!;
      final fromSnapshot =
          resolver.resolveContentY(
            y,
            source: SnapshotScrollGeometrySource(snapshot),
          )!;
      expect(fromSnapshot.visual, live.visual);
      expect(fromSnapshot.logical, live.logical);
      expect(fromSnapshot.geometryRevision, live.geometryRevision);
    });

    test('后台精测改变 Live 几何时，快照解析仍使用手势基准几何', () {
      final heights = [100.0, 200.0, 300.0];
      final entries = {'c1': _entry(id: 'c1', heights: heights)};
      final controller = _controller(
        entries,
        anchor: 'c1',
        window: const ['c1'],
      );
      final resolver = controller.resolver;
      final snapshotV0 = controller.buildGeometrySnapshot();
      final revisionV0 = snapshotV0.revision;

      // 后台精测：块 1 从 100 高变为 300 高，窗口 rebuild 应用新几何。
      final remeasured = _entry(
        id: 'c1',
        heights: const [100, 400, 500],
        totalChars: 300,
      );
      heights[0] = 100;
      heights[1] = 400;
      heights[2] = 500;
      controller.rebuild(
        anchorChapterId: 'c1',
        allChapterIds: const ['c1'],
        resolve: (id) => remeasured,
      );
      expect(controller.geometryRevision, greaterThan(revisionV0));

      const y = 36.0 + 150;
      // ACTIVE：resolver 必须仍使用 v10（快照）几何解释位置。
      final fromSnapshot =
          resolver.resolveContentY(
            y,
            source: SnapshotScrollGeometrySource(snapshotV0),
          )!;
      expect(fromSnapshot.geometryRevision, revisionV0);
      expect(fromSnapshot.visual.blockIndex, 1);
      expect(fromSnapshot.visual.blockRatio, closeTo(0.5, 0.001));

      // Live 几何反映新布局（ScrollEnd 提交后才成为解析基准）。
      final live = resolver.resolveContentY(y)!;
      expect(live.geometryRevision, controller.geometryRevision);
      expect(live.visual.blockIndex, 1);
      expect(
        live.visual.blockRatio,
        closeTo(50 / 300, 0.01),
        reason: 'Live 几何下同一 contentY 的块内比例不同',
      );
    });

    test('窗口滑动改变组成时，快照解析仍使用旧窗口（§42）', () {
      final entries = {
        'c0': _entry(id: 'c0', heights: const [50, 100], totalChars: 100),
        'c1': _entry(id: 'c1', heights: const [100, 200, 300]),
        'c2': _entry(id: 'c2', heights: const [80, 160], totalChars: 100),
      };
      final controller = _controller(
        entries,
        anchor: 'c1',
        window: const ['c0', 'c1', 'c2'],
      );
      final snapshot = controller.buildGeometrySnapshot();

      // 窗口滑动：[c0,c1,c2] → [c1,c2,c3]。
      final c3 = _entry(id: 'c3', heights: const [90, 180], totalChars: 100);
      controller.rebuild(
        anchorChapterId: 'c1',
        allChapterIds: const ['c1', 'c2', 'c3'],
        resolve: (id) => id == 'c3' ? c3 : entries[id],
      );

      const y = 36.0 + 150;
      final fromSnapshot =
          controller.resolver.resolveContentY(
            y,
            source: SnapshotScrollGeometrySource(snapshot),
          )!;
      expect(fromSnapshot.chapterId, 'c1', reason: 'ACTIVE 期间窗口组成冻结');
      expect(snapshot.chapterIds, const [
        'c0',
        'c1',
        'c2',
      ], reason: '快照窗口组成不可变');
    });
  });
}
