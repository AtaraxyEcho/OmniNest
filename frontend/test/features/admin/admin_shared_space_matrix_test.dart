import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';

class _SessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => AuthSessionState(
    user: UserProfile(
      id: 'user-1',
      username: 'admin',
      role: 'ADMIN',
      permissions: {
        'system:user:read',
        'system:config:read',
        'system:config:manage',
      },
    ),
  );
}

class _RecordingActions extends AdminOperationsActions {
  _RecordingActions(super.ref);

  final List<List<AdminSharedSpacePermission>> saved = [];

  @override
  Future<void> updateSharedSpaceRolePermissions(
    List<AdminSharedSpacePermission> permissions,
  ) async {
    saved.add(permissions);
  }
}

const _view = AdminRoleManagementView(
  roles: [
    AdminRoleDetail(
      code: 'MEMBER',
      name: '成员',
      description: '',
      builtIn: true,
      enabled: true,
      permissions: [],
    ),
  ],
  permissions: [],
);

const _permission = AdminSharedSpacePermission(
  roleId: 'role-1',
  roleCode: 'MEMBER',
  canBrowse: true,
  canUpload: false,
  canDownload: false,
  canDeleteOwn: false,
  canDeleteAny: false,
  canMoveTo: false,
  canMoveFrom: false,
  canCreateFolder: false,
);

void main() {
  testWidgets('勾选后确认保存，整批提交一次', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late _RecordingActions actions;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_SessionNotifier.new),
          sharedSpacePermissionsProvider.overrideWith(
            (ref) => Future.value(const [_permission]),
          ),
          adminOperationsActionsProvider.overrideWith((ref) {
            actions = _RecordingActions(ref);
            return actions;
          }),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(child: AdminRolesPage(view: _view)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AdminRolesPage)),
    );
    actions = ProviderScope.containerOf(
      tester.element(find.byType(AdminRolesPage)),
    ).read(adminOperationsActionsProvider) as _RecordingActions;

    // 浏览位默认勾选；取消后矩阵进入脏状态，保存按钮才可用。
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.adminSharedSpaceMatrixSave),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WorkstationDialogFrame), findsOneWidget);
    expect(actions.saved, isEmpty);

    await tester.tap(
      find.widgetWithText(FilledButton, l10n.adminMaintenanceConfirm),
    );
    await tester.pumpAndSettle();

    expect(actions.saved, hasLength(1));
    expect(actions.saved.single.first.canBrowse, isFalse);
    await tester.pump(const Duration(seconds: 10));
  });
}
