import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/core/widgets/workstation_pagination_bar.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';
import 'package:omninest/features/admin/presentation/pages/admin_users_page.dart';

import 'desktop_test_harness.dart';

/// 只给状态、不打网络：桌面用户卡读的是页面传入的 state，
/// 动作层仍从 provider 取控制器，因此也必须替身。
class _SeededUsers extends AdminUserController {
  @override
  Future<AdminUserState> build() async => _state;
}

class _SeededConsole extends AdminConsoleController {
  @override
  Future<AdminConsoleSummary> build() async => _summary;
}

const AdminConsoleSummary _summary = AdminConsoleSummary(
  users: AdminUserStats(
    total: 12,
    active: 9,
    disabled: 3,
    roleCounts: {'SUPER_ADMIN': 1, 'MEMBER': 11},
  ),
  roles: [],
  configs: AdminConfigStats(total: 0, hot: 0, nextTask: 0, restartRequired: 0),
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
    fileCount: 0,
    folderCount: 0,
    objectCount: 0,
    usedBytes: 0,
    externalAccountCount: 0,
  ),
  health: [],
);

const AdminUser _superAdmin = AdminUser(
  id: 'u-1',
  username: 'mira',
  displayName: 'Mira Han',
  status: AdminUserStatus.active,
  role: AdminRoles.superAdmin,
  roles: {AdminRoles.superAdmin},
  permissions: {},
  quotaBytes: 0,
  usedBytes: 0,
  twoFactorEnabled: true,
  createdAt: '2026-05-02T10:00:00Z',
);

const AdminUser _member = AdminUser(
  id: 'u-2',
  username: 'jun',
  displayName: 'Jun Park',
  status: AdminUserStatus.disabled,
  role: AdminRoles.member,
  roles: {AdminRoles.member},
  permissions: {},
  quotaBytes: 53687091200,
  usedBytes: 12884901888,
  createdAt: '2026-06-18T10:00:00Z',
);

const AdminUserState _state = AdminUserState(
  users: [_superAdmin, _member],
  totalElements: 12,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUsers(WidgetTester tester, {required bool hosted}) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          adminUserControllerProvider.overrideWith(_SeededUsers.new),
          // 移动分支的指标卡读控制台 summary；桌面分支不再依赖它。
          adminConsoleControllerProvider.overrideWith(_SeededConsole.new),
        ],
        child: wrapDesktop(
          DesktopShellScope(
            hosted: hosted,
            child: const SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: AdminUsersPage(state: _state),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('托管态：用户卡带头部计数、角色筛选与桌面行', (tester) async {
    await pumpUsers(tester, hosted: true);

    expect(tester.takeException(), isNull);
    expect(find.text('Mira Han'), findsOneWidget);
    expect(find.text('Jun Park'), findsOneWidget);
    // v11 的 AdminCard 不再在标题行重复渲染总数，改由分页条给出区间统计。
    expect(find.text('Create User'), findsOneWidget);
    expect(find.text('All roles'), findsOneWidget);
    expect(find.text('PROTECTED'), findsOneWidget);
    // 12 个用户按 10 条一页分成两页；分页条统一给首/前/页码/后/末一组按钮。
    expect(find.byTooltip('First page'), findsOneWidget);
    // 桌面分支不再叠移动口径的指标卡与分页条。
    expect(find.byType(WorkstationPaginationBar), findsNothing);
  });

  testWidgets('托管态：停用账号的开关关闭，超级管理员不给开关', (tester) async {
    await pumpUsers(tester, hosted: true);

    final toggle = tester.widget<DesktopToggle>(find.byType(DesktopToggle));
    expect(toggle.value, isFalse);
    expect(find.byType(DesktopToggle), findsOneWidget);
    expect(find.text('12.0 GB / 50.0 GB'), findsOneWidget);
  });
}
