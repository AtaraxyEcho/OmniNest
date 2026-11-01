import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/network/session_gate.dart';

/// 会话结束后的请求闸门测试。
///
/// <p>退出登录会让 Photo/File 等 provider 立即重建，并各自发出一个注定 401 的
/// 请求。闸门的作用是让这批请求停在本地，同时不得误伤真正匿名可达的端点。</p>
void main() {
  test('会话结束后业务请求不再发出，本地按 401 拒绝', () async {
    final adapter = _CountingAdapter();
    final client = _client(adapter, readToken: () => null)..markSessionEnded();

    await expectLater(
      client.dio.get<Map<String, dynamic>>('/files?page=0'),
      throwsA(
        isA<DioException>()
            .having((error) => error.response?.statusCode, 'statusCode', 401)
            .having(
              (error) => error.error,
              'error',
              isA<AppException>().having(
                (exception) => exception.code,
                'code',
                'UNAUTHORIZED',
              ),
            )
            .having(
              (error) => error.response?.data,
              'errorName',
              containsPair('errorName', 'UNAUTHORIZED'),
            ),
      ),
    );

    expect(adapter.paths, isEmpty);
  });

  test('登出后的批量重建只有一次请求真的出网就能证明闸门生效', () async {
    final adapter = _CountingAdapter();
    final client = _client(adapter, readToken: () => null)..markSessionEnded();

    // 模拟 provider 级联：8 个不同业务端点同时重建。
    for (final path in <String>[
      '/photos/timeline',
      '/files',
      '/music/albums',
      '/video/library',
      '/reader/books',
      '/tasks',
      '/notifications',
      '/admin/operations/logs',
    ]) {
      await expectLater(
        client.dio.get<Map<String, dynamic>>(path),
        throwsA(isA<DioException>()),
      );
    }

    expect(adapter.paths, isEmpty);
  });

  test('匿名端点不受闸门影响', () async {
    final adapter = _CountingAdapter();
    final client = _client(adapter, readToken: () => null)..markSessionEnded();

    const anonymousPaths = <String>[
      '/auth/login',
      '/auth/register',
      '/auth/refresh',
      '/auth/logout',
      '/setup/status',
      '/setup/super-admin',
      '/s/share-token',
      '/s/share-token/authorize',
      '/s/share-token/preview',
      '/s/share-token/children',
      '/public/bootstrap',
      '/share/abc',
      '/external-connectors/conn-1/oauth/callback',
      '/music/playback/sessions/session-1/stream',
    ];
    for (final path in anonymousPaths) {
      await client.dio.get<Map<String, dynamic>>(path);
    }

    expect(adapter.paths, anonymousPaths);
  });

  test('会话未结束时无令牌请求仍照常发出，保留首启 401 刷新恢复', () async {
    final adapter = _CountingAdapter();
    final client = _client(adapter, readToken: () => null);

    await client.dio.get<Map<String, dynamic>>('/files');

    // 首启时内存里还没有令牌是正常状态：请求必须出网，靠 401 触发刷新恢复。
    expect(adapter.paths, ['/files']);
  });

  test('重新登录携带令牌后闸门解除', () async {
    String? token;
    final adapter = _CountingAdapter();
    final client = _client(adapter, readToken: () => token)..markSessionEnded();

    await expectLater(
      client.dio.get<Map<String, dynamic>>('/files'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.paths, isEmpty);

    token = 'fresh-token';
    final response = await client.dio.get<Map<String, dynamic>>('/files');

    expect(response.statusCode, 200);
    expect(adapter.paths, ['/files']);
    expect(adapter.authorizations, ['Bearer fresh-token']);
  });

  test('外部签名地址不参与闸门，也不会被判成需要身份', () async {
    final adapter = _CountingAdapter();
    final client = _client(adapter, readToken: () => null)..markSessionEnded();

    final response = await client.dio.get<String>(
      'https://storage.example/book.epub?signature=test',
      options: Options(
        responseType: ResponseType.plain,
        extra: const {ApiClient.skipAuthorizationKey: true},
      ),
    );

    expect(response.statusCode, 200);
    expect(adapter.paths, ['https://storage.example/book.epub?signature=test']);
  });

  test('共享闸门覆盖登出后重建的客户端', () async {
    final gate = SessionGate();
    final adapter = _CountingAdapter();
    // 登出会重建 ApiClient：新实例必须继承已结束状态，而不是重新放行。
    final rebuilt = _client(adapter, readToken: () => null, sessionGate: gate);
    gate.markEnded();

    await expectLater(
      rebuilt.dio.get<Map<String, dynamic>>('/photos/timeline'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.paths, isEmpty);
  });

  test('需要身份的判定锚定在路径分段上', () {
    expect(ApiClient.requiresSession('/files'), isTrue);
    expect(ApiClient.requiresSession('/photos/timeline'), isTrue);
    // 前缀近似但并非匿名端点：不能让 /settlement 之类借 /setup 漏过。
    expect(ApiClient.requiresSession('/settings'), isTrue);
    expect(ApiClient.requiresSession('/publications'), isTrue);
    expect(ApiClient.requiresSession('/shared/files'), isTrue);
    expect(ApiClient.requiresSession('/s'), isTrue);

    expect(ApiClient.requiresSession('/setup/status'), isFalse);
    expect(ApiClient.requiresSession('/public/bootstrap'), isFalse);
    expect(ApiClient.requiresSession('/s/token/preview'), isFalse);
  });
}

ApiClient _client(
  _CountingAdapter adapter, {
  required String? Function() readToken,
  SessionGate? sessionGate,
}) {
  return ApiClient(
    const AppEnvironment(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      wsBaseUrl: 'ws://localhost:8080/ws',
    ),
    readAccessToken: readToken,
    refreshSession: () async => false,
    sessionGate: sessionGate,
    httpClientAdapter: adapter,
  );
}

/// 只记录出网路径的适配器：闸门生效时应当一条都收不到。
class _CountingAdapter implements HttpClientAdapter {
  final List<String> paths = <String>[];
  final List<String> authorizations = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final authorization = options.headers['Authorization']?.toString();
    if (authorization != null) {
      authorizations.add(authorization);
    }
    return ResponseBody.fromString(
      '{"code":200,"message":"success","data":{}}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
