import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_client.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/login_page.dart';

/// 登录页两步验证流测试：
/// - 密码登录返回挑战时切换到验证码面板且不落会话；
/// - 提交验证码后调用 verifyTwoFactor 并跳转门户。
class _FakeAuthClient extends AuthClient {
  _FakeAuthClient() : super(Dio(BaseOptions(validateStatus: (status) => true)));

  String? lastChallengeToken;
  String? lastCode;

  @override
  Future<AuthLoginResult> login({
    required String username,
    required String password,
  }) async {
    return AuthLoginResult(challenge: _verifyChallenge('challenge-token'));
  }

  @override
  Future<AuthTokenResponse> verifyTwoFactor({
    required String challengeToken,
    required String code,
  }) async {
    lastChallengeToken = challengeToken;
    lastCode = code;
    return AuthTokenResponse.fromJson(const {
      'tokenType': 'Bearer',
      'accessToken': 'access',
      'expiresAt': '2999-01-01T00:00:00Z',
      'refreshToken': 'refresh',
      'refreshExpiresAt': '2999-01-01T00:00:00Z',
      'user': {
        'id': 'u-1',
        'username': 'admin',
        'role': 'ADMIN',
        'roles': ['ADMIN'],
        'permissions': <String>[],
      },
    });
  }
}

AuthChallenge _verifyChallenge(String token) {
  return AuthChallenge.fromJson({
    'twoFactorRequired': true,
    'challengeToken': token,
    'challengeType': 'verify',
  });
}

void main() {
  testWidgets('密码登录返回挑战时展示验证码面板且不再显示登录表单', (tester) async {
    final fake = _FakeAuthClient();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'admin@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('twoFactorCodeField')), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(fake.lastChallengeToken, isNull);
  });

  testWidgets('提交验证码后调用两步验证登录并跳转门户', (tester) async {
    final fake = _FakeAuthClient();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'admin@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('twoFactorCodeField')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('twoFactorVerifyButton')));
    await tester.pumpAndSettle();

    expect(fake.lastChallengeToken, 'challenge-token');
    expect(fake.lastCode, '123456');
    expect(find.byKey(const Key('portal-landing')), findsOneWidget);
  });
}

Widget _host(_FakeAuthClient client) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/portal',
        builder:
            (_, _) => const Scaffold(
              key: Key('portal-landing'),
              body: SizedBox.expand(),
            ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authClientProvider.overrideWithValue(client),
      authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}
