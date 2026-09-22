import 'dart:typed_data';
import 'package:omninest/app/session/session_epoch.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/profile/data/profile_repository_impl.dart';
import 'package:omninest/features/profile/domain/profile_repository.dart';
import 'package:omninest/features/profile/domain/user_profile.dart';
import 'package:omninest/features/profile/domain/user_session.dart';

/// 个人资料仓储依赖注入入口。
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepositoryImpl(ref.watch(meApiProvider));
});

/// 个人资料用户命令服务。
final profileCommandServiceProvider = Provider<ProfileCommandService>((ref) {
  return ProfileCommandService(ref.watch(profileRepositoryProvider));
});

/// 协调个人资料写操作。
class ProfileCommandService {
  const ProfileCommandService(this._repository);

  final ProfileRepository _repository;

  Future<String> uploadAvatar(Uint8List bytes, String fileName) {
    return _repository.uploadAvatar(bytes, fileName);
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) {
    return _repository.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }

  Future<void> revokeSession(String sessionId) {
    return _repository.revokeSession(sessionId);
  }
}

/// 当前用户资料 Provider（从 auth session 中提取）
final userProfileProvider = Provider<UserProfile?>((ref) {
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session?.user == null) return null;
  return UserProfile.fromJson(session!.user!.toJson());
});

/// 用户显示名称 Provider
final userDisplayNameProvider = Provider<String>((ref) {
  final profile = ref.watch(userProfileProvider);
  return profile?.effectiveName ?? '';
});

/// 用户头像 URL Provider
final userAvatarUrlProvider = Provider<String?>((ref) {
  return ref.watch(userProfileProvider)?.avatarUrl;
});

/// 用户角色 Provider
final userRoleProvider = Provider<String>((ref) {
  return ref.watch(userProfileProvider)?.role ?? 'MEMBER';
});

/// 是否为管理员 Provider
final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(userProfileProvider)?.isAdmin ?? false;
});

/// 当前用户活跃会话列表 Provider。
final userSessionsProvider = FutureProvider<List<UserSession>>((ref) async {
  ref.watch(sessionEpochProvider);
  return ref.watch(profileRepositoryProvider).getSessions();
});
