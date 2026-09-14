import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_visual_metrics.dart';

ReaderContentMetrics _metrics({
  List<double> heights = const [100, 200, 300],
  List<int> prefixes = const [0, 100, 100, 200],
  bool ready = true,
}) {
  return ReaderContentMetrics(
    chapterId: 'c1',
    blockCount: heights.length,
    cumulativeHeights: heights,
    totalHeight: heights.last,
    totalChars: prefixes.isEmpty ? 200 : prefixes.last,
    isReady: ready,
    blockCharPrefixes: prefixes,
  );
}

void main() {
  group('ReaderContentMetrics 内容几何', () {
    test('块区间按 [start, end) 归属，块底归下一块', () {
      final metrics = _metrics();
      expect(metrics.blockIndexAt(50), 0);
      expect(metrics.blockIndexAt(100), 1, reason: '块 0 底归块 1');
      expect(metrics.blockIndexAt(250), 2);
      expect(metrics.blockIndexAt(300), 2, reason: '末块 [start, end]');
    });

    test('块起点与块高按累积高度计算', () {
      final metrics = _metrics();
      expect(metrics.blockStartY(0), 0);
      expect(metrics.blockStartY(2), 200);
      expect(metrics.blockHeight(1), 100);
      expect(metrics.blockHeight(5), 0, reason: '越界块高为 0');
    });

    test('字符前缀缺失时按全章线性折算', () {
      final metrics = _metrics(prefixes: const [], ready: false);
      expect(metrics.hasCharPrefixes, isFalse);
      expect(metrics.charStartOfBlock(0), 0);
      expect(metrics.charStartOfBlock(3), 200, reason: '末块起点=总字数');
      expect(metrics.charStartOfBlock(1), closeTo(67, 1));
    });

    test('文本块判定依赖 blocks 列表，越界按非文本处理', () {
      final metrics = _metrics();
      final blocks = <ContentBlock>[
        ParagraphBlock(
          lines: [
            LineData(spans: [ReaderInlineSpan(text: 'p')]),
          ],
        ),
        ImageBlock(src: 'image://p1'),
        DividerBlock(),
      ];
      expect(metrics.isTextBlockAt(0, blocks), isTrue);
      expect(metrics.isTextBlockAt(1, blocks), isFalse);
      expect(metrics.isTextBlockAt(9, blocks), isFalse);
    });
  });

  group('ReaderContinuousVisualMetrics 视觉空间', () {
    test('visualAt 返回块索引、块内偏移与比例', () {
      final visual = ReaderContinuousVisualMetrics(_metrics());
      final (index, offset, ratio) = visual.visualAt(150);
      expect(index, 1);
      expect(offset, 50);
      expect(ratio, closeTo(0.5, 0.001));
    });

    test('视觉块区间与游标一致', () {
      final visual = ReaderContinuousVisualMetrics(_metrics());
      final (start, end) = visual.visualRangeOfBlock(1);
      expect(start, 100);
      expect(end, 200);
      expect(visual.cursorFor(1, 50), 150);
    });

    test('图片零字符块内部 charOffset 恒定，不制造虚假字符', () {
      final metrics = _metrics();
      final visual = ReaderContinuousVisualMetrics(metrics);
      final blocks = <ContentBlock>[
        ParagraphBlock(
          lines: [
            LineData(spans: [ReaderInlineSpan(text: 'p')]),
          ],
        ),
        ImageBlock(src: 'image://p1'),
        ParagraphBlock(
          lines: [
            LineData(spans: [ReaderInlineSpan(text: 'q')]),
          ],
        ),
      ];
      // 图片块区间 [100, 200)，字符前缀 [100, 100]。
      final top = visual.charOffsetForBlock(1, 0.0, blocks: blocks);
      final mid = visual.charOffsetForBlock(1, 0.5, blocks: blocks);
      final bottom = visual.charOffsetForBlock(1, 1.0, blocks: blocks);
      expect(top, 100);
      expect(mid, 100);
      expect(bottom, 100);
    });

    test('文本块按比例投影到字符前缀区间', () {
      final visual = ReaderContinuousVisualMetrics(_metrics());
      final blocks = <ContentBlock>[
        ParagraphBlock(
          lines: [
            LineData(spans: [ReaderInlineSpan(text: 'p')]),
          ],
        ),
        ParagraphBlock(
          lines: [
            LineData(spans: [ReaderInlineSpan(text: 'q')]),
          ],
        ),
        ParagraphBlock(
          lines: [
            LineData(spans: [ReaderInlineSpan(text: 'r')]),
          ],
        ),
      ];
      expect(visual.charOffsetForBlock(1, 0.0, blocks: blocks), 100);
      expect(visual.charOffsetForBlock(1, 1.0, blocks: blocks), 100);
      expect(visual.charOffsetForBlock(2, 0.0, blocks: blocks), 100);
      expect(visual.charOffsetForBlock(2, 1.0, blocks: blocks), 200);
    });
  });
}
