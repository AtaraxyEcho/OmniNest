import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/tasks/data/task_api.dart';

void main() {
  group('TaskApi', () {
    test('list sends GET to /tasks with default pagination', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'items': [
              {
                'id': 'task-1',
                'taskType': 'FILE_INDEX',
                'status': 'COMPLETED',
                'retryCount': 0,
                'maxRetries': 3,
                'createdAt': '2025-06-01T10:00:00Z',
              },
            ],
          },
        },
      );
      final api = TaskApi(_apiClient(adapter));

      final result = await api.list();

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/tasks');
      expect(adapter.lastQueryParams, {'page': 0, 'size': 20});
      expect(result, hasLength(1));
      expect(result.first.id, 'task-1');
      expect(result.first.taskType, 'FILE_INDEX');
      expect(result.first.status, 'COMPLETED');
    });

    test('list sends custom page and size parameters', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {'items': <Map<String, dynamic>>[]},
        },
      );
      final api = TaskApi(_apiClient(adapter));

      await api.list(page: 2, size: 10);

      expect(adapter.lastQueryParams, {'page': 2, 'size': 10});
    });

    test('list returns empty list when data is null', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {'code': 200, 'message': 'success', 'data': null},
      );
      final api = TaskApi(_apiClient(adapter));

      final result = await api.list();

      expect(result, isEmpty);
    });

    test('list returns empty list when items key missing', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {'code': 200, 'message': 'success', 'data': <String, dynamic>{}},
      );
      final api = TaskApi(_apiClient(adapter));

      final result = await api.list();

      expect(result, isEmpty);
    });

    test('list parses failed task with error message', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'items': [
              {
                'id': 'task-fail',
                'taskType': 'MEDIA_SCRAPE',
                'status': 'FAILED',
                'retryCount': 2,
                'maxRetries': 3,
                'errorMessage': 'Network timeout',
                'createdAt': '2025-06-02T14:30:00Z',
              },
            ],
          },
        },
      );
      final api = TaskApi(_apiClient(adapter));

      final result = await api.list();

      expect(result, hasLength(1));
      expect(result.first.status, 'FAILED');
      expect(result.first.errorMessage, 'Network timeout');
      expect(result.first.retryCount, 2);
      expect(result.first.canRetry, isTrue);
    });

    test('retry sends POST to /tasks/:id/retry for owned tasks', () async {
      final adapter = _CapturingHttpClientAdapter();
      final api = TaskApi(_apiClient(adapter));

      await api.retry('task-fail');

      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastPath, '/tasks/task-fail/retry');
    });
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

class _CapturingHttpClientAdapter implements HttpClientAdapter {
  _CapturingHttpClientAdapter({
    this.body = const {'code': 200, 'message': 'success', 'data': {}},
  });

  final Map<String, dynamic> body;
  String? lastMethod;
  String? lastPath;
  Object? lastData;
  Map<String, dynamic>? lastQueryParams;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastMethod = options.method;
    lastPath = options.path;
    lastData = options.data;
    lastQueryParams =
        options.queryParameters.isEmpty
            ? null
            : Map<String, dynamic>.from(options.queryParameters);
    return ResponseBody.fromString(
      jsonEncode(body),
      (body['code'] as num?)?.toInt() ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
