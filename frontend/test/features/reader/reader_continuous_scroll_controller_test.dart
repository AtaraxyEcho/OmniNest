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
      expect(controller.prefixHeightOf('c0'), 0);
      expect(controller.prefixHeightOf('c1'), 200);
      expect(controller.prefixHeightOf('c2'), 500);
      expect(controller.totalHeight, 750);
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

      final inFirst = controller.positionAtContentY(50);
      expect(inFirst!.chapterId, 'c0');
      expect(inFirst.charOffset, 25);

      final inSecond = controller.positionAtContentY(250);
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
        300,
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
}
