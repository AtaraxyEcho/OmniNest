import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/notifications/application/notification_type_controller.dart';
import 'package:omninest/features/notifications/data/notification_email_admin_api.dart';
import 'package:omninest/features/notifications/data/notification_type_api.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/notifications/domain/notification_type.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_settings_page.dart';
import 'package:toastification/toastification.dart';

class _AdminSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => AuthSessionState(
    user: UserProfile(
      id: 'user-1',
      username: 'admin',
      role: 'ADMIN',
      permissions: <String>{'system:config:read', 'system:config:manage'},
    ),
  );
}

class _MemberSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => AuthSessionState(
    user: UserProfile(
      id: 'user-2',
      username: 'member',
      role: 'MEMBER',
      permissions: <String>{'activity:read'},
    ),
  );
}

class _FakePreferencesNotifier extends NotificationPreferencesController {
  _FakePreferencesNotifier(this._value);

  final NotificationPreferences _value;

  @override
  Future<NotificationPreferences> build() async => _value;

  @override
  Future<void> save(NotificationPreferences preferences) async {
    state = AsyncData(preferences);
  }
}

class _FakeTypeApi implements NotificationTypeApi {
  final List<({String id, bool enabled})> updates = [];

  @override
  Future<List<NotificationTypeConfig>> list() async => const [];

  @override
  Future<List<NotificationTypeConfig>> listAll() async => seedTypes;

  @override
  Future<NotificationTypeConfig> updateType(
    String id, {
    required bool enabled,
  }) async {
    updates.add((id: id, enabled: enabled));
    final current = seedTypes.firstWhere((type) => type.id == id);
    return NotificationTypeConfig(
      id: current.id,
      typeCode: current.typeCode,
      label: current.label,
      enabled: enabled,
    );
  }
}

class _FakeEmailApi implements NotificationEmailAdminApi {
  final List<String?> recipients = [];

  @override
  Future<void> sendTest({String? to}) async {
    recipients.add(to);
  }
}

const seedTypes = <NotificationTypeConfig>[
  NotificationTypeConfig(
    id: 'type-1',
    typeCode: 'TASK_COMPLETED',
    label: '任务完成',
    enabled: true,
  ),
];

void main() {
  setUp(() {
    toastification.managers.clear();
  });

  Future<({_FakeTypeApi typeApi, _FakeEmailApi emailApi})> pumpPage(
    WidgetTester tester, {
    required bool admin,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final typeApi = _FakeTypeApi();
    final emailApi = _FakeEmailApi();
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
          authSessionProvider.overrideWith(
            admin ? _AdminSessionNotifier.new : _MemberSessionNotifier.new,
          ),
          notificationPreferencesProvider.overrideWith(
            () => _FakePreferencesNotifier(const NotificationPreferences()),
          ),
          notificationTypesProvider.overrideWith(
            (ref) => Future.value(const <NotificationTypeConfig>[]),
          ),
          allNotificationTypesProvider.overrideWith(
            (ref) => Future.value(seedTypes),
          ),
          notificationTypeApiProvider.overrideWithValue(typeApi),
          notificationEmailAdminApiProvider.overrideWithValue(emailApi),
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
    return (typeApi: typeApi, emailApi: emailApi);
  }

  testWidgets('管理员发送测试邮件（收件人留空）', (tester) async {
    final fakes = await pumpPage(tester, admin: true);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NotificationSettingsPage)),
    );

    await tester.tap(
      find.widgetWithText(OutlinedButton, l10n.notificationEmailTestAction),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.notificationEmailTestAction),
    );
    await tester.pumpAndSettle();

    expect(fakes.emailApi.recipients, ['']);
    // 让成功提示的自动关闭定时器走完，避免用例结束时仍有挂起 Timer。
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('管理员切换通知类型前必须确认', (tester) async {
    final fakes = await pumpPage(tester, admin: true);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NotificationSettingsPage)),
    );

    final row =
        find.ancestor(of: find.text('任务完成'), matching: find.byType(Row)).first;
    await tester.tap(
      find.descendant(of: row, matching: find.byType(WorkstationSwitch)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorkstationDialogFrame), findsOneWidget);
    expect(fakes.typeApi.updates, isEmpty);

    await tester.tap(
      find.widgetWithText(FilledButton, l10n.notificationTypeAdminConfirm),
    );
    await tester.pumpAndSettle();

    expect(fakes.typeApi.updates, [(id: 'type-1', enabled: false)]);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('普通成员看不到管理面板', (tester) async {
    await pumpPage(tester, admin: false);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NotificationSettingsPage)),
    );

    expect(find.text(l10n.notificationEmailTestAction), findsNothing);
    expect(find.text(l10n.notificationTypeAdminTitle), findsNothing);
  });
}
