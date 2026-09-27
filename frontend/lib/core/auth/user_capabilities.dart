import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';

/// 登录用户能力矩阵：由 permissions + roles 一次推导，UI 与自动写回统一门控。
class UserCapabilities {
  const UserCapabilities({
    required this.canBrowseContent,
    required this.canContributeContent,
    required this.canManageOwnActivity,
    required this.canManagePreferences,
    required this.canManageAccount,
    required this.canUseBackdropLibrary,
    required this.canUploadBackdrop,
    required this.canViewOwnTasks,
    required this.canAdminTasks,
    required this.canManageMediaLibrary,
    required this.canManagePhotos,
    required this.canAdminUsers,
    required this.canReadSystemConfig,
    required this.canManageSystemConfig,
    required this.canAccessAdminConsole,
    required this.canSharedBrowse,
    required this.canSharedUpload,
    required this.canReadWeather,
    required this.canReportLocation,
    required this.canManageTwoFactor,
    required this.canReadActivity,
  });

  final bool canBrowseContent;
  final bool canContributeContent;
  final bool canManageOwnActivity;
  final bool canManagePreferences;
  final bool canManageAccount;
  final bool canUseBackdropLibrary;
  final bool canUploadBackdrop;
  final bool canViewOwnTasks;
  final bool canAdminTasks;
  final bool canManageMediaLibrary;
  final bool canManagePhotos;
  final bool canAdminUsers;
  final bool canReadSystemConfig;
  final bool canManageSystemConfig;
  final bool canAccessAdminConsole;
  final bool canSharedBrowse;
  final bool canSharedUpload;
  final bool canReadWeather;
  final bool canReportLocation;
  final bool canManageTwoFactor;
  final bool canReadActivity;

  factory UserCapabilities.fromUser(UserProfile? user) {
    if (user == null) {
      return const UserCapabilities(
        canBrowseContent: false,
        canContributeContent: false,
        canManageOwnActivity: false,
        canManagePreferences: false,
        canManageAccount: false,
        canUseBackdropLibrary: false,
        canUploadBackdrop: false,
        canViewOwnTasks: false,
        canAdminTasks: false,
        canManageMediaLibrary: false,
        canManagePhotos: false,
        canAdminUsers: false,
        canReadSystemConfig: false,
        canManageSystemConfig: false,
        canAccessAdminConsole: false,
        canSharedBrowse: false,
        canSharedUpload: false,
        canReadWeather: false,
        canReportLocation: false,
        canManageTwoFactor: false,
        canReadActivity: false,
      );
    }
    final permissions = user.permissions;
    bool has(String code) => permissions.contains(code);
    final canReadAnyContent =
        has('file:read') || has('media:read') || has('photo:read');
    final canWriteAnyContent =
        has('file:write') || has('media:write') || has('photo:write');
    final roles = {user.role, ...user.roles};
    final isAdminRole =
        roles.contains('ADMIN') || roles.contains('SUPER_ADMIN');
    final canAccessAdmin =
        isAdminRole ||
        has('system:config:read') ||
        has('system:config:manage') ||
        has('system:user:read') ||
        has('system:user:manage') ||
        has('task:admin') ||
        has('media:library:manage') ||
        has('photo:admin');
    return UserCapabilities(
      canBrowseContent: canReadAnyContent,
      canContributeContent: canWriteAnyContent,
      canManageOwnActivity: has('activity:write'),
      canManagePreferences: has('preference:write'),
      canManageAccount: has('profile:write'),
      canUseBackdropLibrary: has('backdrop:read'),
      canUploadBackdrop: has('backdrop:write'),
      canViewOwnTasks: has('task:read'),
      canAdminTasks: has('task:admin'),
      canManageMediaLibrary: has('media:library:manage'),
      canManagePhotos: has('photo:admin'),
      canAdminUsers: has('system:user:read') || has('system:user:manage'),
      canReadSystemConfig: has('system:config:read'),
      canManageSystemConfig: has('system:config:manage'),
      canAccessAdminConsole: canAccessAdmin,
      canSharedBrowse: has('file:read'),
      canSharedUpload: has('file:write'),
      canReadWeather: true,
      canReportLocation: has('activity:write'),
      canManageTwoFactor: has('profile:write'),
      canReadActivity: has('activity:read'),
    );
  }
}

/// 当前会话用户能力；未登录时为全 false。
final userCapabilitiesProvider = Provider<UserCapabilities>((ref) {
  final session = ref.watch(authSessionProvider).asData?.value;
  return UserCapabilities.fromUser(session?.user);
});
