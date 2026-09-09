import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';

ContinuousChapterEntry _entry({
  required String id,
  int blockCount = 1,
  double totalHeight = 100,
  int totalChars = 10,
  bool isReady = true,
}) {
  return ContinuousChapterEntry(
    chapterId: id,
    title: 'T$id',
    blockCount: blockCount,
    cumulativeHeights: List<double>.generate(
      blockCount,
      (i) => totalHeight * (i + 1) / blockCount,
    ),
    totalHeight: totalHeight,
    totalChars: totalChars,
    isReady: isReady,
    blocks: List.generate(
      blockCount,
      (_) => ParagraphBlock(
        lines: [
          LineData(spans: [ReaderInlineSpan(text: 'x' * 8)]),
        ],
      ),
    ),
    blockCharPrefixes: [
      for (var i = 0; i <= blockCount; i++) (totalChars * i ~/ blockCount),
    ],
  );
}

void main() {
  group('ReaderContinuousScrollController rebuild short-circuit', () {
    test('identical window does not notify listeners', () {
      final controller = ReaderContinuousScrollController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      ContinuousChapterEntry? resolve(String id) {
        if (id == 'c1') {
          return _entry(
            id: 'c1',
            blockCount: 2,
            totalHeight: 200,
            totalChars: 50,
          );
        }
        if (id == 'c0' || id == 'c2') {
          return _entry(id: id, totalHeight: 80, totalChars: 20);
        }
        return null;
      }

      controller.rebuild(
        anchorChapterId: 'c1',
        allChapterIds: const ['c0', 'c1', 'c2'],
        resolve: resolve,
      );
      expect(notifications, 1);
      expect(controller.entries.length, 3);

      controller.rebuild(
        anchorChapterId: 'c1',
        allChapterIds: const ['c0', 'c1', 'c2'],
        resolve: resolve,
      );
      expect(notifications, 1, reason: 'identical signature must not notify');
    });

    test('height change notifies listeners', () {
      final controller = ReaderContinuousScrollController();
      var notifications = 0;
      controller.addListener(() => notifications++);
      var height = 100.0;

      ContinuousChapterEntry? resolve(String id) {
        if (id == 'c0') {
          return _entry(id: 'c0', totalHeight: height, totalChars: 20);
        }
        return null;
      }

      controller.rebuild(
        anchorChapterId: 'c0',
        allChapterIds: const ['c0', 'c1'],
        resolve: resolve,
        estimateHeight: (_) => 400,
      );
      expect(notifications, 1);

      height = 160;
      controller.rebuild(
        anchorChapterId: 'c0',
        allChapterIds: const ['c0', 'c1'],
        resolve: resolve,
        estimateHeight: (_) => 400,
      );
      expect(notifications, 2);
      expect(controller.entryFor('c0')!.totalHeight, 160);
    });

    test('anchor change updates window composition', () {
      final controller = ReaderContinuousScrollController();
      ContinuousChapterEntry? resolve(String id) => _entry(id: id);

      controller.rebuild(
        anchorChapterId: 'c0',
        allChapterIds: const ['c0', 'c1', 'c2'],
        resolve: resolve,
      );
      expect(controller.entries.map((e) => e.chapterId), ['c0', 'c1']);

      controller.rebuild(
        anchorChapterId: 'c1',
        allChapterIds: const ['c0', 'c1', 'c2'],
        resolve: resolve,
      );
      expect(controller.entries.map((e) => e.chapterId), ['c0', 'c1', 'c2']);
    });
  });
}
