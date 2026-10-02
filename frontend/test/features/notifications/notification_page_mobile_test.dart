import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/workstation_portal_link.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_page.dart';

/// 通知中心移动形态回归：MobileShellScope 托管态渲染移动面板
/// （玻璃横幅语义下的两档分段 + 按天分组 + 全部已读 + 权限门控），
/// 桌面工位顶栏元素不得出现。
void main() {
  // 以日历日正午构造，规避测试运行时刻跨午夜导致分组漂移。
  final today = DateTime.now();
  final todayNoon = DateTime(today.year, today.month, today.day, 12);
  final todayItem = NotificationDto(
    id: 'n-today',
    type: 'SYSTEM_MESSAGE',
    title: '今天的通知',
    message: '内容',
    read: false,
    createdAt: todayNoon,
  );
  final yesterdayItem = NotificationDto(
    id: 'n-yesterday',
    type: 'SYSTEM_MESSAGE',
    title: '昨天的通知',
    message: null,
    read: true,
    createdAt: todayNoon.subtract(const Duration(days: 1)),
  );
  final earlierItem = NotificationDto(
    id: 'n-earlier',
    type: 'SYSTEM_MESSAGE',
    title: '更早的通知',
    message: null,
    read: false,
    createdAt: todayNoon.subtract(const Duration(days: 10)),
  );

  const activityCapableOnly = UserCapabilities(
    canBrowseContent: false,
    canContributeContent: false,
    canManageOwnActivity: true,
    canManagePreferences: false,
    canManageAccount: false,
    canUseBackdropLibrary: false,
    canUploadBackdrop: false,
    canViewOwnTasks: false,
    canAdminTasks: false,
    canManageMediaLibrary: false,
    canManagePhotos: false,
    canAdminUsers: false,
    canReadSystemConfig: false,
    canManageSystemConfig: false,
    canAccessAdminConsole: false,
    canSharedBrowse: false,
    canSharedUpload: false,
    canReadWeather: false,
    canReportLocation: false,
    canManageTwoFactor: false,
    canReadActivity: false,
  );

  const noCapabilities = UserCapabilities(
    canBrowseContent: false,
    canContributeContent: false,
    canManageOwnActivity: false,
    canManagePreferences: false,
    canManageAccount: false,
    canUseBackdropLibrary: false,
    canUploadBackdrop: false,
    canViewOwnTasks: false,
    canAdminTasks: false,
    canManageMediaLibrary: false,
    canManagePhotos: false,
    canAdminUsers: false,
    canReadSystemConfig: false,
    canManageSystemConfig: false,
    canAccessAdminConsole: false,
    canSharedBrowse: false,
    canSharedUpload: false,
    canReadWeather: false,
    canReportLocation: false,
    canManageTwoFactor: false,
    canReadActivity: false,
  );

  Widget buildPage() {
    return MaterialApp(
      theme: OmniNestTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: MobileShellScope(hosted: true, child: const NotificationPage()),
      ),
    );
  }

  testWidgets('托管态渲染移动形态：分段/分组/未读点/全部已读', (tester) async {
    final fake = _RecordingNotificationController(
      NotificationState(
        items: [todayItem, yesterdayItem, earlierItem],
        total: 3,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationControllerProvider.overrideWith(() => fake),
          unreadCountProvider.overrideWith(() => _FakeUnreadCountNotifier()),
          userCapabilitiesProvider.overrideWithValue(activityCapableOnly),
          authSessionProvider.overrideWith(_TestAuthSessionNotifier.new),
        ],
        child: buildPage(),
      ),
    );
    await tester.pumpAndSettle();

    // 桌面工位顶栏不得出现。
    expect(find.byType(WorkstationPortalLink), findsNothing);
    // 两档分段（zh：全部 / 未读，纯标签不带计数）。
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('未读'), findsOneWidget);
    // 分组眉标（样例两档：今天/更早，昨天并入更早）。
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('更早'), findsOneWidget);
    // 有写权限且存在未读时提供全部已读。
    expect(find.text('全部已读'), findsOneWidget);
    // 条目标题齐备。
    expect(find.text('今天的通知'), findsOneWidget);
    expect(find.text('昨天的通知'), findsOneWidget);
    expect(find.text('更早的通知'), findsOneWidget);
  });

  testWidgets('无 activity:write 时隐藏全部已读与清空入口', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationControllerProvider.overrideWith(
            () => _RecordingNotificationController(
              NotificationState(
                items: [todayItem, yesterdayItem, earlierItem],
                total: 3,
              ),
            ),
          ),
          unreadCountProvider.overrideWith(() => _FakeUnreadCountNotifier()),
          userCapabilitiesProvider.overrideWithValue(noCapabilities),
          authSessionProvider.overrideWith(_TestAuthSessionNotifier.new),
        ],
        child: buildPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部已读'), findsNothing);
    expect(find.byIcon(Icons.delete_outline_outlined), findsNothing);
    expect(find.text('今天的通知'), findsOneWidget);
  });

  testWidgets('分段切换调用 setFilter', (tester) async {
    final fake = _RecordingNotificationController(
      NotificationState(
        items: [todayItem, yesterdayItem, earlierItem],
        total: 3,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationControllerProvider.overrideWith(() => fake),
          unreadCountProvider.overrideWith(() => _FakeUnreadCountNotifier()),
          userCapabilitiesProvider.overrideWithValue(activityCapableOnly),
          authSessionProvider.overrideWith(_TestAuthSessionNotifier.new),
        ],
        child: buildPage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('未读'));
    await tester.pumpAndSettle();

    expect(fake.filters, [NotificationFilter.unread]);
  });
}

/// 固定状态并记录筛选调用，屏蔽真实加载与实时刷新链路。
class _RecordingNotificationController extends NotificationController {
  _RecordingNotificationController(this.initialState);

  final NotificationState initialState;
  final filters = <NotificationFilter>[];

  @override
  NotificationState build() => initialState;

  @override
  Future<void> load({int page = 0, int size = 20}) async {}

  @override
  Future<void> refreshForRealtime({int size = 20}) async {}

  @override
  Future<void> setFilter(NotificationFilter filter, {int size = 20}) async {
    filters.add(filter);
  }
}

class _FakeUnreadCountNotifier extends UnreadCountNotifier {
  @override
  int build() => 1;
}

class _TestAuthSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return const AuthSessionState.unauthenticated();
  }
}
