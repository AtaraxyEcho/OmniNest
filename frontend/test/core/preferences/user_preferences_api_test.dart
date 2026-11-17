import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/preferences/user_preferences_api.dart';

void main() {
  test('patch sends versioned top-level mutation', () async {
    final adapter = _CapturingAdapter(
      responseBody: {
        'code': 200,
        'message': 'success',
        'data': {
          'scope': 'appearance.v1',
          'preferences': {'themeMode': 'dark'},
          'createdAt': '2026-07-15T00:00:00Z',
          'updatedAt': '2026-07-15T01:00:00Z',
          'version': 4,
        },
      },
    );
    final api = UserPreferencesApi(_apiClient(adapter));

    final snapshot = await api.patch(
      scope: 'appearance.v1',
      baseVersion: 3,
      changes: {'themeMode': 'dark'},
      removeKeys: {'legacy'},
    );

    expect(adapter.lastMethod, 'PATCH');
    expect(adapter.lastPath, '/preferences/appearance.v1');
    expect(adapter.lastData, {
      'baseVersion': 3,
      'changes': {'themeMode': 'dark'},
      'removeKeys': ['legacy'],
    });
    expect(snapshot.version, 4);
    expect(snapshot.preferences['themeMode'], 'dark');
  });

  test('getSnapshot preserves audit metadata', () async {
    final adapter = _CapturingAdapter(
      responseBody: {
        'code': 200,
        'message': 'success',
        'data': {
          'scope': 'locale.v1',
          'preferences': {'language': 'en'},
          'createdAt': '2026-07-15T00:00:00Z',
          'updatedAt': '2026-07-15T01:00:00Z',
          'version': 2,
        },
      },
    );

    final snapshot = await UserPreferencesApi(
      _apiClient(adapter),
    ).getSnapshot('locale.v1');

    expect(snapshot.scope, 'locale.v1');
    expect(snapshot.version, 2);
    expect(snapshot.updatedAt, DateTime.parse('2026-07-15T01:00:00Z'));
  });

  test('非信封响应直接失败，不把本地偏好覆盖成空快照', () async {
    final adapter = _CapturingAdapter(responseBody: const <String, dynamic>{});

    await expectLater(
      UserPreferencesApi(_apiClient(adapter)).getSnapshot('locale.v1'),
      throwsA(isA<AppException>()),
    );
  });

  test('HTTP 200 但信封 code 非 200 时按失败处理', () async {
    final adapter = _CapturingAdapter(
      responseBody: const <String, dynamic>{
        'code': 500,
        'errorName': 'INTERNAL_ERROR',
        'message': '服务异常',
      },
    );

    await expectLater(
      UserPreferencesApi(_apiClient(adapter)).getSnapshot('locale.v1'),
      throwsA(
        isA<AppException>().having(
          (error) => error.code,
          'code',
          'INTERNAL_ERROR',
        ),
      ),
    );
  });
}

ApiClient _apiClient(HttpClientAdapter adapter) {
  return ApiClient(
    const AppEnvironment(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      wsBaseUrl: 'ws://localhost:8080/ws',
    ),
    httpClientAdapter: adapter,
  );
}

class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter({required this.responseBody});

  final Map<String, dynamic> responseBody;
  String? lastMethod;
  String? lastPath;
  Object? lastData;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastMethod = options.method;
    lastPath = options.path;
    lastData = options.data;
    return ResponseBody.fromString(
      jsonEncode(responseBody),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
