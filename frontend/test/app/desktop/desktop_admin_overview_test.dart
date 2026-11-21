import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_overview_desktop.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const summary = AdminConsoleSummary(
    users: AdminUserStats(
      total: 12,
      active: 9,
      disabled: 3,
      roleCounts: {'admin': 1, 'user': 11},
    ),
    roles: [
      AdminRoleSummary(
        code: 'admin',
        name: 'Admin',
        description: '',
        builtIn: true,
        enabled: true,
        permissionCount: 12,
        permissions: [],
      ),
    ],
    configs: AdminConfigStats(
      total: 20,
      hot: 8,
      nextTask: 2,
      restartRequired: 1,
    ),
    tasks: AdminTaskStats(
      total: 40,
      queued: 3,
      running: 2,
      completed: 30,
      failed: 4,
      cancelled: 1,
      dlq: 0,
    ),
    storage: AdminStorageStats(
      fileCount: 52418,
      folderCount: 1204,
      objectCount: 53000,
      usedBytes: 73443901440,
      externalAccountCount: 2,
    ),
    health: [
      AdminHealthItem(name: 'Postgres', status: 'UP', detail: '12ms'),
      AdminHealthItem(name: 'Redis', status: 'DOWN', detail: 'timeout'),
    ],
  );

  testWidgets('桌面概览给出四张指标卡与健康/角色/存储', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileStorageStatsProvider.overrideWith((ref) async => seededStorage),
        ],
        child: wrapDesktop(
          const SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: DesktopAdminOverview(summary: summary),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('USERS'), findsOneWidget);
    expect(find.text('12'), findsWidgets);
    expect(find.text('System health'), findsOneWidget);
    expect(find.textContaining('Postgres'), findsOneWidget);
    expect(find.textContaining('Redis'), findsOneWidget);
    expect(find.text('View logs'), findsOneWidget);
    expect(find.text('Admin · 1'), findsOneWidget);
    expect(find.textContaining('52,418'), findsNothing);
    expect(find.textContaining('this week'), findsWidgets);
  });
}
