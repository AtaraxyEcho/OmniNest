import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_book_detail_page.dart';
import 'package:omninest/app/desktop/pages/desktop_book_metadata_dialog.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/features/reader/domain/parsed_book.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';

import 'desktop_test_harness.dart';

final ReaderItemDetail _detail = ReaderItemDetail(
  item: ReaderItem(
    id: 'b-1',
    itemType: 'EPUB',
    title: 'The Quiet Arrival',
    authorName: 'Ines Aoki',
    description: 'Essays on staying still while everything moves.',
    progressPercent: 64,
    genres: const ['Essays', 'Nature'],
    createdAt: DateTime(2026, 9, 12),
    updatedAt: DateTime(2026, 11, 14),
  ),
  progress: ReaderProgress(
    readerItemId: 'b-1',
    charOffset: 1200,
    progressPercent: 64,
    readingMode: 'page',
    chapterId: 'c-2',
    updatedAt: DateTime(2026, 11, 14),
  ),
  chapters: const [
    ReaderChapter(id: 'c-1', title: 'Foreword', chapterNumber: 1),
    ReaderChapter(id: 'c-2', title: 'Kyoto, Winter', chapterNumber: 2),
    ReaderChapter(id: 'c-3', title: 'Sitting Still', chapterNumber: 3),
  ],
);

/// 后端 `ReaderItemDetailDto` 不下发 chapters；桌面书详必须能只用文本清单
/// 把目录与阅读入口撑起来。
final ParsedBook _parsedBook = ParsedBook(
  chapters: [
    ParsedChapter(
      number: 1,
      title: 'Foreword',
      xhtmlContent: '<p>A</p>',
      charCount: 1,
      chapterKey: 'c-1',
    ),
    ParsedChapter(
      number: 2,
      title: 'Kyoto, Winter',
      xhtmlContent: '<p>B</p>',
      charCount: 2,
      chapterKey: 'c-2',
    ),
  ],
);

final ReaderItemDetail _detailNoChapters = ReaderItemDetail(
  item: _detail.item,
  progress: _detail.progress,
  chapters: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面书籍详情：英雄区 + 统计条 + 章节分页', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          readerItemDetailProvider.overrideWith((ref, id) async => _detail),
          parsedBookProvider.overrideWith((ref, id) async => _parsedBook),
          readerItemAnnotationsProvider.overrideWith(
            (ref, id) async => const <ReaderAnnotation>[],
          ),
          readerItemBookmarksProvider.overrideWith(
            (ref, id) async => const <ReaderBookmark>[],
          ),
          readerStatsOverviewProvider.overrideWith(
            (ref) async => const ReaderStatsOverview(
              dailyMinutes: [],
              completedCount: 0,
              inProgressCount: 1,
              totalItems: 1,
              inProgressItems: [],
            ),
          ),
        ],
        child: wrapDesktop(
          const DesktopShellScope(
            hosted: true,
            child: DesktopBookDetailPage(itemId: 'b-1'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(tester.takeException(), isNull);
    expect(find.text('The Quiet Arrival'), findsWidgets);
    expect(find.text('Ines Aoki'), findsWidgets);
    expect(find.text('PROGRESS'), findsOneWidget);
    expect(find.text('CHAPTERS'), findsOneWidget);
    expect(find.textContaining('Essays on staying still'), findsOneWidget);
    // 四页签与 About 的 spec 卡
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Publisher'), findsOneWidget);

    await tester.tap(find.text('Notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      find.textContaining('Highlights, notes and bookmarks'),
      findsOneWidget,
    );

    await tester.tap(find.text('Chapters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('Kyoto, Winter'), findsOneWidget);
    expect(find.text('Sitting Still'), findsOneWidget);
  });

  testWidgets('detail 无 chapters 时目录与阅读入口由文本清单补齐', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          readerItemDetailProvider.overrideWith(
            (ref, id) async => _detailNoChapters,
          ),
          parsedBookProvider.overrideWith((ref, id) async => _parsedBook),
          readerItemAnnotationsProvider.overrideWith(
            (ref, id) async => const <ReaderAnnotation>[],
          ),
          readerItemBookmarksProvider.overrideWith(
            (ref, id) async => const <ReaderBookmark>[],
          ),
          readerStatsOverviewProvider.overrideWith(
            (ref) async => const ReaderStatsOverview(
              dailyMinutes: [],
              completedCount: 0,
              inProgressCount: 1,
              totalItems: 1,
              inProgressItems: [],
            ),
          ),
        ],
        child: wrapDesktop(
          const DesktopShellScope(
            hosted: true,
            child: DesktopBookDetailPage(itemId: 'b-1'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(tester.takeException(), isNull);
    // 阅读按钮不能再因为 chapters 恒空而置灰。
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DesktopButton &&
            widget.label == 'Continue Reading' &&
            widget.onPressed != null,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Chapters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('Kyoto, Winter'), findsOneWidget);
    expect(find.text('Foreword'), findsWidgets);
  });

  testWidgets('详情页相关书卡复用统一 Reader 封面组件', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final related = ReaderItem(
      id: 'b-2',
      title: 'A Small Weather',
      authorName: 'Mina Ito',
      itemType: 'EPUB',
      contentKind: 'TEXT',
      updatedAt: DateTime(2026, 11, 13),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(
            readerDashboard: ReaderDashboard(
              overview: seededReaderDashboard.overview,
              continueReading: [_detail.item],
              recentItems: [_detail.item, related],
            ),
          ),
          readerItemDetailProvider.overrideWith((ref, id) async => _detail),
          parsedBookProvider.overrideWith((ref, id) async => _parsedBook),
          readerItemAnnotationsProvider.overrideWith(
            (ref, id) async => const <ReaderAnnotation>[],
          ),
          readerItemBookmarksProvider.overrideWith(
            (ref, id) async => const <ReaderBookmark>[],
          ),
          readerStatsOverviewProvider.overrideWith(
            (ref) async => const ReaderStatsOverview(
              dailyMinutes: [],
              completedCount: 0,
              inProgressCount: 1,
              totalItems: 2,
              inProgressItems: [],
            ),
          ),
        ],
        child: wrapDesktop(
          const DesktopShellScope(
            hosted: true,
            child: DesktopBookDetailPage(itemId: 'b-1'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(tester.takeException(), isNull);
    expect(find.byType(DesktopReaderBookCover), findsNWidgets(2));
    expect(find.text('A Small Weather'), findsWidgets);
  });

  testWidgets('编辑元数据打开右侧抽屉而不是居中弹窗', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          readerItemDetailProvider.overrideWith((ref, id) async => _detail),
          parsedBookProvider.overrideWith((ref, id) async => _parsedBook),
          readerItemAnnotationsProvider.overrideWith(
            (ref, id) async => const <ReaderAnnotation>[],
          ),
          readerItemBookmarksProvider.overrideWith(
            (ref, id) async => const <ReaderBookmark>[],
          ),
          readerStatsOverviewProvider.overrideWith(
            (ref) async => const ReaderStatsOverview(
              dailyMinutes: [],
              completedCount: 0,
              inProgressCount: 1,
              totalItems: 1,
              inProgressItems: [],
            ),
          ),
        ],
        child: wrapDesktop(
          const DesktopShellScope(
            hosted: true,
            child: DesktopBookDetailPage(itemId: 'b-1'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    await tester.tap(find.text('Edit metadata'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.byType(DesktopBookMetadataDrawer), findsOneWidget);
    expect(find.byType(DesktopDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('书名清空后保存禁用，并给出字段级错误', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          readerItemDetailProvider.overrideWith((ref, id) async => _detail),
          parsedBookProvider.overrideWith((ref, id) async => _parsedBook),
          readerItemAnnotationsProvider.overrideWith(
            (ref, id) async => const <ReaderAnnotation>[],
          ),
          readerItemBookmarksProvider.overrideWith(
            (ref, id) async => const <ReaderBookmark>[],
          ),
          readerStatsOverviewProvider.overrideWith(
            (ref) async => const ReaderStatsOverview(
              dailyMinutes: [],
              completedCount: 0,
              inProgressCount: 1,
              totalItems: 1,
              inProgressItems: [],
            ),
          ),
        ],
        child: wrapDesktop(
          const DesktopShellScope(
            hosted: true,
            child: DesktopBookDetailPage(itemId: 'b-1'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    await tester.tap(find.text('Edit metadata'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final drawer = find.byType(DesktopBookMetadataDrawer);
    final title =
        find.descendant(of: drawer, matching: find.byType(TextField)).first;
    DesktopButton save() => tester.widget<DesktopButton>(
      find.widgetWithText(DesktopButton, 'Save'),
    );

    expect(save().onPressed, isNotNull);

    // 纯空白按空处理（样例 `!v.title.trim()`）。
    await tester.enterText(title, '   ');
    await tester.pump();

    expect(find.text('A title is required'), findsOneWidget);
    expect(save().onPressed, isNull);

    await tester.enterText(title, 'A quieter arrival');
    await tester.pump();

    expect(find.text('A title is required'), findsNothing);
    expect(save().onPressed, isNotNull);
  });
}
