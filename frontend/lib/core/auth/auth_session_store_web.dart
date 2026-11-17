import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';

AuthSessionStore createAuthSessionStore() {
  return WebAuthSessionStore();
}

/// Web 端会话存储。Token 仅保存在内存中。
///
/// 页面刷新后的会话恢复由后端 HttpOnly Cookie 兜底，避免将 Refresh Token
/// 暴露给 localStorage 或 IndexedDB。
class WebAuthSessionStore implements AuthSessionStore {
  String? _accessToken;

  @override
  String? readAccessToken() {
    return _accessToken;
  }

  @override
  Future<String?> readRefreshToken() async {
    return null;
  }

  @override
  Future<void> saveSession(AuthTokenResponse session) async {
    _accessToken = session.accessToken;
  }

  @override
  Future<void> saveAccessToken(String? accessToken) async {
    _accessToken = accessToken;
  }

  @override
  Future<void> clear() async {
    _accessToken = null;
  }
}
