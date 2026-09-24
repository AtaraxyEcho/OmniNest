import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/domain/parsed_book.dart';
import 'package:omninest/features/reader/domain/reader_item.dart';
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
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
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
            onReadChapter: (chapterId, {required resume}) {},
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
    String? pageId,
    int? pageIndex,
    String? pageFingerprint,
    String? sourceId,
    int? sourcePageIndex,
    String? catalogKey,
    int? manifestVersion,
    double? intraPageOffset,
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
}
