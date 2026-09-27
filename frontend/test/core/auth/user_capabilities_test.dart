import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/auth/user_capabilities.dart';

UserProfile _user({
  String role = 'MEMBER',
  Set<String> roles = const {},
  Set<String> permissions = const {},
}) {
  return UserProfile(
    id: 'u1',
    username: 'u',
    role: role,
    roles: roles,
    permissions: permissions,
  );
}

void main() {
  test('GUEST 能力：可体验、不可贡献', () {
    final caps = UserCapabilities.fromUser(
      _user(
        role: 'GUEST',
        roles: {'GUEST'},
        permissions: {
          'profile:read',
          'profile:write',
          'activity:read',
          'activity:write',
          'preference:read',
          'preference:write',
          'file:read',
          'media:read',
          'photo:read',
          'backdrop:read',
        },
      ),
    );
    expect(caps.canBrowseContent, isTrue);
    expect(caps.canManageOwnActivity, isTrue);
    expect(caps.canManagePreferences, isTrue);
    expect(caps.canReportLocation, isTrue);
    expect(caps.canReadWeather, isTrue);
    expect(caps.canContributeContent, isFalse);
    expect(caps.canViewOwnTasks, isFalse);
    expect(caps.canAccessAdminConsole, isFalse);
    expect(caps.canSharedUpload, isFalse);
    expect(caps.canUploadBackdrop, isFalse);
  });

  test('MEMBER 能力：可贡献与本人任务', () {
    final caps = UserCapabilities.fromUser(
      _user(
        role: 'MEMBER',
        roles: {'MEMBER'},
        permissions: {
          'profile:read',
          'profile:write',
          'activity:read',
          'activity:write',
          'preference:read',
          'preference:write',
          'file:read',
          'file:write',
          'media:read',
          'media:write',
          'photo:read',
          'photo:write',
          'backdrop:read',
          'backdrop:write',
          'task:read',
        },
      ),
    );
    expect(caps.canContributeContent, isTrue);
    expect(caps.canViewOwnTasks, isTrue);
    expect(caps.canSharedUpload, isTrue);
    expect(caps.canAccessAdminConsole, isFalse);
    expect(caps.canAdminTasks, isFalse);
    expect(caps.canManageSystemConfig, isFalse);
  });

  test('ADMIN 能力：进管理台且不可写系统配置', () {
    final caps = UserCapabilities.fromUser(
      _user(
        role: 'ADMIN',
        roles: {'ADMIN'},
        permissions: {
          'profile:read',
          'system:config:read',
          'system:user:manage',
          'task:admin',
          'media:library:manage',
          'photo:admin',
          'media:read',
        },
      ),
    );
    expect(caps.canAccessAdminConsole, isTrue);
    expect(caps.canAdminTasks, isTrue);
    expect(caps.canManageMediaLibrary, isTrue);
    expect(caps.canManageSystemConfig, isFalse);
    expect(caps.canManageOwnActivity, isFalse);
  });

  test('未登录全 false', () {
    final caps = UserCapabilities.fromUser(null);
    expect(caps.canBrowseContent, isFalse);
    expect(caps.canReadWeather, isFalse);
  });
}
