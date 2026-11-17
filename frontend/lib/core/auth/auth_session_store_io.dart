import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';

AuthSessionStore createAuthSessionStore() {
  return SecureAuthSessionStore();
}

class SecureAuthSessionStore implements AuthSessionStore {
  SecureAuthSessionStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _refreshTokenKey = 'omninest.refreshToken';

  final FlutterSecureStorage _secureStorage;
  String? _accessToken;

  @override
  String? readAccessToken() {
    return _accessToken;
  }

  @override
  Future<String?> readRefreshToken() {
    return _secureStorage.read(key: _refreshTokenKey);
  }

  @override
  Future<void> saveSession(AuthTokenResponse session) async {
    _accessToken = session.accessToken;
    final refreshToken = session.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  @override
  Future<void> saveAccessToken(String? accessToken) async {
    _accessToken = accessToken;
  }

  @override
  Future<void> clear() async {
    _accessToken = null;
    await _secureStorage.delete(key: _refreshTokenKey);
  }
}
