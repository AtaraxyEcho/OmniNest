// 托管书籍详情页头回归（样例 `.detail-header`：高 84、内衬
// max(18,safe-top) 14 6，左返回右更多都是 48 圆钮，图标为样例同源矢量）。
//
// 现状（本用例即证据）：`ReaderItemDetailPage` 的托管分支把页头交给
// `_DetailBackBar`（48 高文字条 + Icons.arrow_back_rounded 16），
// 并且 `ReaderPageScaffold` 传的是 `headerPadding: EdgeInsets.zero`、
// 托管 body 是不带 SafeArea 的裸 Column —— 页头坐在 y=0，被手机状态栏压住；
// 右上角也没有「更多」。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_item_detail_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_detail_action_sheet.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_detail_header.dart';

/// 44dp 状态栏：Android 手机实测档，用真实 view padding 注入而非页面内猜测。
const double _statusBarInset = 44;

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

ReaderItemDetail _bookDetail({String itemType = 'EPUB'}) {
  return ReaderItemDetail(
    item: ReaderItem(
      id: 'book-1',
      title: 'The Art of Stillness',
      itemType: itemType,
      authorName: 'Pico Iyer',
      description: 'A thoughtful meditation on sitting still.',
      progressPercent: 0.64,
      addedToBookshelf: false,
      updatedAt: null,
    ),
  );
}

ParsedBook _manifest() {
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

Future<void> _pumpHostedDetail(
  WidgetTester tester, {
  String itemType = 'EPUB',
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: _statusBarInset, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);

  final router = GoRouter(
    initialLocation: '/reader/items/book-1',
    routes: [
      GoRoute(
        path: '/reader',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/reader/items/:itemId',
        builder:
            (context, state) => MobileHostedRoute(
              child: ReaderItemDetailPage(
                itemId: state.pathParameters['itemId']!,
              ),
            ),
      ),
      GoRoute(
        path: '/reader/items/:itemId/metadata',
        builder: (context, state) => const Scaffold(body: Text('元数据编辑页桩')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        readerItemDetailProvider(
          'book-1',
        ).overrideWith((ref) async => _bookDetail(itemType: itemType)),
        parsedBookProvider('book-1').overrideWith((ref) async => _manifest()),
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

  // 桩必须落在托管分支上：否则本页用例会在桌面详情视图里空转。
  expect(
    MobileShellScope.isHosted(tester.element(find.byType(ReaderDetailHeader))),
    isTrue,
  );
}

void main() {
  setUp(() => ReaderLocalProgress.init(_FakeReaderLocalProgressStore()));

  testWidgets('详情头左右两枚 48 圆钮，图标走样例同源矢量', (tester) async {
    await _pumpHostedDetail(tester);

    final circles = find.byType(MobileGlassIconButton);
    expect(
      circles,
      findsNWidgets(2),
      reason: '样例 .detail-header 有返回与更多两枚 .icon-button',
    );

    final back = tester.getRect(circles.first);
    final more = tester.getRect(circles.last);
    expect(back.width, 48);
    expect(back.height, 48);
    // 样例 `.detail-header` 横向内衬 14。
    expect(back.left, 14);
    expect(more.right, 390 - 14);

    expect(
      find.descendant(of: circles, matching: find.byType(OmniIcon)),
      findsNWidgets(2),
      reason: '返回与更多用 OmniIcons，不留 Material 图标',
    );
    expect(
      find.descendant(
        of: circles.first,
        matching: find.byIcon(Icons.arrow_back_rounded),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('页头让开状态栏，返回钮不被压住', (tester) async {
    await _pumpHostedDetail(tester);

    final back = tester.getRect(find.byType(MobileGlassIconButton).first);
    expect(
      back.top,
      greaterThanOrEqualTo(_statusBarInset),
      reason: '返回钮顶缘必须在状态栏之下（样例 padding-top 为 max(18, safe-top)）',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('右上角更多是带标签的浮层入口', (tester) async {
    await _pumpHostedDetail(tester);

    // 中文文案取自 app_zh.arb 的 coreMore（更多操作）。
    expect(find.byTooltip('更多操作'), findsOneWidget);
  });

  testWidgets('更多面板收纳三个动作，编辑元数据进编辑页', (tester) async {
    await _pumpHostedDetail(tester);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderDetailActionSheet), findsOneWidget);
    expect(find.text('编辑元数据'), findsOneWidget);
    expect(find.text('重新解析'), findsOneWidget);
    expect(find.text('删除书籍'), findsOneWidget);

    await tester.tap(find.text('编辑元数据'));
    await tester.pumpAndSettle();

    expect(find.text('元数据编辑页桩'), findsOneWidget);
    expect(find.byType(ReaderDetailActionSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('书名按样例衬线 32 常规字重', (tester) async {
    await _pumpHostedDetail(tester);

    // 样例 `.book-identity h1`：font 400 32px/1.02 Instrument Serif。
    final title = tester.widget<Text>(find.text('The Art of Stillness'));
    expect(title.style?.fontSize, 32);
    expect(title.style?.fontWeight, FontWeight.w400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF 托管详情同样走 84 页头与两枚圆钮', (tester) async {
    await _pumpHostedDetail(tester, itemType: 'PDF');

    final circles = find.byType(MobileGlassIconButton);
    expect(circles, findsNWidgets(2));
    expect(
      tester.getRect(circles.first).top,
      greaterThanOrEqualTo(_statusBarInset),
    );
    expect(find.byType(ReaderDetailActionSheet), findsNothing);
    expect(find.text('返回'), findsNothing, reason: '托管态不再用通栏文字返回条');
    expect(tester.takeException(), isNull);
  });
}
