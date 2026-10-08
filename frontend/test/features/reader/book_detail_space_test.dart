import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/book_detail_space.dart';

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

/// 书籍详情空间（原型 BookDetail）行为测试。
void main() {
  setUp(() => ReaderLocalProgress.init(_FakeReaderLocalProgressStore()));
  testWidgets('渲染身份/动作/进度/关于/章节并回调打开章节', (tester) async {
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
                      (chapterId, {required resume}) => opened.add(chapterId),
                ),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readerItemDetailProvider('book-1').overrideWith(
            (ref) async => ReaderItemDetail(
              item: ReaderItem(
                id: 'book-1',
                title: 'The Art of Stillness',
                itemType: 'EPUB',
                updatedAt: DateTime(2026, 10, 1),
                authorName: 'Pico Iyer',
                description: 'A thoughtful meditation on sitting still.',
                progressPercent: 0.64,
                addedToBookshelf: false,
              ),
              chapters: [
                ReaderChapter(id: 'ch-1', title: 'A quiet beginning'),
                ReaderChapter(id: 'ch-2', title: 'The shape of attention'),
                ReaderChapter(id: 'ch-3', title: 'Room to breathe'),
              ],
            ),
          ),
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

    // 身份区与主按钮。
    expect(find.text('The Art of Stillness'), findsOneWidget);
    expect(find.text('Pico Iyer'), findsOneWidget);
    expect(find.text('继续阅读'), findsOneWidget);

    // 章节列表渲染，点击章节回调章节 id。
    expect(find.text('01'), findsOneWidget);
    await tester.tap(find.text('The shape of attention'));
    expect(opened, ['ch-2']);

    // 无本地续读进度时主按钮从第一章开始。
    await tester.tap(find.text('继续阅读'));
    expect(opened, ['ch-2', 'ch-1']);
    expect(tester.takeException(), isNull);
  });
}
