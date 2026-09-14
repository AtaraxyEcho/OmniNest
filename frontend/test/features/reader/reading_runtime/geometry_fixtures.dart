import 'dart:ui' show Size;

import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// Reading Runtime 测试夹具：纯几何构造，不依赖 widget 树。

ContinuousChapterEntry textEntry({
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
    blockCharPrefixes: List<int>.generate(heights.length + 1, (i) {
      return (totalChars / heights.length).round() * i;
    }),
  );
}

/// 正文 + 图片 + 正文：图片零字符但占视觉高度（方案 §45/§112 核心场景）。
ContinuousChapterEntry entryWithImage({
  required String id,
  double textHeight = 100,
  double imageHeight = 600,
  int textChars = 100,
}) {
  return ContinuousChapterEntry(
    chapterId: id,
    title: id,
    blockCount: 3,
    cumulativeHeights: [
      textHeight,
      textHeight + imageHeight,
      textHeight * 2 + imageHeight,
    ],
    totalHeight: textHeight * 2 + imageHeight,
    totalChars: textChars * 2,
    isReady: true,
    blocks: [
      ParagraphBlock(
        lines: [
          LineData(spans: [ReaderInlineSpan(text: 'before image')]),
        ],
      ),
      ImageBlock(src: 'image://p1'),
      ParagraphBlock(
        lines: [
          LineData(spans: [ReaderInlineSpan(text: 'after image')]),
        ],
      ),
    ],
    blockCharPrefixes: const [0, 100, 100, 200],
  );
}

ReaderGeometrySnapshot snapshotFor(List<ContinuousChapterEntry> entries) {
  // sideChapterCount 必须覆盖全部条目：窗口 = 锚点章 ± 1。
  final controller = ReaderContinuousScrollController(sideChapterCount: 1);
  controller.rebuild(
    anchorChapterId: entries.first.chapterId,
    allChapterIds: entries.map((e) => e.chapterId).toList(growable: false),
    resolve: (id) => entries.where((e) => e.chapterId == id).firstOrNull,
  );
  return controller.buildGeometrySnapshot();
}

ReaderViewportSnapshot testViewport({double anchorY = 50}) {
  return ReaderViewportSnapshot(
    viewportSize: const Size(400, 800),
    anchorY: anchorY,
    contentWidth: 360,
    textScale: 1.0,
    safeAreaTop: 0,
    safeAreaBottom: 0,
  );
}

ReaderLayoutSnapshot layoutFor(
  ReaderGeometrySnapshot geometry, {
  double anchorY = 50,
  int windowRevision = 0,
}) {
  return ReaderLayoutSnapshot(
    geometry: geometry,
    viewport: testViewport(anchorY: anchorY),
    windowRevision: windowRevision,
  );
}
