import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/router.dart';
import 'package:omninest/core/notifications/notification_tap_binding.dart';
import 'package:omninest/core/notifications/system_notifier.dart';

void main() {
  testWidgets('系统通知点击落位到通知中心', (tester) async {
    final router = GoRouter(
      initialLocation: '/portal',
      routes: <RouteBase>[
        GoRoute(
          path: '/portal',
          builder: (context, state) => const Scaffold(body: Text('portal')),
        ),
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const Scaffold(body: Text('inbox')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRouterProvider.overrideWithValue(router)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    // 绑定在 Provider 首次读取时挂接通知 tap 回调。
    ProviderScope.containerOf(
      tester.element(find.text('portal')),
      listen: false,
    ).read(systemNotificationTapBindingProvider);

    notificationTapRouteHandler?.call(notificationTapRoute);
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/notifications',
    );
    expect(find.text('inbox'), findsOneWidget);
  });

  testWidgets('provider 释放后通知 tap 回调被清空', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appRouterProvider.overrideWithValue(
          GoRouter(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(systemNotificationTapBindingProvider);
    expect(notificationTapRouteHandler, isNotNull);

    container.dispose();
    expect(notificationTapRouteHandler, isNull);
  });
}
