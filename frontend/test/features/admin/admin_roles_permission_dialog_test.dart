import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';

const _permissions = [
  AdminPermissionDetail(
    code: 'file:read',
    name: '读取文件',
    module: 'file',
    description: '',
    enabled: true,
  ),
  AdminPermissionDetail(
    code: 'file:write',
    name: '写入文件',
    module: 'file',
    description: '',
    enabled: true,
  ),
  AdminPermissionDetail(
    code: 'file:legacy',
    name: '废弃能力',
    module: 'file',
    description: '',
    enabled: false,
  ),
  AdminPermissionDetail(
    code: 'task:admin',
    name: '任务管理',
    module: 'task',
    description: '',
    enabled: true,
  ),
];

const _roleView = AdminRoleManagementView(
  roles: [
    AdminRoleDetail(
      code: 'ROLE_TEST',
      name: '测试角色',
      description: '',
      builtIn: false,
      enabled: true,
      permissions: ['file:read'],
    ),
  ],
  permissions: _permissions,
);

/// 捕获保存集合的假应用层动作。
class _CapturingActions extends AdminOperationsActions {
  _CapturingActions(super.ref, this.savedPermissions, this.savedRoleCode);

  final List<Set<String>> savedPermissions;
  final List<String> savedRoleCode;

  @override
  Future<void> updateRolePermissions(
    String roleCode,
    Set<String> permissions,
  ) async {
    savedRoleCode.add(roleCode);
    savedPermissions.add(permissions.toSet());
  }
}

void main() {
  testWidgets('角色权限弹窗树形选择：模块联动 + 单项，保存扁平 code 集合', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final savedPermissions = <Set<String>>[];
    final savedRoleCode = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRolesProvider.overrideWith((ref) => Future.value(_roleView)),
          adminOperationsActionsProvider.overrideWith(
            (ref) => _CapturingActions(ref, savedPermissions, savedRoleCode),
          ),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(child: AdminRolesPage(view: _roleView)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('配置权限'));
    await tester.pumpAndSettle();
    final dialogFinder = find.byType(WorkstationDialogFrame);
    expect(dialogFinder, findsOneWidget);
    // 初始继承角色现有权限：file:read 已勾选，模块计数 1/3 半选。
    expect(
      find.descendant(of: dialogFinder, matching: find.text('✔')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialogFinder, matching: find.text('1/3')),
      findsOneWidget,
    );

    // 勾选 file 模块 → 全组启用项选中（模块 + 2 子项 = 3 个 ✔）。
    await tester.tap(
      find.descendant(
        of: find.descendant(
          of: dialogFinder,
          matching: find.byKey(const ValueKey('admin-permission-module-file')),
        ),
        matching: find.byType(WorkstationCheckMark),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: dialogFinder, matching: find.text('2/3')),
      findsOneWidget,
    );

    // 再勾选 task 子项，保存集合 = 两个 file 启用 code + task code。
    await tester.tap(
      find.descendant(
        of: find.descendant(
          of: dialogFinder,
          matching: find.byKey(
            const ValueKey('admin-permission-row-task:admin'),
          ),
        ),
        matching: find.byType(WorkstationCheckMark),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: dialogFinder, matching: find.text('保存')),
    );
    await tester.pumpAndSettle();

    expect(savedRoleCode, ['ROLE_TEST']);
    expect(savedPermissions.single, {'file:read', 'file:write', 'task:admin'});
    // 保存后弹窗关闭。
    expect(find.byType(WorkstationDialogFrame), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
