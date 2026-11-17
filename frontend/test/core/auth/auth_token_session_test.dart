import 'package:omninest/core/auth/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session is valid before expiration safety window', () {
    final session = AuthTokenResponse(
      tokenType: 'Bearer',
      accessToken: 'token-value',
      expiresAt: DateTime.utc(2026, 5, 20, 12),
      user: UserProfile(id: '1', username: 'root', role: 'SUPER_ADMIN'),
    );

    expect(session.isExpired(now: DateTime.utc(2026, 5, 20, 11, 50)), isFalse);
  });

  test('session is expired inside expiration safety window', () {
    final session = AuthTokenResponse(
      tokenType: 'Bearer',
      accessToken: 'token-value',
      expiresAt: DateTime.utc(2026, 5, 20, 12),
      user: UserProfile(id: '1', username: 'root', role: 'SUPER_ADMIN'),
    );

    expect(session.isExpired(now: DateTime.utc(2026, 5, 20, 11, 59)), isTrue);
  });

  test('roles and permissions survive persisted session round trip', () {
    final source = AuthTokenResponse(
      tokenType: 'Bearer',
      accessToken: 'token-value',
      expiresAt: DateTime.utc(2026, 5, 20, 12),
      user: UserProfile(
        id: '1',
        username: 'root',
        role: 'ADMIN',
        roles: {'MEMBER', 'ADMIN'},
        permissions: {'media:read', 'media:library:manage'},
      ),
    );

    final restored = AuthTokenResponse.fromJson(source.toJson());

    expect(restored.user.roles, {'MEMBER', 'ADMIN'});
    expect(restored.user.permissions, {'media:read', 'media:library:manage'});
    expect(
      () => restored.user.permissions.add('system:config:manage'),
      throwsUnsupportedError,
    );
  });
}
