import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/network/retry_interceptor.dart';

void main() {
  late Dio dio;
  late RetryInterceptor interceptor;

  setUp(() {
    interceptor = RetryInterceptor(maxRetries: 2);
    dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
    dio.interceptors.add(interceptor);
  });

  RequestOptions getOptions({
    String method = 'GET',
    Map<String, dynamic>? extra,
  }) {
    return RequestOptions(
      path: '/test',
      baseUrl: 'https://example.com',
      method: method,
      extra: extra ?? <String, dynamic>{},
    );
  }

  DioException buildException({
    required DioExceptionType type,
    int? statusCode,
    String method = 'GET',
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
  }) {
    final options = getOptions(method: method, extra: extra);
    options.headers.addAll(headers ?? const <String, dynamic>{});
    Response<dynamic>? response;
    if (statusCode != null) {
      response = Response(statusCode: statusCode, requestOptions: options);
    }
    return DioException(
      type: type,
      requestOptions: options,
      response: response,
    );
  }

  group('RetryInterceptor', () {
    test('does not retry on 400 Bad Request', () async {
      final handler = _TestErrorHandler();
      final exception = buildException(
        type: DioExceptionType.badResponse,
        statusCode: 400,
      );

      await interceptor.onError(exception, handler);

      expect(handler.nextCount, 1);
      expect(handler.resolveCount, 0);
      expect(handler.lastError?.response?.statusCode, 400);
    });

    test('retries on 503 Service Unavailable up to maxRetries', () async {
      final handler = _TestErrorHandler();
      final exception = buildException(
        type: DioExceptionType.badResponse,
        statusCode: 503,
      );

      // 第一次调用：应该重试（retryCount 从 0 开始）
      await interceptor.onError(exception, handler);
      expect(handler.resolveCount + handler.nextCount, 1);

      // 模拟重试失败后再次调用拦截器
      final handler2 = _TestErrorHandler();
      exception.requestOptions.extra['retryCount'] = 1;
      await interceptor.onError(exception, handler2);
      // retryCount=1 < maxRetries=2，应该继续重试
      expect(handler2.resolveCount + handler2.nextCount, 1);

      // 达到 maxRetries 后不再重试
      final handler3 = _TestErrorHandler();
      exception.requestOptions.extra['retryCount'] = 2;
      await interceptor.onError(exception, handler3);
      expect(handler3.nextCount, 1);
      expect(handler3.resolveCount, 0);
    });

    test('retries on connection timeout', () async {
      final handler = _TestErrorHandler();
      final exception = buildException(
        type: DioExceptionType.connectionTimeout,
      );

      await interceptor.onError(exception, handler);

      // 连接超时应该触发重试，要么 resolve 要么 next
      expect(handler.resolveCount + handler.nextCount, 1);
    });

    test('does not exceed maxRetries', () async {
      final handler = _TestErrorHandler();
      final exception = buildException(
        type: DioExceptionType.connectionTimeout,
      );

      // 设置 retryCount 达到最大值
      exception.requestOptions.extra['retryCount'] = 2;

      await interceptor.onError(exception, handler);

      expect(handler.nextCount, 1);
      expect(handler.resolveCount, 0);
      expect(handler.lastError?.type, DioExceptionType.connectionTimeout);
    });

    test('does not retry POST on 500 (only on connection error)', () async {
      final handler = _TestErrorHandler();
      final exception = buildException(
        type: DioExceptionType.badResponse,
        statusCode: 500,
        method: 'POST',
      );

      await interceptor.onError(exception, handler);

      expect(handler.nextCount, 1);
      expect(handler.resolveCount, 0);
    });

    test(
      'does not retry POST on connection error without idempotency key',
      () async {
        final handler = _TestErrorHandler();
        final exception = buildException(
          type: DioExceptionType.connectionError,
          method: 'POST',
        );

        await interceptor.onError(exception, handler);

        expect(handler.nextCount, 1);
        expect(handler.resolveCount, 0);
        expect(exception.requestOptions.extra['retryCount'], isNull);
      },
    );

    test('retries POST with idempotency key on connection error', () async {
      final handler = _TestErrorHandler();
      final exception = buildException(
        type: DioExceptionType.connectionError,
        method: 'POST',
        headers: {'Idempotency-Key': 'request-1'},
      );

      await interceptor.onError(exception, handler);

      expect(handler.resolveCount + handler.nextCount, 1);
      expect(exception.requestOptions.extra['retryCount'], 1);
    });

    test('retries on 408 Request Timeout for GET', () async {
      final handler = _TestErrorHandler();
      final exception = buildException(
        type: DioExceptionType.badResponse,
        statusCode: 408,
      );

      await interceptor.onError(exception, handler);

      expect(handler.resolveCount + handler.nextCount, 1);
    });

    test('retries on receive timeout', () async {
      final handler = _TestErrorHandler();
      final exception = buildException(type: DioExceptionType.receiveTimeout);

      await interceptor.onError(exception, handler);

      expect(handler.resolveCount + handler.nextCount, 1);
    });

    test(
      'does not retry receive timeout for writes without idempotency key',
      () async {
        final handler = _TestErrorHandler();
        final exception = buildException(
          type: DioExceptionType.receiveTimeout,
          method: 'PUT',
        );

        await interceptor.onError(exception, handler);

        // 30 秒读超时重试两次会让写操作阻塞 90 秒以上。
        expect(handler.nextCount, 1);
        expect(handler.resolveCount, 0);
        expect(exception.requestOptions.extra['retryCount'], isNull);
      },
    );

    test(
      'stops retrying when the request is cancelled during backoff',
      () async {
        final fastInterceptor = RetryInterceptor(
          maxRetries: 2,
          baseDelay: Duration.zero,
        );
        final handler = _TestErrorHandler();
        final cancelToken = CancelToken();
        final options = getOptions();
        options.cancelToken = cancelToken;
        final exception = DioException(
          type: DioExceptionType.connectionTimeout,
          requestOptions: options,
        );
        cancelToken.cancel();

        await fastInterceptor.onError(exception, handler);

        expect(handler.nextCount, 1);
        expect(handler.resolveCount, 0);
        expect(options.extra['retryCount'], isNull);
      },
    );

    test(
      'does not retry an idempotent request with a single-subscription stream body',
      () async {
        final handler = _TestErrorHandler();
        final options = RequestOptions(
          path: '/test',
          baseUrl: 'https://example.com',
          method: 'PUT',
          data: Stream<List<int>>.fromIterable([
            <int>[1, 2],
          ]),
        );
        final exception = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: options,
          response: Response(statusCode: 503, requestOptions: options),
        );

        await interceptor.onError(exception, handler);

        // 单次订阅流重放会抛 StateError，必须按不可重试处理。
        expect(handler.nextCount, 1);
        expect(handler.resolveCount, 0);
      },
    );

    test('does not retry POST on 429', () async {
      final handler = _TestErrorHandler();
      final exception = buildException(
        type: DioExceptionType.badResponse,
        statusCode: 429,
        method: 'POST',
      );

      await interceptor.onError(exception, handler);

      expect(handler.nextCount, 1);
      expect(handler.resolveCount, 0);
    });

    test('stores retry count in requestOptions.extra', () async {
      final handler = _TestErrorHandler();
      final exception = buildException(
        type: DioExceptionType.connectionTimeout,
      );

      expect(exception.requestOptions.extra['retryCount'], isNull);

      await interceptor.onError(exception, handler);

      expect(exception.requestOptions.extra['retryCount'], 1);
    });

    test(
      'skips 5xx retry when the request opts out of server-error retry',
      () async {
        final handler = _TestErrorHandler();
        final exception = buildException(
          type: DioExceptionType.badResponse,
          statusCode: 500,
          method: 'DELETE',
          extra: <String, dynamic>{skipServerErrorRetryKey: true},
        );

        await interceptor.onError(exception, handler);

        // 用户已确认的一次性动作：服务端 5xx 重试注定失败，只会把等待时间
        // 放大成退避之和（1s + 2s），因此这里必须直接失败而不是重试。
        expect(handler.nextCount, 1);
        expect(handler.resolveCount, 0);
        expect(exception.requestOptions.extra['retryCount'], isNull);
      },
    );

    test('opt-out still retries network level failures', () async {
      final handler = _TestErrorHandler();
      final exception = buildException(
        type: DioExceptionType.connectionTimeout,
        method: 'DELETE',
        extra: <String, dynamic>{skipServerErrorRetryKey: true},
      );

      await interceptor.onError(exception, handler);

      // 连接层失败与业务语义无关：仍然重试。
      expect(handler.resolveCount + handler.nextCount, 1);
      expect(exception.requestOptions.extra['retryCount'], 1);
    });

    test('does not retry 429 delivered as a normal response', () async {
      final retryDio = Dio(
        BaseOptions(
          baseUrl: 'https://example.com',
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final adapter = _QueueHttpAdapter([
        ResponseBody.fromString(
          '{"code":429}',
          429,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
        ResponseBody.fromString(
          '{"code":200}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      ]);
      retryDio.httpClientAdapter = adapter;
      final retry = RetryInterceptor(maxRetries: 1, baseDelay: Duration.zero);
      retry.setDio(retryDio);
      retryDio.interceptors.add(retry);

      final response = await retryDio.get<dynamic>('/test');

      // 限流窗口按分钟级重置，短退避重发既拿不到配额还会继续消耗计数，
      // 因此 429 必须直接返回给调用方，不得自动重试。
      expect(response.statusCode, 429);
      expect(adapter.calls, 1);
    });
  });
}

/// 按顺序返回预置响应的 HTTP 适配器。
class _QueueHttpAdapter implements HttpClientAdapter {
  _QueueHttpAdapter(this.responses);

  final List<ResponseBody> responses;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = calls < responses.length ? calls : responses.length - 1;
    calls++;
    return responses[index];
  }

  @override
  void close({bool force = false}) {}
}

/// 用于测试的 ErrorInterceptorHandler 替身。
class _TestErrorHandler extends ErrorInterceptorHandler {
  int nextCount = 0;
  int resolveCount = 0;
  DioException? lastError;

  @override
  void next(DioException err) {
    nextCount++;
    lastError = err;
  }

  @override
  void resolve(Response<dynamic> response) {
    resolveCount++;
  }
}
