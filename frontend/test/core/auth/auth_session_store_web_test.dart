import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/auth/auth_session_store_web.dart';

void main() {
  test('Web 会话存储仅保留访问令牌', () async {
    final store = WebAuthSessionStore();
    final session = AuthTokenResponse(
      tokenType: 'Bearer',
      accessToken: 'access-token',
      expiresAt: DateTime.utc(2026, 8, 24, 12),
      refreshToken: 'refresh-token',
      refreshExpiresAt: DateTime.utc(2026, 9, 24, 12),
      user: UserProfile(id: '1', username: 'root', role: 'SUPER_ADMIN'),
    );

    await store.saveSession(session);

    expect(store.readAccessToken(), 'access-token');
    expect(await store.readRefreshToken(), isNull);
  });

  test('清理 Web 会话会移除访问令牌', () async {
    final store = WebAuthSessionStore();
    await store.saveAccessToken('access-token');

    await store.clear();

    expect(store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });
}
