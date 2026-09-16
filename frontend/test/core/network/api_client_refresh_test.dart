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
      clearSession: () async {},
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
      clearSession: () async {},
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

  test('403 刷新会话并携带新令牌重试一次成功', () async {
    var accessToken = 'stale-claims-token';
    var refreshCount = 0;
    var clearCount = 0;
    final adapter = _ReplayAdapter();
    final client = ApiClient(
      const AppEnvironment(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        wsBaseUrl: 'ws://localhost:8080/ws',
      ),
      readAccessToken: () => accessToken,
      refreshSession: () async {
        refreshCount++;
        accessToken = 'fresh-claims-token';
        return true;
      },
      clearSession: () async {
        clearCount++;
      },
      httpClientAdapter: adapter,
    );

    final response = await client.dio.get<Map<String, dynamic>>('/claims');

    expect(refreshCount, 1);
    expect(clearCount, 0);
    expect(response.data?['code'], 200);
    expect(adapter.claimAuthorizationHeaders, [
      'Bearer stale-claims-token',
      'Bearer fresh-claims-token',
    ]);
  });

  test('403 真实权限拒绝重试后原样上抛且不清除会话', () async {
    var accessToken = 'stale-claims-token';
    var refreshCount = 0;
    var clearCount = 0;
    final adapter = _ReplayAdapter();
    final client = ApiClient(
      const AppEnvironment(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        wsBaseUrl: 'ws://localhost:8080/ws',
      ),
      readAccessToken: () => accessToken,
      refreshSession: () async {
        refreshCount++;
        accessToken = 'fresh-claims-token';
        return true;
      },
      clearSession: () async {
        clearCount++;
      },
      httpClientAdapter: adapter,
    );

    final response = await client.dio.get<Map<String, dynamic>>('/forbidden');

    expect(response.statusCode, 403);
    expect(refreshCount, 1);
    expect(clearCount, 0);
    expect(adapter.forbiddenRequestCount, 2);
  });
}

class _ReplayAdapter implements HttpClientAdapter {
  int secureRequestCount = 0;
  int forbiddenRequestCount = 0;
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
