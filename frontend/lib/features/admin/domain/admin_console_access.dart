import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';

/// 管理台入口权限码。
///
/// 与 [AdminSection] 分区权限不同：此处仅判定能否进入 `/admin` 壳层；
/// 分区细粒度仍由各分区的 `requiredAnyPermissions` 控制。
const Set<String> adminConsoleEntryPermissionCodes = {
  'system:config:read',
  'system:config:manage',
  'system:user:read',
  'system:user:manage',
  'task:admin',
  'media:library:manage',
  'photo:admin',
};

const Set<String> _adminConsoleRoleCodes = {'ADMIN', 'SUPER_ADMIN'};

/// 是否可进入系统管理台。
///
/// 管理角色或持有任一管理台入口权限码即可；纯 MEMBER 默认不可见、不可进。
bool canAccessAdminConsole({
  String? userRole,
  Set<String>? userPermissions,
  Set<String>? userRoles,
}) {
  final roles = <String>{
    if (userRole != null && userRole.isNotEmpty) userRole,
    ...?userRoles,
  };
  if (roles.any(_adminConsoleRoleCodes.contains)) {
    return true;
  }
  final permissions = userPermissions ?? const <String>{};
  return permissions.any(adminConsoleEntryPermissionCodes.contains);
}

/// 从会话用户推导管理台可见性。
bool canAccessAdminConsoleUser(UserProfile? user) {
  if (user == null) {
    return false;
  }
  return canAccessAdminConsole(
    userRole: user.role,
    userPermissions: user.permissions,
    userRoles: user.roles,
  );
}

/// 当前会话是否可进入系统管理台。
final canAccessAdminConsoleProvider = Provider<bool>((ref) {
  final session = ref.watch(authSessionProvider).asData?.value;
  return canAccessAdminConsoleUser(session?.user);
});
