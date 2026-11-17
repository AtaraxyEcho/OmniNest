import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_detail_text_content.dart';

/// 章节来自本地解析的 EPUB 目录，上千条是常见规模；页签内容必须懒建。
List<ParsedChapter> _chapters(int count) => [
  for (var i = 0; i < count; i++)
    ParsedChapter(
      number: i,
      title: 'Chapter $i',
      xhtmlContent: '',
      charCount: 1200 + i,
    ),
];

Future<void> _pumpDetail(
  WidgetTester tester, {
  required List<ParsedChapter> chapters,
  List<ReaderBookmark> bookmarks = const [],
  void Function(String chapterId, {required bool resume, int? charOffset})?
  onReadChapter,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        readerItemBookmarksProvider.overrideWith(
          (ref, itemId) async => bookmarks,
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: OmniNestTheme.dark(),
        home: Scaffold(
          body: ReaderDetailTextContent(
            item: const ReaderItem(
              id: 'item-1',
              title: 'Book',
              itemType: 'EPUB',
              addedToBookshelf: true,
              updatedAt: null,
            ),
            progress: null,
            chapters: chapters,
            bookshelfBusy: false,
            onToggleBookshelf: () {},
            onReadChapter:
                onReadChapter ??
                (chapterId, {required resume, int? charOffset}) {},
            onEditMetadata: () {},
            onReparse: () {},
            onDelete: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

int _builtChapters(WidgetTester tester) {
  return tester
      .widgetList<Text>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && (widget.data ?? '').startsWith('Chapter '),
        ),
      )
      .length;
}

class _FakeReaderLocalProgressStore implements ReaderLocalProgressStore {
  @override
  Future<void> save({
    required String itemId,
    required double chapterProgress,
    required String mode,
    String? chapterId,
    int charOffset = 0,
    double? bookProgress,
    String? pageId,
    int? pageIndex,
    String? pageFingerprint,
    String? sourceId,
    int? sourcePageIndex,
    String? catalogKey,
    int? manifestVersion,
    double? intraPageOffset,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<Map<String, dynamic>?> load(String itemId, String chapterId) async =>
      null;

  @override
  Future<Map<String, dynamic>?> loadLatest(String itemId) async => null;

  @override
  Future<void> clear(String itemId) async {}
}

void main() {
  setUp(() => ReaderLocalProgress.init(_FakeReaderLocalProgressStore()));

  testWidgets('切到章节页签后只建可见章节行', (tester) async {
    await _pumpDetail(tester, chapters: _chapters(800));

    await tester.tap(find.text('章节'));
    await tester.pumpAndSettle();

    final built = _builtChapters(tester);
    expect(built, greaterThan(0));
    expect(built, lessThan(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('滚动到末章后补建', (tester) async {
    await _pumpDetail(tester, chapters: _chapters(800));
    await tester.tap(find.text('章节'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Chapter 799'),
      find.byType(CustomScrollView),
      const Offset(0, -1200),
      maxIteration: 40,
    );
    await tester.pumpAndSettle();

    expect(find.text('Chapter 799'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('章节页签按身份键跳转，而不是顺位键', (tester) async {
    // TXT 的真实身份键是 't{正文起点}'；目录行硬编码 'chapter_$i' 时路由查不到章，
    // 点任意一章都是"章节加载失败"，当前阅读章也永远不亮。
    final tapped = <String>[];
    await _pumpDetail(
      tester,
      chapters: [
        ParsedChapter(
          number: 1,
          title: '第一章',
          xhtmlContent: '',
          charCount: 600,
          chapterKey: 't0',
        ),
        ParsedChapter(
          number: 2,
          title: '第二章',
          xhtmlContent: '',
          charCount: 600,
          chapterKey: 't1280',
        ),
      ],
      onReadChapter:
          (chapterId, {required resume, int? charOffset}) =>
              tapped.add(chapterId),
    );

    await tester.tap(find.text('章节'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第二章'));
    await tester.pumpAndSettle();

    expect(tapped, ['t1280']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点按书签按 chapterId 与章内偏移跳转', (tester) async {
    final jumps = <String>[];
    await _pumpDetail(
      tester,
      chapters: [
        ParsedChapter(
          number: 1,
          title: '第一章',
          xhtmlContent: '',
          charCount: 600,
          chapterKey: 't0',
        ),
        ParsedChapter(
          number: 2,
          title: '第二章',
          xhtmlContent: '',
          charCount: 600,
          chapterKey: 't1280',
        ),
      ],
      bookmarks: [
        const ReaderBookmark(
          id: 'bm-1',
          readerItemId: 'item-1',
          chapterId: 't1280',
          charOffset: 640,
          progressPercent: 0.4,
          createdAt: null,
        ),
      ],
      onReadChapter:
          (chapterId, {required resume, int? charOffset}) =>
              jumps.add('$chapterId:$charOffset:$resume'),
    );

    await tester.tap(find.text('书签'));
    await tester.pumpAndSettle();

    // 标签取所在章节名，不再每条书签都显示书名。
    expect(find.text('第二章'), findsWidgets);
    await tester.tap(find.text('第二章').last);
    await tester.pumpAndSettle();

    expect(jumps, ['t1280:640:false']);
    expect(tester.takeException(), isNull);
  });
}
