import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_progress_save_coordinator.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_navigation.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  group('章节导航意图', () {
    test('目录、前进和后退使用互不混淆的进入位置', () {
      const toc = ReaderChapterNavigationIntent.start(offerReturn: true);
      const next = ReaderChapterNavigationIntent.start();
      const previous = ReaderChapterNavigationIntent.end();

      expect(toc.entryPoint, ReaderChapterEntryPoint.start);
      expect(toc.offerReturn, isTrue);
      expect(next.entryPoint, ReaderChapterEntryPoint.start);
      expect(next.offerReturn, isFalse);
      expect(previous.entryPoint, ReaderChapterEntryPoint.end);
    });

    test('字符偏移和锚点保留明确目标', () {
      const offset = ReaderChapterNavigationIntent.offset(128);
      const anchor = ReaderChapterNavigationIntent.anchor('section-2');

      expect(offset.charOffset, 128);
      expect(anchor.anchorHref, 'section-2');
    });
  });

  test('高频进度更新只写入最后一条', () async {
    final writes = <ReaderProgressSnapshot>[];
    final coordinator = ReaderProgressSaveCoordinator(
      debounce: const Duration(milliseconds: 20),
      writer: (snapshot) async {
        writes.add(snapshot);
      },
    );

    coordinator.schedule(_snapshot(10));
    coordinator.schedule(_snapshot(20));
    coordinator.schedule(_snapshot(30));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await coordinator.flush();

    expect(writes, hasLength(1));
    expect(writes.single.charOffset, 30);
    await coordinator.dispose();
  });

  test('分页预加载跳过滚动高度测量并复用并发解析', () async {
    const chapter = ReaderChapter(id: 'chapter-1', title: '第一章');
    final loader = ReaderContentLoader(allChapters: const [chapter]);
    final content = ReaderChapterContent(
      title: chapter.title,
      content: '<p>${List<String>.filled(80, '分页内容').join(' ')}</p>',
    );
    final settings = ReaderViewSettings();

    final results = await Future.wait([
      loader.loadChapter(
        chapterId: chapter.id,
        content: content,
        pageWidth: 320,
        pageHeight: 480,
        settings: settings,
        prepareScrollLayout: false,
      ),
      loader.loadChapter(
        chapterId: chapter.id,
        content: content,
        pageWidth: 320,
        pageHeight: 480,
        settings: settings,
        prepareScrollLayout: false,
      ),
    ]);

    expect(results[0], same(results[1]));
    expect(results[0].cumulativeHeights, isEmpty);
    expect(loader.contentFor(chapter.id), same(content));

    final scrollReady = await loader.loadChapter(
      chapterId: chapter.id,
      content: content,
      pageWidth: 320,
      pageHeight: 0,
      settings: settings,
    );
    expect(scrollReady, same(results[0]));
    expect(scrollReady.cumulativeHeights, isNotEmpty);
  });

  test('相邻章节预加载内容可供切章立即复用', () async {
    const chapters = [
      ReaderChapter(id: 'chapter-1', title: '第一章'),
      ReaderChapter(id: 'chapter-2', title: '第二章'),
    ];
    final loader = ReaderContentLoader(allChapters: chapters);
    final settings = ReaderViewSettings();
    const content = ReaderChapterContent(
      title: '第二章',
      content: '<p>已经预加载的章节内容</p>',
    );

    loader.setActive('chapter-1');
    await loader.loadChapter(
      chapterId: 'chapter-2',
      content: content,
      pageWidth: 320,
      pageHeight: 480,
      settings: settings,
      prepareScrollLayout: false,
    );

    // 邻章预载后 HTML 会被 drop 以省内存；切章复用的是 blocks。
    expect(loader.contentFor('chapter-2'), isNull);
    final neighbor = loader.get('chapter-2', settings);
    expect(neighbor, isNotNull);
    expect(neighbor!.blocks, isNotEmpty);
    expect(neighbor.content.content, isEmpty);
    expect(neighbor.content.title, '第二章');
  });

  test('长段落连续翻页复用视觉行测量结果', () {
    final settings = ReaderViewSettings();
    final blocks = parseBlocks(
      '<p>${List<String>.filled(1200, '连续分页内容').join(' ')}</p>',
    );
    final layout = ReaderPaginationEngine.preparePageLayout(
      blocks,
      320,
      480,
      settings,
    );

    final first = layout.computePage(0);
    final second = layout.computePage(first!.endCharOffset);
    final measurementsAfterSecond = layout.visualLineMeasurementCount;
    final third = layout.computePage(second!.endCharOffset);

    expect(third, isNotNull);
    expect(layout.visualLineMeasurementCount, measurementsAfterSecond);
  });

  test('超长文本块不会在两千条视觉行处截断', () {
    final settings = ReaderViewSettings();
    final blocks = parseBlocks(List<String>.filled(2105, '<p>测</p>').join());

    final lines = ReaderPaginationEngine.measureVisualLines(
      blocks.single,
      320,
      settings,
      1,
      blockGlobalOffset: 0,
    );

    expect(lines.length, greaterThan(2000));
    expect(lines.last.globalEnd, 2105);
  });

  test('异步页码定位不限制五百页并可恢复长章节位置', () async {
    final navigator = PageNavigator(
      blocks: parseBlocks('<p>测试</p>'),
      computeFn: (startCharOffset) {
        if (startCharOffset >= 900) {
          return null;
        }
        return PageSlice(
          startIndex: 0,
          endIndex: 1,
          startCharOffset: startCharOffset,
          endCharOffset: startCharOffset + 1,
        );
      },
    );

    final page = await navigator.findPageByCharOffset(750);

    expect(page, 750);
    expect(navigator.getSlice(page!), isNotNull);
  });

  testWidgets('连续翻页命令在动画完成前只提交一次', (tester) async {
    final controller = ReaderPageTurnController();
    final callbacks = _TestPageTurnCallbacks();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: ReaderPageView(
            controller: controller,
            state: PagedState(
              chapterId: 'chapter-1',
              pageIndex: 0,
              pageCount: 3,
              hasMore: false,
              hasNextChapter: true,
            ),
            pageBuilder: (index) => Text('page-$index'),
            callbacks: callbacks,
            surfaceColor: Colors.white,
          ),
        ),
      ),
    );

    controller.next();
    controller.next();
    controller.next();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 120));

    expect(callbacks.pages, [1]);
  });

  testWidgets('章节边界加载期间连续点击只触发一次', (tester) async {
    final controller = ReaderPageTurnController();
    final callbacks = _TestPageTurnCallbacks();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: ReaderPageView(
            controller: controller,
            state: PagedState(
              chapterId: 'chapter-1',
              pageIndex: 0,
              pageCount: 1,
              hasMore: false,
              hasNextChapter: true,
            ),
            pageBuilder: (index) => Text('page-$index'),
            callbacks: callbacks,
            surfaceColor: Colors.white,
          ),
        ),
      ),
    );

    controller.next();
    controller.next();
    controller.next();
    await tester.pump();

    expect(callbacks.nextChapterCount, 1);
  });

  testWidgets('滑动模式可从章节末页拖拽进入下一章', (tester) async {
    final callbacks = _TestPageTurnCallbacks();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: ReaderPageView(
            state: PagedState(
              chapterId: 'chapter-1',
              pageIndex: 0,
              pageCount: 1,
              hasMore: false,
              hasNextChapter: true,
            ),
            pageBuilder: (index) => Text('page-$index'),
            callbacks: callbacks,
            surfaceColor: Colors.white,
          ),
        ),
      ),
    );

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();

    expect(callbacks.nextChapterCount, 1);
  });

  testWidgets('淡入模式可从章节末页拖拽进入下一章', (tester) async {
    final callbacks = _TestPageTurnCallbacks();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: ReaderPageView(
            state: PagedState(
              chapterId: 'chapter-1',
              pageIndex: 0,
              pageCount: 1,
              hasMore: false,
              hasNextChapter: true,
            ),
            pageBuilder: (index) => Text('page-$index'),
            callbacks: callbacks,
            surfaceColor: Colors.white,
            turnMode: PageTurnMode.fade,
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ReaderPageView), const Offset(-320, 0));
    await tester.pumpAndSettle();

    expect(callbacks.nextChapterCount, 1);
  });

  testWidgets('从滑动切换为覆盖模式后使用覆盖动画翻页', (tester) async {
    final controller = ReaderPageTurnController();
    final callbacks = _TestPageTurnCallbacks();
    final mode = ValueNotifier<PageTurnMode>(PageTurnMode.slide);
    addTearDown(controller.dispose);
    addTearDown(mode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<PageTurnMode>(
          valueListenable: mode,
          builder:
              (context, value, child) => SizedBox.expand(
                child: ReaderPageView(
                  controller: controller,
                  state: PagedState(
                    chapterId: 'chapter-1',
                    pageIndex: 0,
                    pageCount: 3,
                    hasMore: false,
                  ),
                  pageBuilder: (index) => Text('page-$index'),
                  callbacks: callbacks,
                  surfaceColor: Colors.white,
                  turnMode: value,
                ),
              ),
        ),
      ),
    );

    mode.value = PageTurnMode.cover;
    await tester.pump();
    controller.next();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    expect(
      transforms.any((widget) => widget.transform.storage[12].abs() > 0),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(callbacks.pages, [1]);
  });

  testWidgets('动画完成并同步页码后下一次命令继续前进', (tester) async {
    final controller = ReaderPageTurnController();
    final pages = <int>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: _UpdatingPageHost(controller: controller, pages: pages),
      ),
    );

    controller.next();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    controller.next();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(pages, [1, 2]);
  });
}

ReaderProgressSnapshot _snapshot(int charOffset) {
  return ReaderProgressSnapshot(
    chapterId: 'chapter-1',
    charOffset: charOffset,
    chapterProgress: charOffset / 100,
  );
}

class _TestPageTurnCallbacks implements PageTurnCallbacks {
  final List<int> pages = <int>[];
  int nextChapterCount = 0;

  @override
  void onNextChapter() {
    nextChapterCount++;
  }

  @override
  void onPageChanged(int pageIndex) {
    pages.add(pageIndex);
  }

  @override
  void onPreviousChapter() {}

  @override
  void onToggleControls() {}
}

class _UpdatingPageHost extends StatefulWidget {
  const _UpdatingPageHost({required this.controller, required this.pages});

  final ReaderPageTurnController controller;
  final List<int> pages;

  @override
  State<_UpdatingPageHost> createState() => _UpdatingPageHostState();
}

class _UpdatingPageHostState extends State<_UpdatingPageHost>
    implements PageTurnCallbacks {
  int _pageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ReaderPageView(
        controller: widget.controller,
        state: PagedState(
          chapterId: 'chapter-1',
          pageIndex: _pageIndex,
          pageCount: 3,
          hasMore: false,
        ),
        pageBuilder: (index) => Text('page-$index'),
        callbacks: this,
        surfaceColor: Colors.white,
      ),
    );
  }

  @override
  void onNextChapter() {}

  @override
  void onPageChanged(int pageIndex) {
    widget.pages.add(pageIndex);
    setState(() => _pageIndex = pageIndex);
  }

  @override
  void onPreviousChapter() {}

  @override
  void onToggleControls() {}
}
