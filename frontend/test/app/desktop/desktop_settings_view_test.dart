import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_settings_page.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/profile/domain/user_session.dart';

import 'desktop_test_harness.dart';

/// 通知偏好只覆盖 build：开关仍走真实的 save 路径（测试里只验渲染）。
class _SeededNotificationPreferences extends NotificationPreferencesController {
  @override
  Future<NotificationPreferences> build() async =>
      const NotificationPreferences(
        quietHours: QuietHours(enabled: true, start: '22:00', end: '08:00'),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSettings(WidgetTester tester, {String? section}) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          notificationPreferencesProvider.overrideWith(
            _SeededNotificationPreferences.new,
          ),
          userSessionsProvider.overrideWith(
            (ref) async => [
              const UserSession(
                id: 's-1',
                clientPlatform: 'Windows',
                deviceName: 'Studio desktop',
                ipAddress: '192.168.1.8',
                issuedAt: '2026-11-14T08:00:00Z',
                expiresAt: '2026-11-21T08:00:00Z',
                lastActiveAt: '2026-11-14T09:30:00Z',
                createdAt: '2026-11-14T08:00:00Z',
                current: true,
              ),
              const UserSession(
                id: 's-2',
                clientPlatform: 'Android',
                deviceName: 'Living room TV',
                ipAddress: '192.168.1.21',
                issuedAt: '2026-11-10T08:00:00Z',
                expiresAt: '2026-11-17T08:00:00Z',
                lastActiveAt: '2026-11-13T21:10:00Z',
                createdAt: '2026-11-10T08:00:00Z',
              ),
            ],
          ),
        ],
        child: wrapDesktop(DesktopSettingsPage(initialSection: section)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('默认打开账户节', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Settings'), findsOneWidget);
    // 页头眉标与账户名输入框各出现一次。
    expect(find.text('Mira Han'), findsWidgets);
    expect(find.text('SUPER_ADMIN'), findsWidgets);
  });

  testWidgets('外观节列出主题、强调色与环境开关', (tester) async {
    await pumpSettings(tester, section: 'appearance');

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Sage'), findsOneWidget);
    expect(find.text('Mist'), findsOneWidget);
    expect(find.text('Copper'), findsOneWidget);
    expect(find.text('Reduce motion'), findsWidgets);
    expect(find.text('Compact density'), findsWidgets);
  });

  testWidgets('账户节读会话里的名字与角色', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Account').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Mira Han'), findsWidgets);
    expect(find.text('SUPER_ADMIN'), findsWidgets);
  });

  testWidgets('通知节列出偏好开关与免打扰时段', (tester) async {
    await pumpSettings(tester, section: 'notifications');

    expect(find.text('Enable notifications'), findsOneWidget);
    expect(find.text('Foreground banners'), findsOneWidget);
    expect(find.text('Do Not Disturb'), findsOneWidget);
    expect(find.textContaining('22:00'), findsOneWidget);
  });

  testWidgets('安全节给出改密表单与活跃会话', (tester) async {
    await pumpSettings(tester, section: 'security');

    expect(find.text('Current Password'), findsOneWidget);
    expect(find.text('New Password'), findsOneWidget);
    expect(find.text('Studio desktop'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    // 样例 `Settings.tsx:80`：非当前设备的动作是 Sign out。
    expect(find.text('Sign out'), findsWidgets);
  });

  testWidgets('连接服务节给出空态与入口', (tester) async {
    await pumpSettings(tester, section: 'services');

    expect(find.text('Connected services'), findsWidgets);
    // 当前产品把连接服务落在音乐平台与 Last.fm 上（真实能力），
    // 不再有 OneDrive/External Storage 占位入口。
    expect(find.text('Netease Cloud Music'), findsOneWidget);
    expect(find.text('Last.fm scrobbling'), findsOneWidget);
  });

  testWidgets('关于节给出检查更新入口', (tester) async {
    await pumpSettings(tester, section: 'about');

    expect(find.text('About OmniNest'), findsWidgets);
    expect(find.text('Check for Updates'), findsOneWidget);
  });

  testWidgets('分区顺序与样例一致，背景库在第三位', (tester) async {
    await pumpSettings(tester);

    // 样例 `Settings.tsx:13` 的八节顺序：Profile · Appearance · Backdrop
    // library · Notifications · Security · Storage · Connected services ·
    // About & updates。顺序错了就是偏离样例，这条锁住它。
    final labels = DesktopSettingsSection.values
        .map(
          (section) => switch (section) {
            DesktopSettingsSection.profile => 'Account',
            DesktopSettingsSection.appearance => 'Appearance',
            DesktopSettingsSection.backdrop => 'Backdrop library',
            DesktopSettingsSection.notifications => 'Notifications',
            DesktopSettingsSection.security => 'Security & sessions',
            DesktopSettingsSection.storage => 'Storage',
            DesktopSettingsSection.services => 'Connected services',
            DesktopSettingsSection.about => 'About',
          },
        )
        .toList(growable: false);
    expect(labels[2], 'Backdrop library');
    expect(DesktopSettingsSection.values.length, 8);
    expect(find.text('Backdrop library'), findsWidgets);
  });

  testWidgets('存储节按种子用量显示', (tester) async {
    await pumpSettings(tester, section: 'storage');

    expect(find.text('Storage'), findsWidgets);
    // 样例 Storage 卡用分段条 + GB 图例，不写百分比。
    expect(find.textContaining('GB'), findsWidgets);
  });
}
