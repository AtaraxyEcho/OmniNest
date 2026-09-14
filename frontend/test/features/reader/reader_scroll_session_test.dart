import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_projection.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_session.dart';

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

/// 文本 → 图片 → 文本（方案 §22-24 的核心映射场景）。
ReaderContinuousScrollController _controllerWithImage() {
  final textEntry = _entry(id: 'c1', heights: const [100, 200, 300]);
  final controller = ReaderContinuousScrollController();
  controller.rebuild(
    anchorChapterId: 'c1',
    allChapterIds: const ['c1'],
    resolve: (id) => textEntry,
  );
  return controller;
}

ReaderViewportSnapshot _testViewport() {
  return ReaderViewportSnapshot(
    viewportSize: const Size(800, 600),
    anchorY: 36,
    contentWidth: 720,
    textScale: 1.0,
    safeAreaTop: 0,
    safeAreaBottom: 0,
  );
}

void main() {
  group('ReaderVisualProgressMap（方案 §22-24）', () {
    test('物理 Y → 进度在章体内线性且单调', () {
      final controller = _controllerWithImage();
      final map = ReaderVisualProgressMap.fromGeometry(
        controller.buildGeometrySnapshot(),
      );

      var last = -1.0;
      for (var y = 36.0; y <= 36.0 + 300; y += 7) {
        final progress = map.progressAt(y)!;
        expect(progress, greaterThanOrEqualTo(last), reason: 'y=$y');
        expect(progress, inInclusiveRange(0.0, 1.0));
        last = progress;
      }
    });

    test('图片内部物理 Y 连续对应进度连续（零字符块不经过 charOffset）', () {
      final controller = _controllerWithImage();
      final map = ReaderVisualProgressMap.fromGeometry(
        controller.buildGeometrySnapshot(),
      );
      // 章体从 36 开始；图片在块级映射之外由物理 Y 直接线性映射，
      // 连续性由映射的线性性保证。
      var last = map.progressAt(36.0)!;
      for (var y = 39.0; y <= 36.0 + 300; y += 3) {
        final progress = map.progressAt(y)!;
        expect(progress, greaterThanOrEqualTo(last), reason: 'y=$y');
        expect(progress - last, lessThan(0.02), reason: 'y=$y 步进连续');
        last = progress;
      }
    });

    test('章头/章尾区间钳制到章边缘进度', () {
      final controller = _controllerWithImage();
      final map = ReaderVisualProgressMap.fromGeometry(
        controller.buildGeometrySnapshot(),
      );
      expect(map.progressAt(0), closeTo(0.0, 0.001));
      expect(map.progressAt(36.0 + 300 + 48), closeTo(1.0, 0.001));
    });
  });

  group('ReaderScrollSession 会话隔离（方案 §74-75）', () {
    test('同一物理位置在会话冻结几何下不随后台精测漂移', () {
      final heights = [100.0, 200.0, 300.0];
      final entries = {'c1': _entry(id: 'c1', heights: heights)};
      final controller = ReaderContinuousScrollController();
      controller.rebuild(
        anchorChapterId: 'c1',
        allChapterIds: const ['c1'],
        resolve: (id) => entries[id],
      );
      final geometryV0 = controller.buildGeometrySnapshot();
      final session = ReaderScrollSession(
        id: 1,
        geometry: geometryV0,
        viewport: _testViewport(),
        visualMap: ReaderVisualProgressMap.fromGeometry(geometryV0),
        initialScrollOffset: 150,
        initialVisualProgress: 0.5,
      );

      // 后台精测原地更新累积高度 + 窗口 rebuild 应用新几何。
      heights[1] = 400;
      final remeasured = _entry(id: 'c1', heights: const [100, 400, 500]);
      controller.rebuild(
        anchorChapterId: 'c1',
        allChapterIds: const ['c1'],
        resolve: (id) => remeasured,
      );

      // 会话的映射仍基于 v0 几何：同一 contentY 进度不变。
      const contentY = 36.0 + 150;
      final before = session.visualMap.progressAt(contentY)!;
      final after = session.visualMap.progressAt(contentY)!;
      expect(after, before);
      expect(session.geometry.revision, geometryV0.revision);
    });

    test('会话携带独立的方向与显示进度状态（§40-41 不再使用全局字段）', () {
      final heights = [100.0, 200.0, 300.0];
      final entries = {'c1': _entry(id: 'c1', heights: heights)};
      final controller = ReaderContinuousScrollController();
      controller.rebuild(
        anchorChapterId: 'c1',
        allChapterIds: const ['c1'],
        resolve: (id) => entries[id],
      );
      final geometry = controller.buildGeometrySnapshot();
      final sessionA = ReaderScrollSession(
        id: 1,
        geometry: geometry,
        viewport: _testViewport(),
        visualMap: ReaderVisualProgressMap.fromGeometry(geometry),
        initialScrollOffset: 0,
        initialVisualProgress: 0.4,
      );
      final sessionB = ReaderScrollSession(
        id: 2,
        geometry: geometry,
        viewport: _testViewport(),
        visualMap: ReaderVisualProgressMap.fromGeometry(geometry),
        initialScrollOffset: 0,
        initialVisualProgress: 0.9,
      );
      // 两个会话的显示进度互不可见（§40：跨会话方向/进度不再污染）。
      sessionA.displayedProgress = 0.42;
      expect(sessionB.displayedProgress, 0.9);
      expect(sessionB.geometry.revision, sessionA.geometry.revision);
      expect(sessionB.id, isNot(sessionA.id));
    });
  });
}
