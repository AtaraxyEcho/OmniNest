import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';

import 'desktop_test_harness.dart';

const AdminRoleManagementView _view = AdminRoleManagementView(
  roles: [
    AdminRoleDetail(
      code: 'SUPER_ADMIN',
      name: 'Super Admin',
      description: 'Holds every permission and is read-only by design.',
      builtIn: true,
      enabled: true,
      permissions: ['file:read', 'file:write', 'system:config:write'],
    ),
    AdminRoleDetail(
      code: 'ROLE_EDITOR',
      name: 'Editor',
      description: 'Curates the shared library.',
      builtIn: false,
      enabled: true,
      permissions: ['file:read'],
    ),
  ],
  permissions: [
    AdminPermissionDetail(
      code: 'file:read',
      name: 'Read files',
      module: 'file',
      description: '',
      enabled: true,
    ),
    AdminPermissionDetail(
      code: 'file:write',
      name: 'Write files',
      module: 'file',
      description: '',
      enabled: true,
    ),
    AdminPermissionDetail(
      code: 'system:config:write',
      name: 'Write config',
      module: 'system',
      description: '',
      enabled: true,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('托管态角色分区画角色卡与权限矩阵卡', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: wrapDesktop(
          const DesktopShellScope(
            hosted: true,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: AdminRolesPage(view: _view),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Super Admin'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Built-in'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('New custom role'), findsOneWidget);
    // 权限比文案：3 / 3 与 1 / 3。
    expect(find.text('3 / 3 permissions selected'), findsOneWidget);
    expect(find.text('1 / 3 permissions selected'), findsOneWidget);
    // 矩阵卡按模块分组。
    expect(find.text('FILE'), findsOneWidget);
    expect(find.text('SYSTEM'), findsOneWidget);
  });
}
