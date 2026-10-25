import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/video/data/movie_api.dart';

void main() {
  test('delete item sends delete request to video endpoint', () async {
    final adapter = _CapturingHttpClientAdapter();
    final api = MovieApi(_apiClient(adapter));

    await api.deleteItem('video-1');

    expect(adapter.lastMethod, 'DELETE');
    expect(adapter.lastPath, '/video/items/video-1');
  });

  test(
    'completeUploadSession reads fileNodeId from the shared upload contract',
    () async {
      final adapter = _JsonHttpClientAdapter({
        'code': 200,
        'message': 'success',
        'data': {
          'uploadId': 'upload-1',
          'status': 'COMPLETED',
          'taskId': null,
          'fileNodeId': 'file-node-1',
        },
      });
      final api = MovieApi(_apiClient(adapter));

      final result = await api.completeUploadSession(uploadId: 'upload-1');

      expect(result.isScanning, isFalse);
      expect(result.fileNodeId, 'file-node-1');
    },
  );

  test(
    'completeUploadSession keeps scanning task id when promotion is pending',
    () async {
      final adapter = _JsonHttpClientAdapter({
        'code': 200,
        'message': 'success',
        'data': {
          'uploadId': 'upload-1',
          'status': 'SCANNING',
          'taskId': 'task-1',
          'fileNodeId': null,
        },
      });
      final api = MovieApi(_apiClient(adapter));

      final result = await api.completeUploadSession(uploadId: 'upload-1');

      expect(result.isScanning, isTrue);
      expect(result.taskId, 'task-1');
      expect(result.fileNodeId, isNull);
    },
  );

  test(
    'subtitle loading decodes GBK and marks external URL as no-auth',
    () async {
      final adapter = _BytesHttpClientAdapter(
        Uint8List.fromList(<int>[
          0xD6,
          0xD0,
          0xCE,
          0xC4,
          0xD7,
          0xD6,
          0xC4,
          0xBB,
        ]),
      );
      final api = MovieApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          readAccessToken: () => 'secret-jwt',
          httpClientAdapter: adapter,
        ),
      );

      final content = await api.loadSubtitle(
        'https://storage.example/subtitle.srt',
      );

      expect(content, '中文字幕');
      expect(adapter.lastHeaders?['Authorization'], isNull);
      expect(adapter.lastSkipAuthorization, isTrue);
    },
  );

  test('subtitle loading truncates oversized responses to two MiB', () async {
    final adapter = _TextHttpClientAdapter(
      List<String>.filled(2 * 1024 * 1024 + 32, 'a').join(),
    );
    final api = MovieApi(_apiClient(adapter));

    final content = await api.loadSubtitle('http://minio/subtitle.vtt');

    expect(adapter.lastPath, 'http://minio/subtitle.vtt');
    expect(adapter.lastHeaders?['Range'], 'bytes=0-2097151');
    expect(content.length, 2 * 1024 * 1024);
  });

  test('detail resolves relative asset urls to absolute api origin', () async {
    final adapter = _JsonHttpClientAdapter({
      'code': 200,
      'message': 'success',
      'data': {
        'id': 'video-1',
        'fileNodeId': 'file-1',
        'mediaType': 'MOVIE',
        'title': '影片',
        'metadataStatus': 'MATCHED',
        'nfoStatus': 'DISABLED',
        'updatedAt': null,
        'metadata': <String, dynamic>{},
        'posterUrl': '/api/v1/public/video/items/video-1/assets/file-1?token=t',
        'backdropUrl':
            '/api/v1/public/video/items/video-1/assets/file-2?token=t',
        'assets': {
          'POSTER': {
            'assetType': 'POSTER',
            'primary': true,
            'metadata': <String, dynamic>{},
            'url': '/api/v1/public/video/items/video-1/assets/file-3?token=t',
          },
        },
        'castMembers': [
          {
            'name': '张三',
            'character': '角色',
            'profilePath': '/abc.jpg',
            'order': 0,
          },
        ],
        'crewMembers': <Map<String, dynamic>>[],
      },
    });
    final api = MovieApi(_apiClient(adapter));

    final item = await api.detail('video-1');

    expect(
      item.posterImageUrl,
      startsWith('http://localhost:8080/api/v1/public/video/items/video-1'),
    );
    expect(
      item.backdropImageUrl,
      startsWith('http://localhost:8080/api/v1/public/video/items/video-1'),
    );
    expect(
      item.assets['POSTER']?.url,
      startsWith('http://localhost:8080/api/v1/public/video/items/video-1'),
    );
    // TMDB 相对头像路径应拼接 TMDB 图床，而不是 API origin。
    expect(
      item.castMembers.first.profilePath,
      'https://image.tmdb.org/t/p/w185/abc.jpg',
    );
  });

  test('detail keeps absolute asset urls unchanged', () async {
    final adapter = _JsonHttpClientAdapter({
      'code': 200,
      'message': 'success',
      'data': {
        'id': 'video-1',
        'fileNodeId': 'file-1',
        'mediaType': 'MOVIE',
        'title': '影片',
        'metadataStatus': 'MATCHED',
        'nfoStatus': 'DISABLED',
        'updatedAt': null,
        'metadata': <String, dynamic>{},
        'posterUrl': 'http://localhost:9000/media/poster.jpg',
        'castMembers': <Map<String, dynamic>>[],
        'crewMembers': <Map<String, dynamic>>[],
      },
    });
    final api = MovieApi(_apiClient(adapter));

    final item = await api.detail('video-1');

    expect(item.posterImageUrl, 'http://localhost:9000/media/poster.jpg');
  });
}

class _JsonHttpClientAdapter implements HttpClientAdapter {
  _JsonHttpClientAdapter(this.body);

  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
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
  String? lastMethod;
  String? lastPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastMethod = options.method;
    lastPath = options.path;
    return ResponseBody.fromString(
      jsonEncode({'code': 200, 'message': 'success', 'data': {}}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _BytesHttpClientAdapter implements HttpClientAdapter {
  _BytesHttpClientAdapter(this.content);

  final Uint8List content;
  Map<String, dynamic>? lastHeaders;
  bool? lastSkipAuthorization;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastHeaders = Map<String, dynamic>.from(options.headers);
    lastSkipAuthorization =
        options.extra[ApiClient.skipAuthorizationKey] == true;
    return ResponseBody.fromBytes(
      content,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _TextHttpClientAdapter implements HttpClientAdapter {
  _TextHttpClientAdapter(this.content);

  final String content;
  String? lastPath;
  Map<String, dynamic>? lastHeaders;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastPath = options.path;
    lastHeaders = Map<String, dynamic>.from(options.headers);
    return ResponseBody.fromString(
      content,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
