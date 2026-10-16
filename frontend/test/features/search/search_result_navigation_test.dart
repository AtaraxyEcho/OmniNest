// 搜索结果跳转的栈语义守卫。
//
// `/photos/:id`、`/video/:id`、`/music`、`/reader/items/:id` 都是壳层之外的
// 根级路由：用 `go` 会换掉整条导航栈，之后 Android 侧滑没有可弹层，
// `popRoute` 返回 false，引擎按「无路由可退」处理——真机表现就是退出到桌面。
// 分支路由 `/files` 反过来必须 `go`（四空间是同级目的地，不留幽灵返回栈）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/search/domain/search_result.dart';
import 'package:omninest/features/search/presentation/widgets/search_result_tile.dart';

Future<GoRouter> _pumpSearch(
  WidgetTester tester, {
  required String type,
}) async {
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(
        path: '/search',
        builder:
            (context, state) => Scaffold(
              body: SearchResultTile(
                result: SearchResult(
                  id: 'x-1',
                  title: '样本',
                  subtitle: '类型 $type',
                  type: type,
                ),
              ),
            ),
      ),
      GoRoute(
        path: '/photos/:id',
        builder: (context, state) => const Scaffold(body: Text('land-photo')),
      ),
      GoRoute(
        path: '/video/:videoId',
        builder: (context, state) => const Scaffold(body: Text('land-video')),
      ),
      GoRoute(
        path: '/reader/items/:itemId',
        builder: (context, state) => const Scaffold(body: Text('land-book')),
      ),
      GoRoute(path: '/music', builder: (context, state) => const Scaffold(body: Text('land-music'))),
      GoRoute(path: '/files', builder: (context, state) => const Scaffold(body: Text('land-files'))),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  for (final (type, marker) in <(String, String)>[
    ('photo', 'land-photo'),
    ('video', 'land-video'),
    ('book', 'land-book'),
    ('music', 'land-music'),
  ]) {
    testWidgets('$type 结果：push 留下可弹层，侧滑回到搜索页', (tester) async {
      final router = await _pumpSearch(tester, type: type);

      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      expect(find.text(marker), findsOneWidget);
      expect(
        router.canPop(),
        isTrue,
        reason: 'go 会换掉整条栈：侧滑没得弹就直接退出应用',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(marker), findsNothing);
      expect(find.byType(ListTile), findsOneWidget, reason: '返回应落回搜索页');
    });
  }

  testWidgets('file 结果仍用 go 切分支：同级目的地不留幽灵栈', (tester) async {
    final router = await _pumpSearch(tester, type: 'file');

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(find.text('land-files'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });
}
