import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/module_entry_refresh_listener.dart';

void main() {
  testWidgets('回到模块根路径时节流触发进入刷新', (tester) async {
    var refreshes = 0;
    final router = GoRouter(
      initialLocation: '/portal',
      routes: [
        ShellRoute(
          builder:
              (context, state, child) => ModuleEntryRefreshListener(
                modulePath: '/music',
                onRefresh: () => refreshes += 1,
                child: Scaffold(body: Center(child: child)),
              ),
          routes: [
            GoRoute(
              path: '/portal',
              builder: (context, state) => const Text('portal'),
            ),
            GoRoute(
              path: '/music',
              builder: (context, state) => const Text('music'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(refreshes, 0);

    router.go('/music');
    await tester.pumpAndSettle();
    expect(refreshes, 1);

    // 节流窗口内的往返不重复刷新。
    router.go('/portal');
    await tester.pumpAndSettle();
    router.go('/music');
    await tester.pumpAndSettle();
    expect(refreshes, 1);

    // 离开模块根路径不触发。
    router.go('/portal');
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });
}
