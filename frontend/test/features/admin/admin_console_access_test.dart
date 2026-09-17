import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/admin/domain/admin_console_access.dart';

void main() {
  test('MEMBER 默认不可进入管理台', () {
    expect(
      canAccessAdminConsole(
        userRole: 'MEMBER',
        userPermissions: const {
          'file:read',
          'file:write',
          'media:read',
          'task:read',
        },
      ),
      isFalse,
    );
  });

  test('ADMIN/SUPER_ADMIN 可进入管理台', () {
    expect(canAccessAdminConsole(userRole: 'ADMIN'), isTrue);
    expect(canAccessAdminConsole(userRole: 'SUPER_ADMIN'), isTrue);
  });

  test('持管理权限码的自定义角色可进入管理台', () {
    expect(
      canAccessAdminConsole(
        userRole: 'MEMBER',
        userPermissions: const {'task:admin'},
      ),
      isTrue,
    );
    expect(
      canAccessAdminConsole(
        userRole: 'OPS',
        userPermissions: const {'media:library:manage'},
      ),
      isTrue,
    );
  });

  test('UserProfile 推导与角色/权限一致', () {
    final member = UserProfile(
      id: 'u1',
      username: 'member',
      email: 'm@example.com',
      role: 'MEMBER',
      permissions: const {'file:read'},
    );
    expect(canAccessAdminConsoleUser(member), isFalse);

    final admin = UserProfile(
      id: 'u2',
      username: 'admin',
      email: 'a@example.com',
      role: 'ADMIN',
    );
    expect(canAccessAdminConsoleUser(admin), isTrue);
  });
}
