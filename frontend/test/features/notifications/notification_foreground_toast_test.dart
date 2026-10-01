import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/router.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/core/window/desktop_close_action.dart';
import 'package:omninest/features/notifications/application/notification_foreground_presenter.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/presentation/widgets/notification_foreground_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

NotificationDto _notification(String title) {
  return NotificationDto(
    id: title,
    type: 'SYSTEM',
    title: title,
    read: false,
    createdAt: DateTime.utc(2026, 9, 20),
  );
}

GoRouter _buildRouter({
  String initialLocation = '/',
  Widget Function(BuildContext, GoRouterState)? homeBuilder,
}) {
  return GoRouter(
    navigatorKey: desktopCloseNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder:
            homeBuilder ??
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
}

/// 组装宿主：路由先行创建，容器把应用级路由 provider 覆写为测试路由，
/// 避免 toast 回退读取真实应用路由；反馈门面依赖的 Wrapper 包在最外层。
Future<ProviderContainer> _pumpHost(
  WidgetTester tester, {
  required StreamController<NotificationDto> events,
  String initialLocation = '/',
  Widget Function(BuildContext, GoRouterState)? homeBuilder,
}) async {
  final router = _buildRouter(
    initialLocation: initialLocation,
    homeBuilder: homeBuilder,
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: [
      notificationForegroundEventsStreamProvider.overrideWith(
        (ref) => events.stream,
      ),
      appRouterProvider.overrideWithValue(router),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    ToastificationWrapper(
      config: omniFeedbackToastConfig,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 冲刷自动关闭计时器与移除动画，避免测试结束残留 pending timer。
Future<void> _flush(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

/// 事件经流与 AnimatedList 逐帧挂载：两次空帧加一段时长推进后可见。
Future<void> _presentEvent(
  WidgetTester tester,
  StreamController<NotificationDto> events,
  String title,
) async {
  events.add(_notification(title));
  await tester.pump();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  // toastification 为全局单例，manager 持有已销毁树的 overlayEntry 时会
  // 跳过 holder 重建，导致后续用例条目永不渲染；每个用例前清空。
  setUp(() {
    toastification.managers.clear();
  });

  testWidgets('通知到达弹出前台提示并可点击跳转', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final events = StreamController<NotificationDto>.broadcast();
    addTearDown(events.close);
    await _pumpHost(tester, events: events);

    await _presentEvent(tester, events, '新任务完成');

    expect(find.text('新任务完成'), findsOneWidget);
    expect(find.text('查看'), findsOneWidget);
    // 呈现层不依赖 ScaffoldMessenger：任何 SnackBar 实例都不应存在。
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();
    expect(find.text('notifications'), findsOneWidget);
    expect(find.text('新任务完成'), findsNothing);
  });

  testWidgets('开关关闭时不弹前台提示', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'notification_foreground_toast_enabled': false,
    });
    final events = StreamController<NotificationDto>.broadcast();
    addTearDown(events.close);
    final container = await _pumpHost(tester, events: events);
    // 预热开关 provider，确保读取到关闭值而非回落默认。
    await container.read(notificationForegroundToastEnabledProvider.future);

    await _presentEvent(tester, events, '不应出现');

    expect(find.text('不应出现'), findsNothing);
  });

  testWidgets('通知页打开期间抑制前台提示', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final events = StreamController<NotificationDto>.broadcast();
    addTearDown(events.close);
    await _pumpHost(tester, events: events, initialLocation: '/notifications');

    await _presentEvent(tester, events, '同屏抑制');

    expect(find.text('同屏抑制'), findsNothing);
  });

  testWidgets('同文案通知合并为一条，不同文案按门面堆叠共存', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final events = StreamController<NotificationDto>.broadcast();
    addTearDown(events.close);
    await _pumpHost(tester, events: events);

    await _presentEvent(tester, events, '音乐扫描完成');
    await _presentEvent(tester, events, '音乐扫描完成');
    expect(find.text('音乐扫描完成'), findsOneWidget);

    await _presentEvent(tester, events, '照片导入完成');
    expect(find.text('音乐扫描完成'), findsOneWidget);
    expect(find.text('照片导入完成'), findsOneWidget);
    await _flush(tester);
  });

  testWidgets('多根 Scaffold 并存时路由切换不触发 SnackBar Hero 冲突', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final events = StreamController<NotificationDto>.broadcast();
    addTearDown(events.close);
    // 模拟桌面端分支壳层：IndexedStack 内多个根 Scaffold 同时挂载，
    // 再向根导航推入另一个根 Scaffold 页面。SnackBar 呈现路径会在两个
    // 挂载点重复挂出同内容 Hero，路由切换的 Hero 遍历将抛出 multiple
    // heroes 断言；门面 Overlay 不参与 Hero。
    await _pumpHost(
      tester,
      events: events,
      homeBuilder:
          (context, state) => NotificationForegroundToast(
            child: IndexedStack(
              children: <Widget>[
                Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('branch-a'),
                        Builder(
                          builder:
                              (context) => TextButton(
                                onPressed: () => context.push('/notifications'),
                                child: const Text('go-push'),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Scaffold(body: Center(child: Text('branch-b'))),
              ],
            ),
          ),
    );

    await _presentEvent(tester, events, '音乐扫描完成');
    expect(find.text('音乐扫描完成'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    // 路由切换触发 Hero 遍历：门面提示不应产生任何 Hero 冲突异常。
    await tester.tap(find.text('go-push'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('notifications'), findsOneWidget);
    expect(find.text('音乐扫描完成'), findsOneWidget);
    await _flush(tester);
  });
}
