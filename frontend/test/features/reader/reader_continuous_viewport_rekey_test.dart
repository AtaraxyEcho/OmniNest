import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReaderContentLoader continuous viewport rekey', () {
    test(
      'rekeyAndRecomputeHeightsForChapters remeasures window chapters',
      () async {
        final chapters = [
          ReaderChapter(id: 'c0', title: 'A'),
          ReaderChapter(id: 'c1', title: 'B'),
        ];
        final loader = ReaderContentLoader(allChapters: chapters);
        final settings = ReaderViewSettings(fontSize: 18, lineHeight: 1.8);
        final html = '<p>${'字' * 400}</p>';

        await loader.loadChapter(
          chapterId: 'c0',
          content: ReaderChapterContent(title: 'A', content: html),
          pageWidth: 320,
          pageHeight: 0,
          settings: settings,
          prepareScrollLayout: true,
        );
        await loader.loadChapter(
          chapterId: 'c1',
          content: ReaderChapterContent(title: 'B', content: html),
          pageWidth: 320,
          pageHeight: 0,
          settings: settings,
          prepareScrollLayout: true,
        );

        final narrowHeight0 = loader.chapterScrollHeight('c0');
        final narrowHeight1 = loader.chapterScrollHeight('c1');
        expect(narrowHeight0, greaterThan(0));
        expect(narrowHeight1, greaterThan(0));

        // 宽列应比窄列更矮（换行更少）。
        loader.rekeyAndRecomputeHeightsForChapters(
          const ['c0', 'c1'],
          720,
          settings,
          1.0,
        );

        final wideHeight0 = loader.chapterScrollHeight('c0');
        final wideHeight1 = loader.chapterScrollHeight('c1');
        expect(wideHeight0, greaterThan(0));
        expect(wideHeight0, lessThan(narrowHeight0));
        expect(wideHeight1, greaterThan(0));
        expect(wideHeight1, lessThan(narrowHeight1));
        expect(loader.isScrollLayoutReady('c0'), isTrue);
        expect(loader.isScrollLayoutReady('c1'), isTrue);
      },
    );

    test('neighbor helpers expose ids and readiness', () async {
      final chapters = [
        ReaderChapter(id: 'c0', title: 'A'),
        ReaderChapter(id: 'c1', title: 'B'),
        ReaderChapter(id: 'c2', title: 'C'),
      ];
      final loader = ReaderContentLoader(allChapters: chapters);
      final settings = ReaderViewSettings();
      await loader.loadChapter(
        chapterId: 'c1',
        content: ReaderChapterContent(title: 'B', content: '<p>中间章内容</p>'),
        pageWidth: 400,
        pageHeight: 0,
        settings: settings,
        prepareScrollLayout: true,
      );

      expect(loader.chapterIds, ['c0', 'c1', 'c2']);
      expect(loader.neighborChapterIds('c1'), ['c0', 'c2']);
      expect(loader.isScrollLayoutReady('c1'), isTrue);
      expect(loader.isScrollLayoutReady('c0'), isFalse);
      expect(loader.chapterScrollHeight('c1'), greaterThan(0));
      expect(loader.chapterScrollHeight('c0'), 0);
    });
  });
}
