import 'dart:typed_data';

import 'package:omninest/features/profile/domain/user_session.dart';

/// 个人资料数据访问契约。
abstract interface class ProfileRepository {
  Future<String> uploadAvatar(Uint8List bytes, String fileName);

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  });

  Future<void> updateProfile({String? displayName, String? email});

  Future<List<UserSession>> getSessions();

  Future<void> revokeSession(String sessionId);
}
