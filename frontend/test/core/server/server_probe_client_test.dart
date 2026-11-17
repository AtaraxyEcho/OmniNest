import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/server/server_probe_client.dart';
import 'package:omninest/core/server/server_config.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.responder});

  final Future<Object> Function(RequestOptions options)? responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final result = await responder!(options);
    if (result is ResponseBody) {
      return result;
    }
    throw result as DioException;
  }

  @override
  void close({bool force = false}) {}
}

ServerConfig _config() => ServerConfig.tryParse('https://nest.example.com')!;

void main() {
  test('探活请求规范化基址下的 /setup/status', () async {
    late String capturedPath;
    final client = ServerProbeClient(
      dio:
          Dio()
            ..httpClientAdapter = _StubAdapter(
              responder: (options) async {
                capturedPath = options.uri.toString();
                return ResponseBody.fromString(
                  jsonEncode({
                    'code': 0,
                    'data': {'setupRequired': false},
                  }),
                  200,
                );
              },
            ),
    );

    final result = await client.probe(_config());

    expect(result.isSuccess, isTrue);
    expect(result.setupRequired, isFalse);
    expect(capturedPath, 'https://nest.example.com/api/v1/setup/status');
  });

  test('安装未完成的服务器返回 setupRequired', () async {
    final client = ServerProbeClient(
      dio:
          Dio()
            ..httpClientAdapter = _StubAdapter(
              responder: (options) async {
                return ResponseBody.fromString(
                  jsonEncode({
                    'code': 0,
                    'data': {'setupRequired': true},
                  }),
                  200,
                );
              },
            ),
    );

    final result = await client.probe(_config());

    expect(result.isSuccess, isTrue);
    expect(result.setupRequired, isTrue);
  });

  test('2xx 但响应不是 OmniNest 信封结构判定 notOmniNest', () async {
    final client = ServerProbeClient(
      dio:
          Dio()
            ..httpClientAdapter = _StubAdapter(
              responder: (options) async {
                return ResponseBody.fromString('<html>hi</html>', 200);
              },
            ),
    );

    final result = await client.probe(_config());

    expect(result.failure, ServerProbeFailure.notOmniNest);
  });

  test('2xx 但 data 缺少 setupRequired 布尔字段判定 notOmniNest', () async {
    final client = ServerProbeClient(
      dio:
          Dio()
            ..httpClientAdapter = _StubAdapter(
              responder: (options) async {
                return ResponseBody.fromString(
                  jsonEncode({'code': 0, 'data': <String, dynamic>{}}),
                  200,
                );
              },
            ),
    );

    final result = await client.probe(_config());

    expect(result.failure, ServerProbeFailure.notOmniNest);
  });

  test('4xx 判定 rejected', () async {
    final client = ServerProbeClient(
      dio:
          Dio()
            ..httpClientAdapter = _StubAdapter(
              responder: (options) async {
                return ResponseBody.fromString('not found', 404);
              },
            ),
    );

    final result = await client.probe(_config());

    expect(result.failure, ServerProbeFailure.rejected);
  });

  test('连接失败判定 unreachable', () async {
    final client = ServerProbeClient(
      dio:
          Dio()
            ..httpClientAdapter = _StubAdapter(
              responder: (options) async {
                throw DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                );
              },
            ),
    );

    final result = await client.probe(_config());

    expect(result.failure, ServerProbeFailure.unreachable);
  });

  test('超时判定 timeout', () async {
    final client = ServerProbeClient(
      dio:
          Dio()
            ..httpClientAdapter = _StubAdapter(
              responder: (options) async {
                throw DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionTimeout,
                );
              },
            ),
    );

    final result = await client.probe(_config());

    expect(result.failure, ServerProbeFailure.timeout);
  });

  test('取消请求原样抛出由调用方处理', () async {
    final cancelToken = CancelToken();
    final client = ServerProbeClient(
      dio:
          Dio()
            ..httpClientAdapter = _StubAdapter(
              responder: (options) async {
                cancelToken.cancel();
                throw DioException(
                  requestOptions: options,
                  type: DioExceptionType.cancel,
                  error: cancelToken,
                );
              },
            ),
    );

    await expectLater(
      client.probe(_config(), cancelToken: cancelToken),
      throwsA(isA<DioException>()),
    );
  });
}
