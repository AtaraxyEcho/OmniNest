import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/capability_skipped_error.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/network/capability_gate_interceptor.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CapabilityGateInterceptor', () {
    late CapabilityGateInterceptor interceptor;
    var permissions = <String>{};

    RequestOptions options({
      String method = 'PUT',
      required String path,
      Map<String, dynamic>? extra,
    }) {
      return RequestOptions(
        path: path,
        baseUrl: 'http://localhost:8080/api/v1',
        method: method,
        extra: extra ?? <String, dynamic>{},
      );
    }

    setUp(() {
      permissions = <String>{};
      interceptor = CapabilityGateInterceptor(
        readPermissions: () => permissions,
      );
    });

    test('autoSkip 路径无权限：reject 携带 CapabilitySkippedError', () {
      final handler = _TestRequestHandler();
      interceptor.onRequest(options(path: '/music/progress'), handler);
      expect(handler.rejectCount, 1);
      expect(handler.nextCount, 0);
      final error = handler.lastError!;
      expect(error.type, DioExceptionType.unknown);
      expect(error.error, isA<CapabilitySkippedError>());
      expect(
        (error.error! as CapabilitySkippedError).permission,
        activityWritePermission,
      );
    });

    test('autoSkip 路径有权限：放行', () {
      permissions = {activityWritePermission};
      final handler = _TestRequestHandler();
      interceptor.onRequest(options(path: '/music/progress'), handler);
      expect(handler.nextCount, 1);
      expect(handler.rejectCount, 0);
    });

    test('strict 路径（收藏）无权限：拦截器放行，交由 API 预检', () {
      final handler = _TestRequestHandler();
      interceptor.onRequest(
        options(method: 'POST', path: '/music/tracks/id-1/favorite'),
        handler,
      );
      expect(handler.nextCount, 1);
      expect(handler.rejectCount, 0);
    });

    test('偏好路径按 preference:write 判定', () {
      final handler = _TestRequestHandler();
      interceptor.onRequest(
        options(method: 'PATCH', path: '/preferences/reader'),
        handler,
      );
      expect(handler.rejectCount, 1);
      expect(
        (handler.lastError!.error! as CapabilitySkippedError).permission,
        preferenceWritePermission,
      );

      permissions = {preferenceWritePermission};
      final allowed = _TestRequestHandler();
      interceptor.onRequest(
        options(method: 'PATCH', path: '/preferences/reader'),
        allowed,
      );
      expect(allowed.nextCount, 1);
    });

    test('未标记但命中 autoSkip 路径表：默认按 autoSkip（防漏标回归 403）', () {
      final handler = _TestRequestHandler();
      interceptor.onRequest(
        options(method: 'POST', path: '/weather/location'),
        handler,
      );
      expect(handler.rejectCount, 1);
    });

    test('显式 strict 标记优先于路径表推断', () {
      final handler = _TestRequestHandler();
      interceptor.onRequest(
        options(
          path: '/music/progress',
          extra: {capabilityPolicyKey: CapabilityWritePolicy.strict},
        ),
        handler,
      );
      expect(handler.nextCount, 1);
      expect(handler.rejectCount, 0);
    });

    test('读请求不受门控影响', () {
      final handler = _TestRequestHandler();
      interceptor.onRequest(
        options(method: 'GET', path: '/music/progress'),
        handler,
      );
      expect(handler.nextCount, 1);
    });

    test('锚定收紧：/notes 子串路径不误伤无关端点', () {
      final handler = _TestRequestHandler();
      interceptor.onRequest(
        options(method: 'POST', path: '/reader/items/id-1/notes-export'),
        handler,
      );
      expect(handler.nextCount, 1);
      expect(handler.rejectCount, 0);
    });
  });

  group('ApiClient 能力预检', () {
    test('未注入读取器时视为有权限，保持既有测试行为', () {
      final client = ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
      );
      expect(client.hasPermission(activityWritePermission), isTrue);
      expect(
        () => client.requirePermission(activityWritePermission),
        returnsNormally,
      );
    });

    test('requirePermission 无权限时抛 FORBIDDEN', () {
      final client = ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        readPermissions: () => const <String>{},
      );
      expect(
        () => client.requirePermission(activityWritePermission),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            'FORBIDDEN',
          ),
        ),
      );
    });
  });

  group('MovieApi 写策略', () {
    test('updateProgress 无能力时静默 no-op，不发网络', () async {
      final adapter = _CountingAdapter();
      final client = ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        readPermissions: () => const <String>{},
        httpClientAdapter: adapter,
      );
      final api = MovieApi(client);

      await api.updateProgress(
        videoItemId: 'item-1',
        positionSeconds: 30,
        durationSeconds: 120,
      );

      expect(adapter.requestCount, 0);
    });

    test('favorite 无能力时抛 FORBIDDEN，禁止假成功', () async {
      final adapter = _CountingAdapter();
      final client = ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        readPermissions: () => const <String>{},
        httpClientAdapter: adapter,
      );
      final api = MovieApi(client);

      await expectLater(
        api.favorite(videoItemId: 'item-1', favorite: true),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            'FORBIDDEN',
          ),
        ),
      );
      expect(adapter.requestCount, 0);
    });

    test('有能力时正常发起网络请求', () async {
      final adapter = _CountingAdapter();
      final client = ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        readPermissions: () => {activityWritePermission},
        httpClientAdapter: adapter,
      );
      final api = MovieApi(client);

      await api.updateProgress(
        videoItemId: 'item-1',
        positionSeconds: 30,
        durationSeconds: 120,
      );

      expect(adapter.requestCount, 1);
    });
  });
}

/// RequestInterceptorHandler 替身：记录 next / reject 调用。
class _TestRequestHandler extends RequestInterceptorHandler {
  int nextCount = 0;
  int rejectCount = 0;
  DioException? lastError;

  @override
  void next(RequestOptions options) {
    nextCount++;
  }

  @override
  void reject(DioException error, [bool callFollowingErrorInterceptor = true]) {
    rejectCount++;
    lastError = error;
  }
}

/// 计数适配器：成功响应固定 code 200 空数据。
class _CountingAdapter implements HttpClientAdapter {
  int requestCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    final body = '{"code":200,"message":"ok","data":{}}';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}
