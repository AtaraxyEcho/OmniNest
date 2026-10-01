import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/core/widgets/workstation_portal_link.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 受限角色（无 activity:write）的通知页门控回归：
/// 全部主动写入口（全部已读 / 清空 / 条目删除）必须隐藏，仅保留浏览；
/// 有能力时入口完整。另断言工位顶栏未读徽章形态。
void main() {
  final unreadNotification = NotificationDto(
    id: 'n-1',
    type: 'SYSTEM_MESSAGE',
    title: '标题',
    message: '内容',
    read: false,
    createdAt: DateTime(2026, 9, 26, 12),
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

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Widget buildPage() {
    return MaterialApp(
      theme: OmniNestTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: const NotificationPage(),
    );
  }

  testWidgets('无 activity:write 时隐藏全部已读、清空与条目删除', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationControllerProvider.overrideWith(
            () => _FakeNotificationController(
              NotificationState(items: [unreadNotification], total: 1),
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

    expect(find.text('标题'), findsOneWidget);
    expect(find.text('全部已读'), findsNothing);
    expect(find.byIcon(Icons.delete_outline_outlined), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    // 设置入口与 PORTAL 返回不受能力门控限制。
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byType(WorkstationPortalLink), findsOneWidget);
  });

  testWidgets('有 activity:write 时入口完整渲染并带未读徽章', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationControllerProvider.overrideWith(
            () => _FakeNotificationController(
              NotificationState(items: [unreadNotification], total: 1),
            ),
          ),
          unreadCountProvider.overrideWith(() => _FakeUnreadCountNotifier()),
          userCapabilitiesProvider.overrideWithValue(activityCapableOnly),
          authSessionProvider.overrideWith(_TestAuthSessionNotifier.new),
        ],
        child: buildPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部已读'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_outlined), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.text('[1 未读]'), findsOneWidget);
    expect(find.text('全部通知 (1)'), findsOneWidget);
    expect(find.text('未读消息 (1)'), findsOneWidget);
  });
}

/// 固定通知状态，屏蔽真实加载与实时刷新链路。
class _FakeNotificationController extends NotificationController {
  _FakeNotificationController(this.initialState);

  final NotificationState initialState;

  @override
  NotificationState build() => initialState;

  @override
  Future<void> load({int page = 0, int size = 20}) async {}

  @override
  Future<void> refreshForRealtime({int size = 20}) async {}
}

/// 未读计数固定为 1，驱动顶栏「全部已读」与徽章的渲染条件。
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
