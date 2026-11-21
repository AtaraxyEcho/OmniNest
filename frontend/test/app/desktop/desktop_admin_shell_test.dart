import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_theme.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/features/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_shell.dart';

import 'desktop_test_harness.dart';

/// 管理台的分区可见性由权限码决定；测试里给一份覆盖所有分区的管理员会话。
class _AdminSession extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => AuthSessionState(
    user: UserProfile(
      id: 'u-1',
      username: 'mira',
      displayName: 'Mira Han',
      role: 'SUPER_ADMIN',
      roles: const {'SUPER_ADMIN'},
      permissions: const {
        'system:config:read',
        'system:user:read',
        'system:user:manage',
        'task:admin',
        'photo:admin',
        'media:library:manage',
      },
    ),
  );
}

/// 管理台在桌面统一壳内的形态：页头 + 分区竖轨，不再叠一层工位顶栏与侧栏。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAdmin(WidgetTester tester, {required bool hosted}) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(session: _AdminSession.new),
        child: MediaQuery(
          data: const MediaQueryData(size: kDesktopViewport),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: DesktopTheme.resolve(isDark: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: DesktopShellScope(
              hosted: hosted,
              child: const AdminDashboardPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('未托管：保留工位顶栏与侧栏', (tester) async {
    await pumpAdmin(tester, hosted: false);

    expect(find.byType(AdminSidebar), findsOneWidget);
    expect(find.textContaining('OmniNest Admin /'), findsOneWidget);
  });

  testWidgets('桌面壳托管：顶栏与侧栏让位，改画页头与分区竖轨', (tester) async {
    await pumpAdmin(tester, hosted: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(AdminSidebar), findsNothing);
    expect(find.textContaining('OmniNest Admin /'), findsNothing);
    expect(find.text('Admin Console'), findsWidgets);
    // 5 分区竖轨取代原来的 10 分区列表；默认落在 Overview 容器。
    expect(find.text('Identity & Permissions'), findsOneWidget);
    expect(find.text('Operations'), findsOneWidget);
    expect(find.text('System Config'), findsOneWidget);
  });
}
