import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/book_detail_space.dart';

class _FakeReaderLocalProgressStore implements ReaderLocalProgressStore {
  _FakeReaderLocalProgressStore({this.latest});

  /// 替离线阅读留在 SQLite 里的那一份进度；null 表示本机没读过。
  final Map<String, dynamic>? latest;

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
  Future<Map<String, dynamic>?> loadLatest(String itemId) async => latest;

  @override
  Future<void> clear(String itemId) async {}
}

/// 详情响应里的章节恒为空：后端 `ReaderItemDetailDto` 只有 item 与 progress，
/// 目录一律来自服务端清单（与桌面端同源）。
ReaderItemDetail _detailWithoutChapters({
  String itemType = 'EPUB',
  double? progressPercent = 0.64,
}) {
  return ReaderItemDetail(
    item: ReaderItem(
      id: 'book-1',
      title: 'The Art of Stillness',
      itemType: itemType,
      updatedAt: DateTime(2026, 10, 1),
      authorName: 'Pico Iyer',
      description: 'A thoughtful meditation on sitting still.',
      progressPercent: progressPercent,
      addedToBookshelf: false,
    ),
  );
}

ParsedBook _manifestBook() {
  return ParsedBook(
    title: 'The Art of Stillness',
    chapters: [
      for (var index = 0; index < 3; index++)
        ParsedChapter(
          number: index + 1,
          title:
              const [
                'A quiet beginning',
                'The shape of attention',
                'Room to breathe',
              ][index],
          xhtmlContent: '<p>body $index</p>',
          charCount: 120,
          sourceStartOffset: index * 120,
          sourceEndOffset: (index + 1) * 120,
        ),
    ],
  );
}

/// 卷（level 0）+ 章（level 1）的多级清单：正文全在 level>0 上。
ParsedBook _volumeBook() {
  return ParsedBook(
    title: '分卷书',
    chapters: [
      ParsedChapter(
        number: 1,
        title: '第一卷',
        level: 0,
        xhtmlContent: '<p>卷首</p>',
        charCount: 40,
        sourceStartOffset: 0,
        sourceEndOffset: 40,
      ),
      ParsedChapter(
        number: 2,
        title: '第一章 起风了',
        level: 1,
        xhtmlContent: '<p>甲</p>',
        charCount: 120,
        sourceStartOffset: 40,
        sourceEndOffset: 160,
      ),
      ParsedChapter(
        number: 3,
        title: '第二章 落雨时',
        level: 1,
        xhtmlContent: '<p>乙</p>',
        charCount: 120,
        sourceStartOffset: 160,
        sourceEndOffset: 280,
      ),
    ],
  );
}

/// 手工可控的清单 Future：让"目录仍在解析"这一状态在用例里可停留、可完成。
class _ManifestGate {
  final Completer<ParsedBook> _completer = Completer<ParsedBook>();

  Future<ParsedBook> get future => _completer.future;

  void complete(ParsedBook book) {
    if (!_completer.isCompleted) {
      _completer.complete(book);
    }
  }
}

/// 书籍详情空间（原型 BookDetail）行为测试。
void main() {
  setUp(() => ReaderLocalProgress.init(_FakeReaderLocalProgressStore()));

  /// 摆好移动壳层里的详情空间，返回被点开的章节 id 列表。
  Future<List<String>> pumpSpace(
    WidgetTester tester, {
    required ReaderItemDetail Function() detail,
    required Future<ParsedBook> Function() manifest,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final opened = <String>[];
    final router = GoRouter(
      initialLocation: '/reader/items/book-1',
      routes: [
        GoRoute(
          path: '/reader/items/:itemId',
          builder:
              (context, state) => MobileShellScope(
                hosted: true,
                child: BookDetailSpace(
                  itemId: state.pathParameters['itemId']!,
                  bookshelfBusy: false,
                  bookshelfAdded: false,
                  onToggleBookshelf: () async {},
                  onReadChapter:
                      (chapterId, {required resume, int? charOffset}) =>
                          opened.add(chapterId),
                ),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readerItemDetailProvider(
            'book-1',
          ).overrideWith((ref) async => detail()),
          parsedBookProvider('book-1').overrideWith((ref) => manifest()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.dark(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('渲染身份/动作/进度/关于/章节并回调打开章节', (tester) async {
    final opened = await pumpSpace(
      tester,
      detail: () => _detailWithoutChapters(),
      manifest: () async => _manifestBook(),
    );

    // 身份区与主按钮。
    expect(find.text('The Art of Stillness'), findsOneWidget);
    expect(find.text('Pico Iyer'), findsOneWidget);
    expect(find.text('继续阅读'), findsOneWidget);

    // 章节列表按清单渲染，点击章节回调章节 id。
    expect(find.text('01'), findsOneWidget);
    await tester.tap(find.text('The shape of attention'));
    await tester.pumpAndSettle();
    expect(opened, ['chapter_1']);

    // 服务端进度已读到第二章，主按钮按同一份清单续读。
    await tester.tap(find.text('继续阅读'));
    await tester.pumpAndSettle();
    expect(opened, ['chapter_1', 'chapter_0']);
    expect(tester.takeException(), isNull);
  });

  for (final itemType in <String>['TXT', 'EPUB']) {
    testWidgets('$itemType 无本地进度时从清单首章开始阅读', (tester) async {
      final opened = await pumpSpace(
        tester,
        detail:
            () => _detailWithoutChapters(
              itemType: itemType,
              progressPercent: null,
            ),
        manifest: () async => _manifestBook(),
      );

      // 详情响应从不带章节：此前主按钮读 detail.chapters，空列表下点了没反应。
      await tester.tap(find.text('开始阅读'));
      await tester.pumpAndSettle();
      expect(opened, ['chapter_0']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('清单仍在解析时目录给骨架，主按钮不给死入口', (tester) async {
    final gate = _ManifestGate();
    final opened = await pumpSpace(
      tester,
      detail:
          () => _detailWithoutChapters(itemType: 'TXT', progressPercent: null),
      manifest: () => gate.future,
    );

    expect(find.text('开始阅读'), findsOneWidget);
    await tester.tap(find.text('开始阅读'));
    await tester.pump();
    expect(opened, isEmpty);

    gate.complete(_manifestBook());
    await tester.pumpAndSettle();
    expect(find.text('Room to breathe'), findsOneWidget);
    await tester.tap(find.text('开始阅读'));
    await tester.pumpAndSettle();
    expect(opened, ['chapter_0']);
  });

  testWidgets('清单解析失败时目录给重试入口', (tester) async {
    await pumpSpace(
      tester,
      detail: () => _detailWithoutChapters(itemType: 'TXT'),
      manifest: () async => throw StateError('boom'),
    );

    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// 分卷 EPUB 的正文挂在 level>0：只列顶级就把整本书的正文藏没了。
  testWidgets('分卷书的正文章节照常列入目录', (tester) async {
    final opened = await pumpSpace(
      tester,
      detail: () => _detailWithoutChapters(progressPercent: null),
      manifest: () async => _volumeBook(),
    );

    expect(find.text('第一卷'), findsOneWidget);
    expect(find.text('第一章 起风了'), findsOneWidget);
    expect(find.text('第二章 落雨时'), findsOneWidget);

    await tester.tap(find.text('第二章 落雨时'));
    await tester.pumpAndSettle();
    expect(opened, ['chapter_2']);
  });

  /// 离线读完一章后 item 上的百分比还是旧的：进度必须取本地与服务端里较新一份，
  /// 否则进度块整段消失，主按钮退回"开始阅读"。
  testWidgets('本地进度比条目上的旧百分比新时按本地显示进度', (tester) async {
    ReaderLocalProgress.init(
      _FakeReaderLocalProgressStore(
        latest: const {
          'chapterId': 'chapter_1',
          'charOffset': 40,
          'bookProgress': 0.5,
          'updatedAt': '2026-10-02T01:00:00.000Z',
        },
      ),
    );

    await pumpSpace(
      tester,
      detail: () => _detailWithoutChapters(progressPercent: null),
      manifest: () async => _manifestBook(),
    );

    expect(find.text('50%'), findsOneWidget);
    expect(find.text('继续阅读'), findsOneWidget);
  });
}
