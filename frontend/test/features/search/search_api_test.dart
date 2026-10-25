import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/search/data/search_api.dart';

void main() {
  group('SearchApi', () {
    test('search sends GET to /search with query', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': [
            {
              'id': 'result-1',
              'title': 'Dart Programming',
              'subtitle': 'A comprehensive guide',
              'type': 'book',
            },
          ],
        },
      );
      final api = SearchApi(_apiClient(adapter));

      final result = await api.search('dart');

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/search');
      expect(adapter.lastQueryParams, {'q': 'dart', 'limit': 20});
      expect(result, hasLength(1));
      expect(result.first.title, 'Dart Programming');
      expect(result.first.type, 'book');
    });

    test('search uses custom limit', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': <Map<String, dynamic>>[],
        },
      );
      final api = SearchApi(_apiClient(adapter));

      await api.search('flutter', limit: 5);

      expect(adapter.lastQueryParams, {'q': 'flutter', 'limit': 5});
    });

    test('search maps the file-index shape to file results', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': [
            {
              'fileId': 'file-1',
              'title': '季度报告.pdf',
              'snippet': '…季度财务…',
              'score': 0.92,
            },
          ],
        },
      );
      final api = SearchApi(_apiClient(adapter));

      final result = await api.search('季度');

      expect(result, hasLength(1));
      expect(result.single.id, 'file-1');
      expect(result.single.type, 'file');
      expect(result.single.title, '季度报告.pdf');
      expect(result.single.subtitle, '…季度财务…');
    });

    test('search returns empty list when data is null', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {'code': 200, 'message': 'success', 'data': null},
      );
      final api = SearchApi(_apiClient(adapter));

      final result = await api.search('nothing');

      expect(result, isEmpty);
    });

    test('search returns empty list when data key missing', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {'code': 200, 'message': 'success'},
      );
      final api = SearchApi(_apiClient(adapter));

      final result = await api.search('empty');

      expect(result, isEmpty);
    });

    test('search parses multiple results', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': [
            {
              'id': 'r-1',
              'title': 'Result One',
              'subtitle': 'First',
              'type': 'photo',
              'thumbnailUrl': 'https://example.com/1.jpg',
            },
            {
              'id': 'r-2',
              'title': 'Result Two',
              'subtitle': 'Second',
              'type': 'video',
            },
          ],
        },
      );
      final api = SearchApi(_apiClient(adapter));

      final result = await api.search('test');

      expect(result, hasLength(2));
      expect(result.first.thumbnailUrl, 'https://example.com/1.jpg');
      expect(result.last.thumbnailUrl, isNull);
      expect(result.first.type, 'photo');
      expect(result.last.type, 'video');
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
