import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/admin/data/admin_operations_api.dart';
import 'package:omninest/features/admin/data/admin_user_api.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';

class _MockAdminOperationsApi extends Mock implements AdminOperationsApi {}

class _MockAdminUserApi extends Mock implements AdminUserApi {}

class _ControllableAuthSessionNotifier extends AuthSessionNotifier {
  int refreshCalls = 0;

  @override
  Future<AuthSessionState> build() async =>
      const AuthSessionState.unauthenticated();

  void signInAs(String userId, String role) {
    state = AsyncData(
      AuthSessionState(
        user: UserProfile(
          id: userId,
          username: userId,
          role: role,
          roles: {role},
        ),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }

  @override
  Future<bool> refreshSession() async {
    refreshCalls += 1;
    return true;
  }
}

void main() {
  test('role permission update refreshes session only for own roles', () async {
    final api = _MockAdminOperationsApi();
    const roleDetail = AdminRoleDetail(
      code: 'MEMBER',
      name: 'Member',
      description: '',
      builtIn: true,
      enabled: true,
      permissions: <String>[],
    );
    when(
      () => api.updateRolePermissions(any(), any()),
    ).thenAnswer((_) async => roleDetail);
    final container = ProviderContainer.test(
      overrides: [
        adminOperationsApiProvider.overrideWithValue(api),
        authSessionProvider.overrideWith(_ControllableAuthSessionNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    final auth =
        container.read(authSessionProvider.notifier)
            as _ControllableAuthSessionNotifier;
    await container.read(authSessionProvider.future);
    auth.signInAs('user-a', 'MEMBER');

    final actions = container.read(adminOperationsActionsProvider);
    await actions.updateRolePermissions('ADMIN', const {'file:read'});
    expect(auth.refreshCalls, 0);

    await actions.updateRolePermissions('MEMBER', const {'file:read'});
    expect(auth.refreshCalls, 1);
  });

  test('updating own roles refreshes session, others do not', () async {
    final api = _MockAdminUserApi();
    const updatedUser = AdminUser(
      id: 'user-a',
      username: 'user-a',
      status: 'ACTIVE',
      role: 'ADMIN',
      roles: {'ADMIN'},
      permissions: <String>{},
      quotaBytes: 0,
      usedBytes: 0,
    );
    when(
      () => api.updateUserRoles(any(), any()),
    ).thenAnswer((_) async => updatedUser);
    when(
      () => api.listUsers(page: any(named: 'page'), size: any(named: 'size')),
    ).thenAnswer((_) async => (items: <AdminUser>[], total: 0));
    final container = ProviderContainer.test(
      overrides: [
        adminUserApiProvider.overrideWithValue(api),
        authSessionProvider.overrideWith(_ControllableAuthSessionNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    final auth =
        container.read(authSessionProvider.notifier)
            as _ControllableAuthSessionNotifier;
    await container.read(authSessionProvider.future);
    auth.signInAs('user-a', 'MEMBER');

    final controller = container.read(adminUserControllerProvider.notifier);
    await controller.updateUserRoles('user-b', const {'ADMIN'});
    expect(auth.refreshCalls, 0);

    await controller.updateUserRoles('user-a', const {'ADMIN'});
    expect(auth.refreshCalls, 1);
  });
}
