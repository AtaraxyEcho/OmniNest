import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/auth/auth_models.dart';

void main() {
  group('AuthLoginResult', () {
    test('两步验证挑战分支解析挑战字段', () {
      final result = AuthLoginResult.fromJson(const {
        'twoFactorRequired': true,
        'challengeToken': 'challenge-token',
        'challengeType': 'verify',
        'challengeExpiresAt': '2026-09-12T12:00:00Z',
      });

      expect(result.requiresTwoFactor, isTrue);
      expect(result.token, isNull);
      expect(result.challenge!.challengeToken, 'challenge-token');
      expect(result.challenge!.isEnrollment, isFalse);
    });

    test('enroll 挑战识别为注册引导', () {
      final result = AuthLoginResult.fromJson(const {
        'twoFactorRequired': true,
        'challengeToken': 'enroll-token',
        'challengeType': 'enroll',
      });

      expect(result.challenge!.isEnrollment, isTrue);
    });

    test('普通令牌分支解析完整会话', () {
      final result = AuthLoginResult.fromJson(const {
        'tokenType': 'Bearer',
        'accessToken': 'access',
        'expiresAt': '2026-09-12T12:00:00Z',
        'refreshToken': 'refresh',
        'refreshExpiresAt': '2026-10-12T12:00:00Z',
        'user': {
          'id': 'u-1',
          'username': 'admin',
          'role': 'ADMIN',
          'roles': ['ADMIN'],
          'permissions': ['system:config:manage'],
        },
      });

      expect(result.requiresTwoFactor, isFalse);
      expect(result.token, isNotNull);
      expect(result.token!.user.username, 'admin');
    });
  });

  group('TwoFactorBootstrapEnableData', () {
    test('解析备份码与完成令牌', () {
      final data = TwoFactorBootstrapEnableData.fromJson(const {
        'backupCodes': ['ABCD-2345', 'EFGH-6789'],
        'finalizeToken': 'finalize-token',
      });

      expect(data.backupCodes, ['ABCD-2345', 'EFGH-6789']);
      expect(data.finalizeToken, 'finalize-token');
    });

    test('备份码缺失时回落空列表', () {
      final data = TwoFactorBootstrapEnableData.fromJson(const {
        'finalizeToken': 'finalize-token',
      });

      expect(data.backupCodes, isEmpty);
    });
  });
}
