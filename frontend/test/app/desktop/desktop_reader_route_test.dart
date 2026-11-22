import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/pages/desktop_book_detail_page.dart';
import 'package:omninest/app/desktop/pages/desktop_reader_page.dart';
import 'package:omninest/app/router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_theme.dart';
import 'package:omninest/features/reader/presentation/pages/reader_item_detail_page.dart';
import 'package:omninest/features/reader/presentation/pages/reader_bookshelf_page.dart';
import 'package:omninest/features/reader/domain/parsed_book.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';

import 'desktop_test_harness.dart';
import 'package:omninest/app/l10n/omni_localizations_delegates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面书籍详情深链分派到当前桌面详情而不是旧页面', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/reader/items/b-1',
      routes: [
        GoRoute(
          path: '/reader/items/:itemId',
          builder: (context, state) => buildReaderItemRoute(state),
        ),
      ],
    );
    addTearDown(router.dispose);

    final theme = DesktopTheme.resolve(
      isDark: true,
      accent: DesktopAccent.sage,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: MediaQuery(
          data: const MediaQueryData(
            size: kDesktopViewport,
            devicePixelRatio: 1,
          ),
          child: MaterialApp.router(
            routerConfig: router,
            theme: theme,
            localizationsDelegates: kOmniNestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    debugDefaultTargetPlatformOverride = null;

    expect(find.byType(DesktopBookDetailPage), findsOneWidget);
    expect(find.byType(ReaderItemDetailPage), findsNothing);
  });

  testWidgets('PDF 详情的阅读按钮不受文本章节清单影响', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final item = ReaderItem(
      id: 'pdf-1',
      title: 'A PDF in the Quiet Room',
      itemType: 'PDF',
      updatedAt: DateTime(2026, 11, 14),
    );
    late GoRouter router;
    router = GoRouter(
      initialLocation: '/reader/items/pdf-1',
      routes: [
        GoRoute(
          path: '/reader/items/:itemId',
          builder:
              (context, state) => DesktopRouterScope(
                router: router,
                child: DesktopBookDetailPage(
                  itemId: state.pathParameters['itemId']!,
                ),
              ),
        ),
        GoRoute(
          path: '/reader/pdfs/:itemId/read',
          builder: (context, state) => const Text('pdf-reader-route'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          readerItemDetailProvider.overrideWith(
            (ref, id) async => ReaderItemDetail(item: item),
          ),
          parsedBookProvider.overrideWith(
            (ref, id) async => const ParsedBook(chapters: []),
          ),
          readerItemAnnotationsProvider.overrideWith(
            (ref, id) async => const <ReaderAnnotation>[],
          ),
          readerItemBookmarksProvider.overrideWith(
            (ref, id) async => const <ReaderBookmark>[],
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
            localizationsDelegates: kOmniNestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    debugDefaultTargetPlatformOverride = null;

    expect(tester.takeException(), isNull);
    expect(find.text('Start Reading'), findsOneWidget);
    await tester.tap(find.text('Start Reading'));
    await tester.pump();
    expect(find.text('pdf-reader-route'), findsOneWidget);
  });

  testWidgets('桌面书架深链使用 Reader Library 视图而不是旧书架页', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final router = GoRouter(
      initialLocation: '/reader/bookshelf',
      routes: [
        GoRoute(
          path: '/reader/bookshelf',
          builder:
              (context, state) => const Material(
                child: DesktopReaderPage(initialLibrary: true),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
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
            localizationsDelegates: kOmniNestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 640));
    debugDefaultTargetPlatformOverride = null;

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('desktop-reader-search')),
      findsOneWidget,
    );
    expect(find.byType(ReaderBookshelfPage), findsNothing);
  });
}
