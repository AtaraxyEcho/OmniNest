import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' as go_router;
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_page.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/profile/domain/user_session.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_session_management_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 通知中心筛选按钮形态与会话表结构的回归：
/// - 筛选为两个独立按钮（非连体分段），点击未读触发 setFilter；
/// - 未读信号条固定 6px 宽；
/// - 会话表在多条数据下渲染表头 / 当前会话徽章 / 撤销按钮，不再出现
///   Expanded 误嵌导致的 ParentDataWidget 断言。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Widget host(Widget child) {
    return MaterialApp(
      theme: OmniNestTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(body: child),
    );
  }

  testWidgets('会话表渲染表头/当前徽章/撤销且无 ParentData 断言', (tester) async {
    // 宽档全列：列式表头 + 平台码徽标 + 独立时间列（无前缀文案）。
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer.test(
      overrides: [
        userSessionsProvider.overrideWith(
          (ref) async => const [
            UserSession(
              id: 's-1',
              clientPlatform: 'web',
              deviceName: 'Windows 11 · Chrome 124',
              ipAddress: '192.168.1.108',
              issuedAt: '2026-09-28 09:00:00',
              expiresAt: '2026-10-28 09:00:00',
              lastActiveAt: '2026-09-29 17:20:00',
              createdAt: '2026-09-28 09:00:00',
              current: true,
            ),
            UserSession(
              id: 's-2',
              clientPlatform: 'android',
              deviceName: 'Android 14 · Pixel 8',
              ipAddress: '192.168.1.142',
              issuedAt: '2026-09-27 09:00:00',
              expiresAt: '2026-10-27 09:00:00',
              lastActiveAt: '2026-09-29 15:02:00',
              createdAt: '2026-09-27 09:00:00',
            ),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: host(const ProfileSessionManagementPanel()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Windows 11 · Chrome 124'), findsOneWidget);
    expect(find.text('当前会话'), findsOneWidget);
    expect(find.text('撤销会话'), findsOneWidget);
    expect(find.byType(WorkstationActionButton), findsOneWidget);
    // 平台代码徽标与独立时间列：徽标在设备列，有效期列为无前缀紧凑时间。
    expect(find.text('[WEB]'), findsOneWidget);
    expect(find.text('[ANDROID]'), findsOneWidget);
    expect(find.text('登录时间'), findsOneWidget);
    expect(find.text('有效期'), findsOneWidget);
    expect(find.text('10-28 09:00'), findsOneWidget);
    expect(find.text('10-27 09:00'), findsOneWidget);
  });

  testWidgets('筛选为独立按钮：点击未读按钮触发未读筛选', (tester) async {
    final calls = <NotificationFilter>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_TestAuthSessionNotifier.new),
          unreadCountProvider.overrideWith(() => _Unread3()),
          userCapabilitiesProvider.overrideWithValue(_fullCaps),
          notificationControllerProvider.overrideWith(
            () => _RecordingController(
              NotificationState(items: const [], total: 0),
              calls,
            ),
          ),
        ],
        child: host(const NotificationPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('notification-filter-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notification-filter-unread')),
      findsOneWidget,
    );
    expect(find.text('未读消息 (3)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notification-filter-unread')));
    await tester.pumpAndSettle();

    expect(calls, [NotificationFilter.unread]);
  });

  testWidgets('未读通知卡左侧信号条为 6px 宽', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_TestAuthSessionNotifier.new),
          unreadCountProvider.overrideWith(() => _Unread3()),
          userCapabilitiesProvider.overrideWithValue(_fullCaps),
          notificationControllerProvider.overrideWith(
            () => _StaticController(
              NotificationState(
                items: [
                  NotificationDto(
                    id: 'n-1',
                    type: 'TASK_COMPLETED',
                    title: '标题',
                    read: false,
                    createdAt: DateTime(2026, 9, 29, 9),
                  ),
                ],
                total: 1,
              ),
            ),
          ),
        ],
        child: host(const NotificationPage()),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byKey(const ValueKey('notification-unread-signal'));
    expect(bar, findsOneWidget);
    expect(tester.getSize(bar).width, 6);

    // 色阶契约：未读卡 surfaceContainer 最亮，浮于画布 surface 之上。
    // 须从卡片元素取 WorkstationScope 内的主题，页面外层主题不是工位色板。
    final scheme =
        Theme.of(
          tester.element(find.byKey(const ValueKey('notification-card-n-1'))),
        ).colorScheme;
    final card = tester.widget<Container>(
      find.byKey(const ValueKey('notification-card-n-1')),
    );
    final decoration = card.decoration as BoxDecoration;
    expect(decoration.color, scheme.surfaceContainer);
  });

  testWidgets('页面画布取工位色板（深黑），不落全局主题 surface', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_TestAuthSessionNotifier.new),
          unreadCountProvider.overrideWith(() => _Unread3()),
          userCapabilitiesProvider.overrideWithValue(_fullCaps),
          notificationControllerProvider.overrideWith(
            () => _StaticController(const NotificationState()),
          ),
        ],
        child: host(const NotificationPage()),
      ),
    );
    await tester.pumpAndSettle();

    final pageScaffold = find.descendant(
      of: find.byType(NotificationPage),
      matching: find.byType(Scaffold),
    );
    final scaffold = tester.widget<Scaffold>(pageScaffold);
    // 工位深黑画布：#09090B（WorkstationPalette.canvasDark）。
    expect(scaffold.backgroundColor, const Color(0xFF09090B));
  });

  testWidgets('动作链接跳转前先将未读通知标记已读', (tester) async {
    final readIds = <String>[];
    final router = go_router.GoRouter(
      initialLocation: '/notifications',
      routes: [
        go_router.GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationPage(),
        ),
        go_router.GoRoute(
          path: '/files',
          builder:
              (_, _) => const Scaffold(
                key: Key('files-marker'),
                body: Text('files-page'),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_TestAuthSessionNotifier.new),
          unreadCountProvider.overrideWith(() => _Unread3()),
          userCapabilitiesProvider.overrideWithValue(_fullCaps),
          notificationControllerProvider.overrideWith(
            () => _MarkReadRecordingController(
              readIds,
              NotificationState(items: [unreadItem()], total: 1),
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('查看文件'));
    await tester.pumpAndSettle();

    expect(readIds, ['n-1']);
    expect(find.text('files-page'), findsOneWidget);
  });

  testWidgets('WorkstationSwitch 点击回传取反值', (tester) async {
    var current = false;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder:
              (context, setState) => Center(
                child: WorkstationSwitch(
                  value: current,
                  onChanged: (value) => setState(() => current = value),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.byType(WorkstationSwitch));
    await tester.pumpAndSettle();

    expect(current, isTrue);
  });
}

class _TestAuthSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return const AuthSessionState.unauthenticated();
  }
}

class _Unread3 extends UnreadCountNotifier {
  @override
  int build() => 3;
}

const _fullCaps = UserCapabilities(
  canBrowseContent: true,
  canContributeContent: true,
  canManageOwnActivity: true,
  canManagePreferences: true,
  canManageAccount: true,
  canUseBackdropLibrary: true,
  canUploadBackdrop: true,
  canViewOwnTasks: true,
  canAdminTasks: true,
  canManageMediaLibrary: true,
  canManagePhotos: true,
  canAdminUsers: true,
  canReadSystemConfig: true,
  canManageSystemConfig: true,
  canAccessAdminConsole: true,
  canSharedBrowse: true,
  canSharedUpload: true,
  canReadWeather: true,
  canReportLocation: true,
  canManageTwoFactor: true,
  canReadActivity: true,
);

class _RecordingController extends NotificationController {
  _RecordingController(this.initialState, this.filterCalls);

  final NotificationState initialState;
  final List<NotificationFilter> filterCalls;

  @override
  NotificationState build() => initialState;

  @override
  Future<void> load({int page = 0, int size = 20}) async {}

  @override
  Future<void> refreshForRealtime({int size = 20}) async {}

  @override
  Future<void> setFilter(NotificationFilter filter, {int size = 20}) async {
    filterCalls.add(filter);
  }
}

NotificationDto unreadItem() {
  return NotificationDto(
    id: 'n-1',
    type: 'TASK_COMPLETED',
    title: '导入完成',
    message: null,
    read: false,
    createdAt: DateTime(2026, 9, 29, 9),
  );
}

class _MarkReadRecordingController extends NotificationController {
  _MarkReadRecordingController(this.readIds, this.initialState);

  final List<String> readIds;
  final NotificationState initialState;

  @override
  NotificationState build() => initialState;

  @override
  Future<void> load({int page = 0, int size = 20}) async {}

  @override
  Future<void> refreshForRealtime({int size = 20}) async {}

  @override
  Future<void> markRead(String id) async {
    readIds.add(id);
  }
}

class _StaticController extends NotificationController {
  _StaticController(this.initialState);

  final NotificationState initialState;

  @override
  NotificationState build() => initialState;

  @override
  Future<void> load({int page = 0, int size = 20}) async {}

  @override
  Future<void> refreshForRealtime({int size = 20}) async {}
}
