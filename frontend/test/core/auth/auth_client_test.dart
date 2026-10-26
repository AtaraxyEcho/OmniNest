import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/auth/auth_client.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';

class _CapturingLogoutAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode({'code': 200, 'message': 'success', 'data': null}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _jwtWithExpiry(DateTime expiry) {
  String segment(Object value) => base64Url
      .encode(utf8.encode(jsonEncode(value)))
      .replaceAll('=', '');
  return '${segment({'alg': 'HS256'})}.${segment({'exp': expiry.millisecondsSinceEpoch ~/ 1000})}.sig';
}

void main() {
  late AuthClient authClient;

  setUp(() {
    authClient = AuthClient(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
      ),
    );
  });

  test('parses successful login response', () {
    final result = authClient.parseAuthResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'tokenType': 'Bearer',
        'accessToken': 'token-value',
        'expiresAt': '2026-05-19T12:00:00Z',
        'refreshToken': 'refresh-token-value',
        'refreshExpiresAt': '2026-06-18T12:00:00Z',
        'user': {
          'id': '27f7d398-6f3a-4d2b-89bb-9483af60f84a',
          'username': 'root',
          'displayName': 'root',
          'email': 'root@example.com',
          'role': 'USER',
        },
      },
    });

    expect(result.tokenType, 'Bearer');
    expect(result.accessToken, 'token-value');
    expect(result.refreshToken, 'refresh-token-value');
    expect(
      result.refreshExpiresAt,
      DateTime.parse('2026-06-18T12:00:00Z').toLocal(),
    );
    expect(result.user.username, 'root');
  });

  test('throws app exception when login response is not success', () {
    expect(
      () => authClient.parseAuthResponse({
        'code': 401,
        'message': '用户名或密码错误',
        'data': null,
      }),
      throwsA(isA<AppException>()),
    );
  });

  test('logout keeps cookie credentials and drops expired access token', () async {
    final adapter = _CapturingLogoutAdapter();
    final client = AuthClient(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );

    await client.logout(
      refreshToken: 'refresh-token',
      accessToken: _jwtWithExpiry(
        DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );

    expect(adapter.lastRequest?.headers['Authorization'], isNull);
    expect(adapter.lastRequest?.extra['withCredentials'], isTrue);
  });

  test('logout sends bearer only while access token is still valid', () async {
    final adapter = _CapturingLogoutAdapter();
    final client = AuthClient(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );
    final token = _jwtWithExpiry(
      DateTime.now().add(const Duration(minutes: 5)),
    );

    await client.logout(refreshToken: 'refresh-token', accessToken: token);

    expect(adapter.lastRequest?.headers['Authorization'], 'Bearer $token');
  });
}
