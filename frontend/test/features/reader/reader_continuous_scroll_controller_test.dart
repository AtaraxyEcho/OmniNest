import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';

ContinuousChapterEntry _entry({
  required String id,
  required String title,
  required int blockCount,
  required double totalHeight,
  required int totalChars,
  bool isReady = true,
  List<ContentBlock>? blocks,
  List<double>? cumulativeHeights,
}) {
  final heights =
      cumulativeHeights ??
      List<double>.generate(
        blockCount,
        (i) => totalHeight * (i + 1) / blockCount,
      );
  return ContinuousChapterEntry(
    chapterId: id,
    title: title,
    blockCount: blockCount,
    cumulativeHeights: isReady ? heights : const [],
    totalHeight: totalHeight,
    totalChars: totalChars,
    isReady: isReady,
    blocks:
        blocks ??
        List<ContentBlock>.generate(
          blockCount,
          (i) => ParagraphBlock(
            lines: [
              LineData(spans: [ReaderInlineSpan(text: 'p$i of $id')]),
            ],
          ),
        ),
  );
}

void main() {
  group('ReaderContinuousScrollController', () {
    test('window includes prev/current/next and computes prefix heights', () {
      final controller = ReaderContinuousScrollController();
      final entries = {
        'c0': _entry(
          id: 'c0',
          title: '第一章',
          blockCount: 2,
          totalHeight: 200,
          totalChars: 100,
        ),
        'c1': _entry(
          id: 'c1',
          title: '第二章',
          blockCount: 3,
          totalHeight: 300,
          totalChars: 200,
        ),
        'c2': _entry(
          id: 'c2',
          title: '第三章',
          blockCount: 2,
          totalHeight: 250,
          totalChars: 150,
        ),
      };
      controller.rebuild(
        anchorChapterId: 'c1',
        allChapterIds: const ['c0', 'c1', 'c2'],
        resolve: (id) => entries[id],
      );

      expect(controller.entries.map((e) => e.chapterId), ['c0', 'c1', 'c2']);
      // 前缀含每章 chrome：章头 36 + 章尾 48（就绪章）。
      expect(controller.prefixHeightOf('c0'), 0);
      expect(controller.prefixHeightOf('c1'), 284);
      expect(controller.prefixHeightOf('c2'), 668);
      expect(controller.totalHeight, 1002);
    });

    test('clamps window at book start', () {
      final controller = ReaderContinuousScrollController();
      final entries = {
        'c0': _entry(
          id: 'c0',
          title: 'A',
          blockCount: 1,
          totalHeight: 100,
          totalChars: 10,
        ),
        'c1': _entry(
          id: 'c1',
          title: 'B',
          blockCount: 1,
          totalHeight: 100,
          totalChars: 10,
        ),
      };
      controller.rebuild(
        anchorChapterId: 'c0',
        allChapterIds: const ['c0', 'c1'],
        resolve: (id) => entries[id],
      );
      expect(controller.entries.map((e) => e.chapterId), ['c0', 'c1']);
      expect(controller.prefixHeightOf('c0'), 0);
    });

    test('positionAtContentY resolves chapter and charOffset', () {
      final controller = ReaderContinuousScrollController();
      final entries = {
        'c0': _entry(
          id: 'c0',
          title: 'A',
          blockCount: 2,
          totalHeight: 200,
          totalChars: 100,
        ),
        'c1': _entry(
          id: 'c1',
          title: 'B',
          blockCount: 2,
          totalHeight: 200,
          totalChars: 100,
        ),
      };
      controller.rebuild(
        anchorChapterId: 'c0',
        allChapterIds: const ['c0', 'c1'],
        resolve: (id) => entries[id],
      );

      // 章体起点 = 前缀 + 章头 36；窗口 contentY 需含 chrome 偏移。
      final inFirst = controller.positionAtContentY(36 + 50);
      expect(inFirst!.chapterId, 'c0');
      expect(inFirst.charOffset, 25);

      // c1 前缀 284，章体起点 320。
      final inSecond = controller.positionAtContentY(320 + 50);
      expect(inSecond!.chapterId, 'c1');
      expect(inSecond.charOffset, 25);
    });

    test('contentYFor maps chapter charOffset to window Y', () {
      final controller = ReaderContinuousScrollController();
      final entries = {
        'c0': _entry(
          id: 'c0',
          title: 'A',
          blockCount: 1,
          totalHeight: 200,
          totalChars: 100,
        ),
        'c1': _entry(
          id: 'c1',
          title: 'B',
          blockCount: 1,
          totalHeight: 200,
          totalChars: 100,
        ),
      };
      controller.rebuild(
        anchorChapterId: 'c0',
        allChapterIds: const ['c0', 'c1'],
        resolve: (id) => entries[id],
      );
      expect(
        controller.contentYFor(
          chapterId: 'c1',
          charOffset: 50,
          totalChars: 100,
          chapterHeight: 200,
        ),
        // c1 前缀 284 + 章头 36 + ratio 0.5 × 200。
        420,
      );
    });

    test('expand heuristics fire near window edges', () {
      final controller = ReaderContinuousScrollController();
      final entries = {
        'c0': _entry(
          id: 'c0',
          title: 'A',
          blockCount: 1,
          totalHeight: 800,
          totalChars: 100,
        ),
        'c1': _entry(
          id: 'c1',
          title: 'B',
          blockCount: 1,
          totalHeight: 800,
          totalChars: 100,
        ),
      };
      controller.rebuild(
        anchorChapterId: 'c0',
        allChapterIds: const ['c0', 'c1'],
        resolve: (id) => entries[id],
      );
      expect(controller.shouldExpandForward(1000, 600), isTrue);
      expect(controller.shouldExpandForward(0, 100), isFalse);
      expect(controller.shouldExpandBackward(100), isTrue);
      expect(controller.shouldExpandBackward(1000), isFalse);
    });

    test('unready chapter uses placeholder height and is not ready', () {
      final controller = ReaderContinuousScrollController();
      controller.rebuild(
        anchorChapterId: 'c0',
        allChapterIds: const ['c0', 'c1'],
        resolve: (id) {
          if (id == 'c0') {
            return _entry(
              id: 'c0',
              title: 'A',
              blockCount: 1,
              totalHeight: 100,
              totalChars: 10,
            );
          }
          return null;
        },
      );
      final next = controller.entryFor('c1')!;
      expect(next.isReady, isFalse);
      expect(next.totalHeight, 240);
    });
  });

  group('VisualAnchor 视觉锚点', () {
    ReaderContinuousScrollController buildController({
      required List<double> heights,
      int totalChars = 300,
      String anchor = 'c1',
    }) {
      final controller = ReaderContinuousScrollController();
      final entries = {
        'c0': _entry(
          id: 'c0',
          title: 'A',
          blockCount: 2,
          totalHeight: 200,
          totalChars: 100,
        ),
        'c1': _entry(
          id: 'c1',
          title: 'B',
          blockCount: heights.length,
          totalHeight: heights.last,
          totalChars: totalChars,
          cumulativeHeights: heights,
        ),
      };
      controller.rebuild(
        anchorChapterId: anchor,
        allChapterIds: const ['c0', 'c1'],
        resolve: (id) => entries[id],
      );
      return controller;
    }

    test('解析块索引与块内偏移，块边界按 [start, end) 归下一块', () {
      // 3 块：块高各 100；c1 前缀 284 + 章头 36。
      final controller = buildController(heights: const [100, 200, 300]);
      final inFirstBlock = controller.visualAnchorAt(284 + 36 + 50)!;
      expect(inFirstBlock.chapterId, 'c1');
      expect(inFirstBlock.blockIndex, 0);
      expect(inFirstBlock.offsetInBlock, 50);

      // 恰在块 0 底（=块 1 顶）：归下一块，块内偏移 0。
      final atBoundary = controller.visualAnchorAt(284 + 36 + 100)!;
      expect(atBoundary.blockIndex, 1);
      expect(atBoundary.offsetInBlock, 0);

      final inLastBlock = controller.visualAnchorAt(284 + 36 + 250)!;
      expect(inLastBlock.blockIndex, 2);
      expect(inLastBlock.offsetInBlock, 50);
    });

    test('锚点往返解析保持同一视觉位置', () {
      final controller = buildController(heights: const [100, 200, 300]);
      final contentY = 284.0 + 36 + 250;
      final anchor = controller.visualAnchorAt(contentY)!;
      expect(
        controller.contentYForVisualAnchor(anchor),
        closeTo(contentY, 0.01),
      );
    });

    test('块重测高后按比例保持块内位置（图片中部不回块顶）', () {
      final controller = buildController(heights: const [100, 200, 300]);
      final oldEntry = controller.entryFor('c1');
      // 用户在块 1（高 100，100→200）中部：offsetInBlock = 50。
      final anchor = controller.visualAnchorAt(284 + 36 + 150)!;
      expect(anchor.blockIndex, 1);
      expect(anchor.offsetInBlock, 50);

      // 块 1 重测为 300 高：累积 [100, 400, 500]。
      final remeasured = _entry(
        id: 'c1',
        title: 'B',
        blockCount: 3,
        totalHeight: 500,
        totalChars: 300,
        cumulativeHeights: const [100, 400, 500],
      );
      controller.rebuild(
        anchorChapterId: 'c1',
        allChapterIds: const ['c0', 'c1'],
        resolve: (id) => id == 'c1' ? remeasured : controller.entryFor(id),
      );
      final remapped =
          controller.remapVisualAnchor(anchor, oldEntry: oldEntry)!;
      // 比例保持：50 / 100 × 300 = 150。
      expect(remapped.offsetInBlock, closeTo(150, 0.01));
      final newY = controller.contentYForVisualAnchor(remapped)!;
      expect(newY, closeTo(284 + 36 + 100 + 150, 0.01));
    });

    test('锚点章重测后未就绪时透传锚点且无法解析窗口坐标', () {
      final controller = buildController(heights: const [100, 200]);
      final anchor = controller.visualAnchorAt(284 + 36 + 50)!;
      controller.rebuild(
        anchorChapterId: 'c1',
        allChapterIds: const ['c0', 'c1'],
        resolve: (id) => null,
      );
      // 新布局无块级高度：重映射透传锚点本体，但窗口坐标不可解析
      // （调用方回退高度差补偿）。
      expect(controller.remapVisualAnchor(anchor, oldEntry: null), isNotNull);
      expect(controller.contentYForVisualAnchor(anchor), isNull);
    });
  });
}
