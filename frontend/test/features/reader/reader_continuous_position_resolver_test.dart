import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';

ContinuousChapterEntry _textEntry({
  required String id,
  required List<double> heights,
  required int totalChars,
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

/// 正文 + 图片 + 正文：图片零字符但占视觉高度，是双坐标模型的核心场景。
ContinuousChapterEntry _entryWithImage({
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

ReaderContinuousScrollController _controller({
  required ContinuousChapterEntry anchor,
}) {
  final controller = ReaderContinuousScrollController(sideChapterCount: 0);
  controller.rebuild(
    anchorChapterId: anchor.chapterId,
    allChapterIds: [anchor.chapterId],
    resolve: (id) => id == anchor.chapterId ? anchor : null,
  );
  return controller;
}

void main() {
  group('ReaderContinuousPositionResolver 双坐标', () {
    test('Visual 往返：contentY → VisualPosition → contentY 保持块与比例', () {
      final entry = _textEntry(
        id: 'c1',
        heights: const [100, 200, 300],
        totalChars: 300,
      );
      final controller = _controller(anchor: entry);
      final resolver = controller.resolver;

      final contentY = 36.0 + 150;
      final visual = resolver.visualAtContentY(contentY)!;
      expect(visual.blockIndex, 1);
      expect(visual.blockRatio, closeTo(0.5, 0.001));

      final back = resolver.contentYForVisualPosition(visual)!;
      final visualAgain = resolver.visualAtContentY(back)!;
      expect(visualAgain.blockIndex, visual.blockIndex);
      expect(visualAgain.blockRatio, closeTo(visual.blockRatio, 0.001));
    });

    test('Logical 往返：charOffset → 视觉 → contentY → charOffset 误差有界', () {
      final entry = _textEntry(
        id: 'c1',
        heights: const [100, 200, 300],
        totalChars: 300,
      );
      final controller = _controller(anchor: entry);
      final resolver = controller.resolver;

      for (final charOffset in const [0, 60, 150, 240, 299]) {
        final visual = resolver.visualFromLogical('c1', charOffset)!;
        final contentY = resolver.contentYForVisualPosition(visual)!;
        final resolved = resolver.resolveContentY(contentY)!;
        expect(
          (resolved.logical.charOffset - charOffset).abs(),
          lessThanOrEqualTo(3),
          reason: 'charOffset=$charOffset 往返偏差应逐字有界',
        );
      }
    });

    test('图片内部滚动：视觉进度连续增长、逻辑进度保持不变', () {
      final entry = _entryWithImage(id: 'c1');
      final controller = _controller(anchor: entry);
      final resolver = controller.resolver;

      // 章体从 contentY = 36 开始：图片块区间 [100, 700)（块底归下一块）。
      final imageTop = 36.0 + 100;
      var lastVisualProgress = -1.0;
      var lastRatio = -1.0;
      final charOffsets = <int>{};
      for (var step = 0; step < 10; step++) {
        final y = imageTop + 600 * step / 10;
        final resolved = resolver.resolveContentY(y)!;
        expect(resolved.visual.blockIndex, 1, reason: 'y=$y 应落在图片块内');
        expect(
          resolved.visual.blockRatio,
          greaterThanOrEqualTo(lastRatio),
          reason: 'blockRatio 应单调不减',
        );
        expect(
          resolved.chapterVisualProgress,
          greaterThan(lastVisualProgress),
          reason: '视觉进度必须连续增长，不得二值跳变',
        );
        charOffsets.add(resolved.logical.charOffset);
        lastVisualProgress = resolved.chapterVisualProgress;
        lastRatio = resolved.visual.blockRatio;
      }
      // 图片底部边界按 [start, end) 归下一块。
      final atImageBottom = resolver.resolveContentY(imageTop + 600)!;
      expect(atImageBottom.visual.blockIndex, 2);
      // 图片内部 charOffset 恒为图片块字符（前缀 100），不产生虚假字符。
      expect(charOffsets, {100});
      expect(entry.totalChars, 200);
    });

    test('visualFromLogical：图片起点 charOffset 映射到图片顶部', () {
      final entry = _entryWithImage(id: 'c1');
      final controller = _controller(anchor: entry);
      final resolver = controller.resolver;

      final visual = resolver.visualFromLogical('c1', 100)!;
      expect(visual.blockIndex, 1);
      expect(visual.offsetInBlock, 0);
      expect(visual.blockRatio, 0);
    });

    test('块边界按 [start, end) 归下一块，逻辑结果边界中性', () {
      final entry = _textEntry(
        id: 'c1',
        heights: const [100, 200, 300],
        totalChars: 300,
      );
      final controller = _controller(anchor: entry);
      final resolver = controller.resolver;

      final atBoundary = resolver.visualAtContentY(36.0 + 100)!;
      expect(atBoundary.blockIndex, 1);
      expect(atBoundary.offsetInBlock, 0);

      // 块 0 末字符与块 1 首字符是同一起始前缀：边界归属不影响逻辑值。
      final resolved = resolver.resolveContentY(36.0 + 100)!;
      expect(resolved.logical.charOffset, entry.blockCharPrefixes[1]);
    });

    test('性质化扫描：密集网格上双坐标往返与单调性保持', () {
      // 正文 + 图片 + 正文（图 600 高），章体总高 800。
      final entry = _entryWithImage(id: 'c1');
      final controller = _controller(anchor: entry);
      final resolver = controller.resolver;

      final bodyTop = 36.0;
      final bodyHeight = entry.totalHeight;
      var lastCursor = -1.0;
      var lastCharOffset = -1;
      for (var i = 0; i <= 400; i++) {
        final contentY = bodyTop + bodyHeight * i / 400;
        final resolved = resolver.resolveContentY(contentY)!;

        // Visual 往返：块索引一致、比例误差有界。
        final backY = resolver.contentYForVisualPosition(resolved.visual)!;
        final again = resolver.visualAtContentY(backY)!;
        expect(
          again.blockIndex,
          resolved.visual.blockIndex,
          reason: 'y=$contentY',
        );
        expect(
          again.blockRatio,
          closeTo(resolved.visual.blockRatio, 0.001),
          reason: 'y=$contentY',
        );

        // 视觉游标单调不减。
        expect(
          resolved.chapterVisualCursor,
          greaterThanOrEqualTo(lastCursor),
          reason: 'y=$contentY',
        );
        lastCursor = resolved.chapterVisualCursor;

        // Logical 往返：charOffset → 视觉 → contentY → charOffset 有界。
        final visual =
            resolver.visualFromLogical('c1', resolved.logical.charOffset)!;
        final logicalBack = resolver.logicalFromVisual(visual)!.charOffset;
        expect(
          (logicalBack - resolved.logical.charOffset).abs(),
          lessThanOrEqualTo(2),
          reason: 'y=$contentY charOffset=${resolved.logical.charOffset}',
        );

        // 逻辑进度随向下扫描单调不减。
        expect(
          resolved.logical.charOffset,
          greaterThanOrEqualTo(lastCharOffset),
          reason: 'y=$contentY',
        );
        lastCharOffset = resolved.logical.charOffset;
      }
    });
  });
}
