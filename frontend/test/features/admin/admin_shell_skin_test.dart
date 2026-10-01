import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/theme/workstation_skin.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';

AdminConsoleSummary _fakeSummary() {
  return AdminConsoleSummary(
    users: AdminUserStats(
      total: 12,
      active: 10,
      disabled: 2,
      roleCounts: const {},
    ),
    roles: const [],
    configs: AdminConfigStats(
      total: 0,
      hot: 0,
      nextTask: 0,
      restartRequired: 0,
    ),
    tasks: AdminTaskStats(
      total: 0,
      queued: 0,
      running: 0,
      completed: 0,
      failed: 0,
      cancelled: 0,
      dlq: 0,
    ),
    storage: AdminStorageStats(
      fileCount: 4280,
      folderCount: 0,
      objectCount: 0,
      usedBytes: 842500000000,
      externalAccountCount: 0,
    ),
    health: const [],
  );
}

class _FakeAdminConsoleController extends AdminConsoleController {
  @override
  Future<AdminConsoleSummary> build() => Future.value(_fakeSummary());
}

/// 管理端外壳按权限挑选分区，需要管理权限才能看到全部分组。
class _AdminSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(
      user: UserProfile(
        id: 'admin-1',
        username: 'admin-it',
        role: 'ADMIN',
        permissions: const {
          'system:config:read',
          'system:user:read',
          'task:admin',
        },
      ),
    );
  }
}

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminConsoleControllerProvider.overrideWith(
          _FakeAdminConsoleController.new,
        ),
        authSessionProvider.overrideWith(_AdminSessionNotifier.new),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const AdminDashboardPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('宽屏外壳渲染工位皮肤要素（PORTAL/在线徽章/等宽组标/存储微卡）', (tester) async {
    await _pumpShell(tester);

    expect(find.text('PORTAL'), findsOneWidget);
    // 在线徽章取实时相位文案，未连接时为 OFFLINE。
    expect(find.textContaining(RegExp('^(ONLINE|OFFLINE)\$')), findsOneWidget);
    expect(find.textContaining('OmniNest Admin /'), findsOneWidget);
    // 分组标题携带等宽英文代码。
    expect(find.textContaining('(OVERVIEW)'), findsOneWidget);
    expect(find.textContaining('(OPERATIONS)'), findsOneWidget);
    // 底部存储微卡渲染 summary 数值。
    final l10n = AppLocalizations.of(tester.element(find.text('PORTAL')));
    expect(find.text(l10n.adminStorageOverview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('外壳整体运行在工位 ColorScheme 上', (tester) async {
    await _pumpShell(tester);
    final ctx = tester.element(find.text('PORTAL'));
    expect(Theme.of(ctx).colorScheme.surface, WorkstationPalette.canvasDark);
    expect(
      Theme.of(ctx).colorScheme.outlineVariant,
      WorkstationPalette.lineDark,
    );
  });
}
