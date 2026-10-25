import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';

void main() {
  test('401 只会触发一次刷新并重放并发请求', () async {
    var accessToken = 'expired-token';
    var refreshCount = 0;
    final adapter = _ReplayAdapter();

    final client = ApiClient(
      const AppEnvironment(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        wsBaseUrl: 'ws://localhost:8080/ws',
      ),
      readAccessToken: () => accessToken,
      refreshSession: () async {
        refreshCount++;
        accessToken = 'fresh-token';
        return true;
      },
      httpClientAdapter: adapter,
    );

    final responses = await Future.wait([
      client.dio.get<Map<String, dynamic>>('/secure'),
      client.dio.get<Map<String, dynamic>>('/secure'),
    ]);

    expect(refreshCount, 1);
    expect(responses, hasLength(2));
    expect(
      responses.every((response) => response.data?['code'] == 200),
      isTrue,
    );
    expect(adapter.secureRequestCount, 4);
  });

  test('二进制接口的 401 也刷新令牌并重放请求', () async {
    var accessToken = 'expired-token';
    var refreshCount = 0;
    final adapter = _ReplayAdapter();

    final client = ApiClient(
      const AppEnvironment(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        wsBaseUrl: 'ws://localhost:8080/ws',
      ),
      readAccessToken: () => accessToken,
      refreshSession: () async {
        refreshCount++;
        accessToken = 'fresh-token';
        return true;
      },
      httpClientAdapter: adapter,
    );

    final response = await client.dio.get<List<int>>(
      '/binary',
      options: Options(
        responseType: ResponseType.bytes,
        // 二进制接口在请求级覆写为仅 2xx 成功，401 会走 onError 而不是 onResponse。
        validateStatus:
            (status) => status != null && status >= 200 && status < 300,
      ),
    );

    expect(response.statusCode, 200);
    expect(response.data, [1, 2, 3]);
    expect(refreshCount, 1);
    expect(adapter.binaryRequestCount, 2);
  });

  test('外部签名地址不会携带 JWT 或触发会话刷新', () async {
    var refreshCount = 0;
    final adapter = _ReplayAdapter();
    final client = ApiClient(
      const AppEnvironment(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        wsBaseUrl: 'ws://localhost:8080/ws',
      ),
      readAccessToken: () => 'private-jwt',
      refreshSession: () async {
        refreshCount++;
        return true;
      },
      httpClientAdapter: adapter,
    );

    final response = await client.dio.get<String>(
      'https://storage.example/book.epub?signature=test',
      options: Options(
        responseType: ResponseType.plain,
        extra: const {ApiClient.skipAuthorizationKey: true},
      ),
    );

    expect(response.statusCode, 401);
    expect(adapter.externalAuthorization, isNull);
    expect(refreshCount, 0);
  });

  test('403 按权限拒绝原样返回，不轮换刷新令牌也不重放请求', () async {
    var refreshCount = 0;
    final adapter = _ReplayAdapter();
    final client = ApiClient(
      const AppEnvironment(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        wsBaseUrl: 'ws://localhost:8080/ws',
      ),
      readAccessToken: () => 'stale-claims-token',
      refreshSession: () async {
        refreshCount++;
        return true;
      },
      httpClientAdapter: adapter,
    );

    final response = await client.dio.get<Map<String, dynamic>>('/forbidden');

    expect(response.statusCode, 403);
    expect(refreshCount, 0);
    expect(adapter.forbiddenRequestCount, 1);
  });

  test('声明过期的 403 同样交回业务层，不由拦截器盲刷会话', () async {
    // 权限变更时服务端已吊销旧会话（表现为 401），管理端改动自己也显式刷新；
    // 让每个 403 都换一枚新令牌只会多付一次刷新与一次重放。
    var refreshCount = 0;
    final adapter = _ReplayAdapter();
    final client = ApiClient(
      const AppEnvironment(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        wsBaseUrl: 'ws://localhost:8080/ws',
      ),
      readAccessToken: () => 'stale-claims-token',
      refreshSession: () async {
        refreshCount++;
        return true;
      },
      httpClientAdapter: adapter,
    );

    final response = await client.dio.get<Map<String, dynamic>>('/claims');

    expect(response.statusCode, 403);
    expect(refreshCount, 0);
    expect(adapter.claimAuthorizationHeaders, ['Bearer stale-claims-token']);
  });

  test('刷新失败时原样上抛 401 且不触发登出（分级由会话通知器负责）', () async {
    var refreshCount = 0;
    final adapter = _ReplayAdapter();
    final client = ApiClient(
      const AppEnvironment(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        wsBaseUrl: 'ws://localhost:8080/ws',
      ),
      readAccessToken: () => 'expired-token',
      refreshSession: () async {
        refreshCount++;
        return false;
      },
      httpClientAdapter: adapter,
    );

    await expectLater(
      client.dio.get<Map<String, dynamic>>('/secure'),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
    expect(refreshCount, 1);
  });

  test('刷新返回失败但并发路径已更新令牌时直接重放成功', () async {
    var accessToken = 'expired-token';
    final adapter = _ReplayAdapter();
    final client = ApiClient(
      const AppEnvironment(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        wsBaseUrl: 'ws://localhost:8080/ws',
      ),
      readAccessToken: () => accessToken,
      refreshSession: () async {
        accessToken = 'fresh-token';
        return false;
      },
      httpClientAdapter: adapter,
    );

    final response = await client.dio.get<Map<String, dynamic>>('/secure');
    expect(response.data?['code'], 200);
  });

  test('刷新被拒且本地无令牌后停止重复刷新，重新带令牌即恢复', () async {
    String? accessToken;
    var refreshCount = 0;
    final adapter = _ReplayAdapter();
    final client = ApiClient(
      const AppEnvironment(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        wsBaseUrl: 'ws://localhost:8080/ws',
      ),
      readAccessToken: () => accessToken,
      refreshSession: () async {
        refreshCount++;
        return false;
      },
      httpClientAdapter: adapter,
    );

    await expectLater(
      client.dio.get<Map<String, dynamic>>('/secure'),
      throwsA(isA<DioException>()),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      // 会话已被判定失效后，后续 401 与首个失败请求一样抛异常，
      // 不能再以普通 Response 返回而让上层误判成功。
      await expectLater(
        client.dio.get<Map<String, dynamic>>('/secure'),
        throwsA(isA<DioException>()),
      );
    }
    expect(refreshCount, 1);

    accessToken = 'stale-token';
    await expectLater(
      client.dio.get<Map<String, dynamic>>('/secure'),
      throwsA(isA<DioException>()),
    );
    expect(refreshCount, 2);
  });
}

class _ReplayAdapter implements HttpClientAdapter {
  int secureRequestCount = 0;
  int forbiddenRequestCount = 0;
  int binaryRequestCount = 0;
  String? externalAuthorization;
  final claimAuthorizationHeaders = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.host == 'storage.example') {
      externalAuthorization = options.headers['Authorization']?.toString();
      return ResponseBody.fromString('expired signature', 401);
    }
    if (options.path.endsWith('/claims')) {
      claimAuthorizationHeaders.add(
        options.headers['Authorization']?.toString() ?? '',
      );
      if (options.headers['Authorization'] == 'Bearer fresh-claims-token') {
        return ResponseBody.fromString(
          '{"code":200,"message":"success","data":{"ok":true}}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json; charset=utf-8'],
          },
        );
      }
      return ResponseBody.fromString(
        '{"code":403,"message":"令牌声明过期","data":null}',
        403,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      );
    }
    if (options.path.endsWith('/forbidden')) {
      forbiddenRequestCount++;
      return ResponseBody.fromString(
        '{"code":403,"message":"无权限","data":null}',
        403,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      );
    }
    if (options.path.endsWith('/binary')) {
      binaryRequestCount++;
      final authorization = options.headers['Authorization']?.toString();
      if (authorization == 'Bearer fresh-token') {
        return ResponseBody.fromBytes([1, 2, 3], 200);
      }
      return ResponseBody.fromString(
        '{"code":401,"message":"未认证","data":null}',
        401,
      );
    }
    if (options.path.endsWith('/secure')) {
      secureRequestCount++;
      final authorization = options.headers['Authorization']?.toString();
      if (authorization == 'Bearer fresh-token') {
        return ResponseBody.fromString(
          '{"code":200,"message":"success","data":{"ok":true}}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json; charset=utf-8'],
          },
        );
      }
      return ResponseBody.fromString(
        '{"code":401,"message":"未认证","data":null}',
        401,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      );
    }
    return ResponseBody.fromString(
      '{"code":404,"message":"资源不存在","data":null}',
      404,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
