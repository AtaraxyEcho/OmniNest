import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/notifications/application/notification_foreground_presenter.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/presentation/widgets/notification_foreground_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

NotificationDto _notification(String title) {
  return NotificationDto(
    id: title,
    type: 'SYSTEM',
    title: title,
    read: false,
    createdAt: DateTime.utc(2026, 9, 20),
  );
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required ProviderContainer container,
  required StreamController<NotificationDto> events,
  String initialLocation = '/',
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder:
            (context, state) => NotificationForegroundToast(
              child: const Scaffold(body: Text('home')),
            ),
      ),
      GoRoute(
        path: '/notifications',
        builder:
            (context, state) => NotificationForegroundToast(
              child: const Scaffold(body: Text('notifications')),
            ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _container(StreamController<NotificationDto> events) {
  return ProviderContainer(
    overrides: [
      notificationForegroundEventsStreamProvider.overrideWith(
        (ref) => events.stream,
      ),
    ],
  );
}

void main() {
  testWidgets('通知到达弹出前台提示并可点击跳转', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final events = StreamController<NotificationDto>.broadcast();
    addTearDown(events.close);
    final container = _container(events);
    addTearDown(container.dispose);
    await _pumpHost(tester, container: container, events: events);

    events.add(_notification('新任务完成'));
    await tester.pumpAndSettle();

    expect(find.text('新任务完成'), findsOneWidget);
    expect(find.text('查看'), findsOneWidget);

    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();
    expect(find.text('notifications'), findsOneWidget);
  });

  testWidgets('开关关闭时不弹前台提示', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'notification_foreground_toast_enabled': false,
    });
    final events = StreamController<NotificationDto>.broadcast();
    addTearDown(events.close);
    final container = _container(events);
    addTearDown(container.dispose);
    // 预热开关 provider，确保读取到关闭值而非回落默认。
    await container.read(notificationForegroundToastEnabledProvider.future);
    await _pumpHost(tester, container: container, events: events);

    events.add(_notification('不应出现'));
    await tester.pumpAndSettle();

    expect(find.text('不应出现'), findsNothing);
  });

  testWidgets('通知页打开期间抑制前台提示', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final events = StreamController<NotificationDto>.broadcast();
    addTearDown(events.close);
    final container = _container(events);
    addTearDown(container.dispose);
    await _pumpHost(
      tester,
      container: container,
      events: events,
      initialLocation: '/notifications',
    );

    events.add(_notification('同屏抑制'));
    await tester.pumpAndSettle();

    expect(find.text('同屏抑制'), findsNothing);
  });

  testWidgets('展示期间新到达合并为最新一条', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final events = StreamController<NotificationDto>.broadcast();
    addTearDown(events.close);
    final container = _container(events);
    addTearDown(container.dispose);
    await _pumpHost(tester, container: container, events: events);

    events.add(_notification('第一条'));
    await tester.pump();
    events.add(_notification('第二条'));
    await tester.pumpAndSettle();

    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
  });
}
