import 'package:omninest/core/auth/auth_models.dart';

abstract class AuthSessionStore {
  String? readAccessToken();

  Future<String?> readRefreshToken();

  Future<void> saveSession(AuthTokenResponse session);

  Future<void> saveAccessToken(String? accessToken);

  Future<void> clear();
}

class MemoryAuthSessionStore implements AuthSessionStore {
  MemoryAuthSessionStore({this.keepRefreshToken = true});

  final bool keepRefreshToken;
  String? _accessToken;
  String? _refreshToken;

  @override
  String? readAccessToken() {
    return _accessToken;
  }

  @override
  Future<String?> readRefreshToken() async {
    return _refreshToken;
  }

  @override
  Future<void> saveSession(AuthTokenResponse session) async {
    _accessToken = session.accessToken;
    if (keepRefreshToken && session.refreshToken != null) {
      _refreshToken = session.refreshToken;
    }
  }

  @override
  Future<void> saveAccessToken(String? accessToken) async {
    _accessToken = accessToken;
  }

  @override
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
  }
}
