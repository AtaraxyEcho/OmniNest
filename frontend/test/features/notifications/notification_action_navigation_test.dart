// 通知动作的跳转方式契约。
//
// 目标是壳层分支路由（四空间之一）时必须 go：push 会让 go_router 再压入第二个
// 壳层页面，Navigator 在 `_debugCheckDuplicatedPageKeys` 断言重复 page key，
// 断言抛出后 chrome、目标分支与来源页三者都不在树上。目标是根级路由时必须 push：
// go 会换掉整条栈，之后系统返回直接结束 Activity，落不回通知中心。
// 这里用与真实路由同形的最小拓扑（StatefulShellRoute.indexedStack + 根级路由）量两种走法。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_action.dart';

void main() {
  testWidgets('分支目标走 go：不触发重复 page key，且落到目标分支', (tester) async {
    final router = await _pump(tester, actionRoute: '/files');

    await tester.tap(find.byKey(const Key('action-link')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'push 分支路由会抛重复 page key 断言');
    expect(find.byKey(const Key('branch-files')), findsOneWidget);
    expect(find.byKey(const Key('shell-chrome')), findsOneWidget);
    expect(
      GoRouter.of(
        tester.element(find.byKey(const Key('shell-chrome'))),
      ).routerDelegate.currentConfiguration.last.matchedLocation,
      '/files',
    );
    router.dispose();
  });

  testWidgets('根级目标走 push：来路留在栈里', (tester) async {
    final router = await _pump(tester, actionRoute: '/video');

    await tester.tap(find.byKey(const Key('action-link')));
    await tester.pumpAndSettle();

    expect(find.text('video'), findsOneWidget);
    expect(router.canPop(), isTrue, reason: 'go 会换掉整条栈，返回时落不到通知中心');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-notifications')), findsOneWidget);
    router.dispose();
  });
}

/// 起一个 `/portal → push /notifications` 的栈，通知页里放一个执行动作的链接。
Future<GoRouter> _pump(
  WidgetTester tester, {
  required String actionRoute,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/portal',
    routes: [
      StatefulShellRoute.indexedStack(
        builder:
            (context, state, shell) => Scaffold(
              body: Column(
                children: [
                  const Expanded(
                    key: Key('shell-chrome'),
                    child: Center(child: Text('chrome')),
                  ),
                  Expanded(child: shell),
                ],
              ),
            ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/portal',
                builder:
                    (context, state) =>
                        const Scaffold(body: Center(child: Text('portal'))),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/files',
                builder:
                    (context, state) => const Scaffold(
                      body: Center(
                        key: Key('branch-files'),
                        child: Text('files'),
                      ),
                    ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/notifications',
        builder:
            (context, state) => Scaffold(
              key: const Key('page-notifications'),
              body: Center(
                child: TextButton(
                  key: const Key('action-link'),
                  onPressed:
                      () => navigateNotificationAction(context, actionRoute),
                  child: const Text('action'),
                ),
              ),
            ),
      ),
      GoRoute(
        path: '/video',
        builder:
            (context, state) =>
                const Scaffold(body: Center(child: Text('video'))),
      ),
    ],
  );

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  router.push('/notifications');
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('action-link')), findsOneWidget);
  return router;
}
