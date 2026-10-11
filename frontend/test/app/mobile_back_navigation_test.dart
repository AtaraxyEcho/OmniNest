// 系统返回（Android 边缘手势、Web 后退键）依赖的一条硬规则：
// 进二级页必须留下可弹的栈。
//
// `go` 把整条导航栈换成目标位置，栈底就成了刚进入的那一页；此后系统返回
// 没有任何可弹层，popRoute 返回 false，引擎按「无路由可退」处理——真机表现
// 就是直接退出应用。`push` 只加一层，返回才落回来源空间。
//
// 用与真实路由同拓扑的壳层（四空间 StatefulShellRoute.indexedStack +
// 根级模块路由）量三种走法，避免只凭断言写作。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 与 router.dart 同形的最小拓扑：分支页 /portal、/library，
/// 分支内二级页 /reader/items/:itemId，根级模块页 /music 与其下的阅读页。
Future<GoRouter> _pumpShellTopology(
  WidgetTester tester, {
  required String initialLocation,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(body: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/portal',
                builder:
                    (context, state) => const Scaffold(body: Text('portal')),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder:
                    (context, state) => const Scaffold(body: Text('library')),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reader',
                builder:
                    (context, state) => const Scaffold(body: Text('reader')),
              ),
              GoRoute(
                path: '/reader/items/:itemId',
                builder:
                    (context, state) => const Scaffold(body: Text('detail')),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/files',
                builder:
                    (context, state) => const Scaffold(body: Text('files')),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/music',
        builder: (context, state) => const Scaffold(body: Text('music')),
      ),
      GoRoute(
        path: '/reader/items/:itemId/chapters/:chapterId',
        builder: (context, state) => const Scaffold(body: Text('reading')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
  );
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  testWidgets('push 进模块页：系统返回落回来源空间', (tester) async {
    final router = await _pumpShellTopology(
      tester,
      initialLocation: '/library',
    );

    router.push('/music');
    await tester.pumpAndSettle();
    expect(find.text('music'), findsOneWidget);
    expect(router.canPop(), isTrue, reason: 'push 必须留下可弹层，否则边缘返回无路可走');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(_location(router), '/library');
    expect(find.text('library'), findsOneWidget);
    expect(find.text('music'), findsNothing);
  });

  testWidgets('go 进模块页会换掉整条栈：返回时已无可弹层', (tester) async {
    final router = await _pumpShellTopology(tester, initialLocation: '/portal');

    router.go('/music');
    await tester.pumpAndSettle();
    // 这条用例锁的是「为什么入口不能写 go」：栈底即当前页，canPop 为假，
    // popRoute 返回 false 后引擎按无路由可退处理（真机直接退出应用）。
    expect(router.canPop(), isFalse);
    expect(_location(router), '/music');
  });

  testWidgets('首页 push 书籍详情再进阅读页：可逐层退回首页', (tester) async {
    final router = await _pumpShellTopology(tester, initialLocation: '/portal');

    router.push('/reader/items/b1');
    await tester.pumpAndSettle();
    router.push('/reader/items/b1/chapters/c1');
    await tester.pumpAndSettle();
    expect(find.text('reading'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_location(router), '/reader/items/b1');
    expect(router.canPop(), isTrue, reason: '退出阅读页后仍要能继续退回首页，不能停在栈底');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_location(router), '/portal');
    expect(router.canPop(), isFalse);
  });

  testWidgets('空间之间用 go 切换是预期语义：不制造幽灵返回栈', (tester) async {
    final router = await _pumpShellTopology(tester, initialLocation: '/portal');

    router.go('/files');
    await tester.pumpAndSettle();

    expect(find.text('files'), findsOneWidget);
    expect(find.text('portal'), findsNothing);
    // 四空间是同级目的地，切换后返回栈保持干净；退出应用由首页的
    // 双击返回确认负责，不靠把每个空间叠成二级页。
    expect(router.canPop(), isFalse);
  });
}
