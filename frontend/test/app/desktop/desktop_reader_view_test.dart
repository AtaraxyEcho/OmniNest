import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/pages/desktop_reader_page.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_theme.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpReader(WidgetTester tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: wrapDesktop(const DesktopReaderPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('总览显示继续阅读卡与洞察计数', (tester) async {
    await pumpReader(tester);

    expect(find.textContaining('42 TITLES'), findsOneWidget);
    expect(find.text('The Quiet Arrival'), findsWidgets);
    expect(find.text('Ines Aoki'), findsWidgets);
    expect(find.textContaining('Kyoto'), findsWidgets);
    expect(find.text('64%'), findsOneWidget);
    // 洞察四卡：藏书 / 在读 / 已读完 / 未读。
    expect(find.text('Books'), findsWidgets);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('书库视图按书名搜索并可切列表', (tester) async {
    await pumpReader(tester);

    await tester.tap(find.text('Library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(
      find.byKey(const ValueKey<String>('desktop-reader-search')),
      findsOneWidget,
    );
    expect(find.text('The Quiet Arrival'), findsWidgets);

    await tester.tap(find.byTooltip('List view'));
    await tester.pump();
    expect(find.byType(DesktopReaderBookCover), findsWidgets);
    expect(find.text('Continue Reading'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-reader-search')),
      'quiet',
    );
    await tester.pump();
    expect(find.text('The Quiet Arrival'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-reader-search')),
      'zzz',
    );
    await tester.pump();
    expect(find.text('Nothing on the shelf yet.'), findsOneWidget);
  });

  testWidgets('筛到已读完时落到空态', (tester) async {
    await pumpReader(tester);
    // 洞察卡里也有 Finished 字样；分段控件在它下面，取最后一个。
    await tester.tap(find.text('Finished').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Nothing on the shelf yet.'), findsOneWidget);
  });

  testWidgets('在读筛选保留当前书', (tester) async {
    await pumpReader(tester);
    await tester.tap(find.text('In progress').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('The Quiet Arrival'), findsWidgets);
  });

  testWidgets('书架卡片使用共享封面结构并保留可点击语义', (tester) async {
    await pumpReader(tester);

    expect(
      find.byKey(const ValueKey<String>('desktop-reader-book-card-b-1')),
      findsWidgets,
    );
    expect(find.byType(DesktopReaderBookCover), findsWidgets);
    expect(find.bySemanticsLabel('The Quiet Arrival'), findsWidgets);
  });

  testWidgets('继续阅读按钮进入章节阅读，书籍页按钮保留详情路由', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    late GoRouter router;
    router = GoRouter(
      initialLocation: '/reader',
      routes: [
        GoRoute(
          path: '/reader',
          builder:
              (context, state) => DesktopRouterScope(
                router: router,
                child: const DesktopReaderPage(),
              ),
        ),
        GoRoute(
          path: '/reader/items/:itemId',
          builder: (context, state) => const Text('book-detail-route'),
        ),
        GoRoute(
          path: '/reader/items/:itemId/chapters/:chapterId',
          builder: (context, state) => const Text('chapter-reader-route'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          readerItemDetailProvider.overrideWith(
            (ref, id) async => ReaderItemDetail(
              item: seededBook,
              progress: ReaderProgress(
                readerItemId: seededBook.id,
                charOffset: 1200,
                progressPercent: 0.64,
                readingMode: 'page',
                chapterId: 'c-2',
                updatedAt: DateTime(2026, 11, 14),
              ),
            ),
          ),
        ],
        child: MediaQuery(
          data: const MediaQueryData(
            size: kDesktopViewport,
            devicePixelRatio: 1,
          ),
          child: MaterialApp.router(
            routerConfig: router,
            theme: DesktopTheme.resolve(
              isDark: true,
              accent: DesktopAccent.sage,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 640));
    debugDefaultTargetPlatformOverride = null;

    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-reader-continue')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 640));
    expect(find.text('chapter-reader-route'), findsOneWidget);

    router.go('/reader');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 640));
    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-reader-book-page')),
    );
    await tester.pump();
    expect(find.text('book-detail-route'), findsOneWidget);
  });
}
