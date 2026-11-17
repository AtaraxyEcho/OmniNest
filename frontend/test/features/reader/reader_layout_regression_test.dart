import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_chapter_hierarchy.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_item_detail_widgets.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('page layout invalidation', () {
    final blocks = parseBlocks(
      '<p>${List<String>.filled(180, 'responsive reading text').join(' ')}</p>',
    );
    final content = ReaderChapterContent(
      title: 'Chapter',
      content: '<p>responsive reading text</p>',
    );
    final settings = ReaderViewSettings(
      fontFamily: 'sans',
      fontSize: 18,
      lineHeight: 1.5,
    );

    test('reuses navigator only while dimensions and typography match', () {
      final data = ChapterData(
        chapterId: 'chapter-1',
        content: content,
        blocks: blocks,
      );

      final initial = data.getOrCreatePageNavigator(560, 640, settings);
      final unchanged = data.getOrCreatePageNavigator(560, 640, settings);
      final resized = data.getOrCreatePageNavigator(560, 820, settings);
      final reformatted = data.getOrCreatePageNavigator(
        560,
        820,
        settings.copyWith(lineHeight: 2.4),
      );

      expect(identical(initial, unchanged), isTrue);
      expect(identical(initial, resized), isFalse);
      expect(identical(resized, reformatted), isFalse);
    });

    test('larger line height consumes more space and fits less text', () {
      final compact = ReaderViewSettings(
        fontFamily: 'sans',
        fontSize: 18,
        lineHeight: 1.5,
      );
      final spacious = compact.copyWith(lineHeight: 2.4);

      final compactHeight = ReaderPaginationEngine.measureBlockHeight(
        blocks.single,
        320,
        compact,
      );
      final spaciousHeight = ReaderPaginationEngine.measureBlockHeight(
        blocks.single,
        320,
        spacious,
      );
      final compactPage = ReaderPaginationEngine.computePage(
        blocks,
        320,
        360,
        compact,
        0,
      );
      final spaciousPage = ReaderPaginationEngine.computePage(
        blocks,
        320,
        360,
        spacious,
        0,
      );

      expect(spaciousHeight, greaterThan(compactHeight));
      expect(spaciousPage, isNotNull);
      expect(compactPage, isNotNull);
      expect(spaciousPage!.endCharOffset, lessThan(compactPage!.endCharOffset));
    });

    test(
      'rekeys cached chapter and recomputes height for new settings',
      () async {
        const chapter = ReaderChapter(id: 'chapter-1', title: 'Chapter');
        final loader = ReaderContentLoader(allChapters: const [chapter]);
        final loaded = await loader.loadChapter(
          chapterId: chapter.id,
          content: ReaderChapterContent(
            title: chapter.title,
            content:
                '<p>${List<String>.filled(120, 'cached reading text').join(' ')}</p>',
          ),
          pageWidth: 320,
          pageHeight: 360,
          settings: settings,
        );
        final previousHeight = loaded.cumulativeHeights.last;
        final spacious = settings.copyWith(lineHeight: 2.4);

        loader.rekeyAndRecomputeHeights(chapter.id, 320, spacious, 1);

        expect(loader.get(chapter.id, settings), isNull);
        expect(loader.get(chapter.id, spacious), same(loaded));
        expect(loaded.cumulativeHeights.last, greaterThan(previousHeight));
      },
    );
  });

  group('chapter hierarchy', () {
    const chapters = [
      ReaderChapter(id: 'volume', title: 'Volume', level: 0),
      ReaderChapter(id: 'chapter', title: 'Chapter', level: 1),
      ReaderChapter(id: 'section', title: 'Section', level: 2),
      ReaderChapter(id: 'sibling', title: 'Sibling', level: 1),
    ];

    test('a collapsed ancestor hides every descendant level', () {
      final visible = ReaderChapterHierarchy.visibleChapters(chapters, {
        'volume',
      });

      expect(visible.map((chapter) => chapter.id), ['volume']);
    });

    test('a collapsed nested chapter keeps its siblings visible', () {
      final visible = ReaderChapterHierarchy.visibleChapters(chapters, {
        'chapter',
      });

      expect(visible.map((chapter) => chapter.id), [
        'volume',
        'chapter',
        'sibling',
      ]);
      expect(ReaderChapterHierarchy.hasChildren(chapters, chapters[1]), isTrue);
      expect(
        ReaderChapterHierarchy.hasChildren(chapters, chapters[3]),
        isFalse,
      );
    });
  });

  test('detail layout uses bounded desktop content and directory height', () {
    final mobile = ReaderDetailLayout.resolve(420);
    final desktop = ReaderDetailLayout.resolve(1440);

    expect(mobile.isDesktop, isFalse);
    expect(mobile.previewChapterCount, 6);
    expect(desktop.isDesktop, isTrue);
    expect(desktop.maxContentWidth, 1080);
    expect(desktop.directoryMaxHeight, 560);
    expect(desktop.previewChapterCount, 10);
    expect(desktop.coverWidth, 216);
    expect(desktop.coverHeight, 307);
    expect(mobile.coverWidth, 164);
    expect(mobile.coverHeight, 233);
  });
}
