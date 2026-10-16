import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:toastification/toastification.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/notifications/application/notification_type_controller.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/notifications/domain/notification_type.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_settings_page.dart';

/// 偏好控制器假体：记录保存入参，并可由测试从外部推送新值。
class _FakePreferencesNotifier extends NotificationPreferencesController {
  _FakePreferencesNotifier(this._value);

  NotificationPreferences _value;

  final List<NotificationPreferences> saved = <NotificationPreferences>[];
  Object? failure;

  @override
  Future<NotificationPreferences> build() async => _value;

  @override
  Future<void> save(NotificationPreferences preferences) async {
    saved.add(preferences);
    if (failure != null) {
      throw failure!;
    }
    state = AsyncData(preferences);
  }

  /// 模拟远端同步回写。
  void pushFromRemote(NotificationPreferences next) {
    _value = next;
    state = AsyncData(next);
  }
}

void main() {
  const seedTypes = <NotificationTypeConfig>[
    NotificationTypeConfig(
      typeCode: 'TASK_COMPLETED',
      label: '任务完成',
      sortOrder: 1,
    ),
  ];

  setUp(() {
    // toastification 是全局单例，残留 overlay 会让后续用例的条目不渲染。
    toastification.managers.clear();
  });

  Future<_FakePreferencesNotifier> pumpPage(
    WidgetTester tester,
    NotificationPreferences seed,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = _FakePreferencesNotifier(seed);
    // 顶栏的返回工位入口需要真实路由，MaterialApp(home:) 会抛 No GoRouter。
    final router = GoRouter(
      initialLocation: '/profile/notifications',
      routes: [
        GoRoute(
          path: '/profile/notifications',
          builder: (context, state) => const NotificationSettingsPage(),
        ),
        GoRoute(
          path: '/portal',
          builder: (context, state) => const SizedBox(key: Key('portal')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationPreferencesProvider.overrideWith(() => fake),
          notificationTypesProvider.overrideWith(
            (ref) => Future.value(seedTypes),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  /// 首行是总开关。
  bool masterValue(WidgetTester tester) =>
      tester
          .widget<WorkstationSwitch>(find.byType(WorkstationSwitch).first)
          .value;

  testWidgets('远端推送会被采纳：页面不再冻结首帧偏好', (tester) async {
    final fake = await pumpPage(
      tester,
      const NotificationPreferences(enabled: false),
    );
    expect(masterValue(tester), isFalse);

    // 旧实现在 build 里 `_prefs ??= prefs`：首帧之后 provider 的更新一概看不到。
    fake.pushFromRemote(const NotificationPreferences(enabled: true));
    await tester.pumpAndSettle();

    expect(masterValue(tester), isTrue);
  });

  testWidgets('总开关把新偏好交给控制器', (tester) async {
    final fake = await pumpPage(
      tester,
      const NotificationPreferences(enabled: false),
    );
    await tester.tap(find.byType(WorkstationSwitch).first);
    await tester.pumpAndSettle();

    expect(fake.saved, hasLength(1));
    expect(fake.saved.single.enabled, isTrue);
    expect(masterValue(tester), isTrue, reason: '保存成功后的乐观值要留在界面上');
  });

  testWidgets('保存失败给出反馈且不留下未处理异常', (tester) async {
    final fake = await pumpPage(
      tester,
      const NotificationPreferences(enabled: true),
    );
    fake.failure = Exception('网络不可用');

    await tester.tap(find.byType(WorkstationSwitch).first);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('保存通知偏好失败，请重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(masterValue(tester), isTrue, reason: '失败回滚后开关不能被拧走');

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
