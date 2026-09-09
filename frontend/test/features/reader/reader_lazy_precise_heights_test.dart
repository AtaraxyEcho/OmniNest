import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  group('lazy precise heights for neighbors', () {
    test('neighbor keeps estimate until ensurePreciseHeights', () async {
      final loader = ReaderContentLoader(
        allChapters: [
          ReaderChapter(id: 'c0', title: 'A'),
          ReaderChapter(id: 'c1', title: 'B'),
        ],
      );
      final settings = ReaderViewSettings();
      final html = '<p>${'字' * 300}</p><p>${'字' * 300}</p>';

      // 先设活动章，邻章 loadChapter 才只做 phase-one。
      loader.setActive('c0');
      await loader.loadChapter(
        chapterId: 'c0',
        content: ReaderChapterContent(title: 'A', content: html),
        pageWidth: 400,
        pageHeight: 0,
        settings: settings,
        prepareScrollLayout: true,
      );
      await loader.loadChapter(
        chapterId: 'c1',
        content: ReaderChapterContent(title: 'B', content: html),
        pageWidth: 400,
        pageHeight: 0,
        settings: settings,
        prepareScrollLayout: true,
      );

      loader.ensureScrollLayoutForNeighbors(
        'c0',
        pageWidth: 400,
        settings: settings,
      );

      final anchor = loader.getByChapterId('c0')!;
      final neighbor = loader.getByChapterId('c1')!;
      expect(anchor.cumulativeHeights, isNotEmpty);
      expect(neighbor.cumulativeHeights, isNotEmpty);

      // 等待锚点精测完成（小章节应很快）。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(anchor.hasPreciseHeights, isTrue);
      expect(
        neighbor.hasPreciseHeights,
        isFalse,
        reason: 'neighbor should stay on phase-one estimate',
      );

      loader.ensurePreciseHeights('c1', pageWidth: 400, settings: settings);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(neighbor.hasPreciseHeights, isTrue);
    });

    test('rekey marks precise heights', () async {
      final loader = ReaderContentLoader(
        allChapters: [ReaderChapter(id: 'c0', title: 'A')],
      );
      final settings = ReaderViewSettings();
      await loader.loadChapter(
        chapterId: 'c0',
        content: ReaderChapterContent(title: 'A', content: '<p>内容内容内容</p>'),
        pageWidth: 400,
        pageHeight: 0,
        settings: settings,
        prepareScrollLayout: true,
      );
      loader.setActive('c0');
      loader.ensureScrollLayoutForNeighbors(
        'c0',
        pageWidth: 400,
        settings: settings,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final data = loader.getByChapterId('c0')!;
      expect(data.hasPreciseHeights, isTrue);

      loader.rekeyAndRecomputeHeights('c0', 500, settings, 1.0);
      expect(loader.getByChapterId('c0')!.hasPreciseHeights, isTrue);
    });
  });
}
