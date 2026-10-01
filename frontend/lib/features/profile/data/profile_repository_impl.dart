import 'dart:typed_data';

import 'package:omninest/features/profile/data/me_api.dart';
import 'package:omninest/features/profile/domain/profile_repository.dart';
import 'package:omninest/features/profile/domain/user_session.dart';

/// 基于当前用户 API 的个人资料仓储实现。
class ProfileRepositoryImpl implements ProfileRepository {
  const ProfileRepositoryImpl(this._api);

  final MeApi _api;

  @override
  Future<String> uploadAvatar(Uint8List bytes, String fileName) {
    return _api.uploadAvatar(bytes, fileName);
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) {
    return _api.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }

  @override
  Future<void> updateProfile({String? displayName, String? email}) {
    return _api.updateMe(displayName: displayName, email: email);
  }

  @override
  Future<List<UserSession>> getSessions() {
    return _api.getSessions();
  }

  @override
  Future<void> revokeSession(String sessionId) {
    return _api.revokeSession(sessionId);
  }
}
