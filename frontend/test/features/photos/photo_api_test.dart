import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/photos/data/photo_api.dart';

void main() {
  group('PhotoApi', () {
    test('dashboard sends GET to /photos/dashboard', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'totalPhotos': 100,
            'totalAlbums': 5,
            'totalFavorites': 10,
            'recentPhotos': <Map<String, dynamic>>[],
            'favoritePhotos': <Map<String, dynamic>>[],
          },
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      final result = await api.dashboard();

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/photos/dashboard');
      expect(result.totalPhotos, 100);
      expect(result.totalAlbums, 5);
      expect(result.totalFavorites, 10);
    });

    test('listPhotos sends paged GET with optional query', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'items': [
              {
                'id': 'photo-1',
                'fileNodeId': 'file-1',
                'title': 'Sunset',
                'format': 'JPEG',
                'fileSize': 2048,
                'metadataStatus': 'READY',
                'favorite': false,
              },
            ],
            'page': 1,
            'size': 25,
            'totalElements': 30,
            'totalPages': 2,
          },
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      final result = await api.listPhotos(query: 'sunset', page: 1, size: 25);

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/photos/page');
      expect(adapter.lastQueryParams, {
        'page': 1,
        'size': 25,
        'sort': 'createdAt,desc',
        'query': 'sunset',
      });
      expect(result.items, hasLength(1));
      expect(result.items.first.id, 'photo-1');
      expect(result.items.first.title, 'Sunset');
      expect(result.hasMore, isFalse);
    });

    test('listPhotos omits query param when empty', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'items': <Map<String, dynamic>>[],
            'page': 0,
            'size': 50,
            'totalElements': 0,
            'totalPages': 0,
          },
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      await api.listPhotos();

      expect(adapter.lastQueryParams, {
        'page': 0,
        'size': 50,
        'sort': 'createdAt,desc',
      });
    });

    test('getPhoto sends GET to /photos/:id', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'id': 'photo-42',
            'fileNodeId': 'file-42',
            'title': 'Mountain View',
            'format': 'PNG',
            'fileSize': 4096,
            'metadataStatus': 'READY',
            'favorite': true,
            'width': 1920,
            'height': 1080,
          },
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      final result = await api.getPhoto('photo-42');

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/photos/photo-42');
      expect(result.id, 'photo-42');
      expect(result.title, 'Mountain View');
      expect(result.width, 1920);
      expect(result.height, 1080);
      expect(result.favorite, isTrue);
    });

    test('listFavorites sends GET to paged favorites endpoint', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'items': [
              {
                'id': 'photo-1',
                'fileNodeId': 'file-1',
                'title': 'Favorite Photo',
                'format': 'JPEG',
                'fileSize': 1024,
                'metadataStatus': 'READY',
                'favorite': true,
              },
            ],
            'page': 0,
            'size': 50,
            'totalElements': 1,
            'totalPages': 1,
          },
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      final result = await api.listFavorites();

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/photos/favorites/page');
      expect(result.items, hasLength(1));
      expect(result.items.first.favorite, isTrue);
    });

    test('listAlbums sends GET to /photos/albums', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': [
            {
              'id': 'album-1',
              'name': 'Vacation',
              'description': 'Summer trip',
              'photoCount': 25,
            },
            {
              'id': 'album-2',
              'name': 'Family',
              'description': '',
              'photoCount': 10,
            },
          ],
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      final result = await api.listAlbums();

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/photos/albums');
      expect(result, hasLength(2));
      expect(result.first.name, 'Vacation');
      expect(result.first.photoCount, 25);
    });

    test('movePhotoToTrash sends DELETE to /photos/:id', () async {
      final adapter = _CapturingHttpClientAdapter();
      final api = PhotoApi(_apiClient(adapter));

      await api.movePhotoToTrash('photo-99');

      expect(adapter.lastMethod, 'DELETE');
      expect(adapter.lastPath, '/photos/photo-99');
    });

    test('listTrash reads /photos/trash/page', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'items': [
              {
                'id': 'photo-1',
                'fileNodeId': 'file-1',
                'title': 'Trashed',
                'format': 'JPEG',
                'fileSize': 10,
                'metadataStatus': 'READY',
              },
            ],
            'page': 0,
            'size': 50,
            'totalElements': 1,
            'totalPages': 1,
          },
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      final page = await api.listTrash();

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/photos/trash/page');
      expect(page.totalElements, 1);
    });

    test('movePhotosToTrash submits one batch request', () async {
      final adapter = _CapturingHttpClientAdapter();
      final api = PhotoApi(_apiClient(adapter));

      await api.movePhotosToTrash(['photo-1', 'photo-2']);

      expect(adapter.lastMethod, 'DELETE');
      expect(adapter.lastPath, '/photos/batch');
      expect(adapter.lastData, {
        'photoIds': ['photo-1', 'photo-2'],
      });
    });

    test('addFavorite sends POST to /photos/:id/favorite', () async {
      final adapter = _CapturingHttpClientAdapter();
      final api = PhotoApi(_apiClient(adapter));

      await api.addFavorite('photo-7');

      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastPath, '/photos/photo-7/favorite');
    });

    test('removeFavorite sends DELETE to /photos/:id/favorite', () async {
      final adapter = _CapturingHttpClientAdapter();
      final api = PhotoApi(_apiClient(adapter));

      await api.removeFavorite('photo-7');

      expect(adapter.lastMethod, 'DELETE');
      expect(adapter.lastPath, '/photos/photo-7/favorite');
    });

    test('createAlbum posts name and description', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'id': 'album-new',
            'name': 'Weekend',
            'description': 'Weekend photos',
            'photoCount': 0,
          },
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      final result = await api.createAlbum(
        name: 'Weekend',
        description: 'Weekend photos',
      );

      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastPath, '/photos/albums');
      expect(adapter.lastData, {
        'name': 'Weekend',
        'description': 'Weekend photos',
      });
      expect(result.id, 'album-new');
    });

    test('getTimeline sends paged GET to /photos/timeline/page', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'items': [
              {
                'year': 2025,
                'month': 6,
                'photoCount': 15,
                'previewPhotos': <Map<String, dynamic>>[],
              },
            ],
            'page': 1,
            'size': 12,
            'totalElements': 20,
            'totalPages': 2,
          },
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      final result = await api.getTimeline(page: 1, size: 12);

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/photos/timeline/page');
      expect(adapter.lastQueryParams, {'page': 1, 'size': 12});
      expect(result.items, hasLength(1));
      expect(result.items.first.year, 2025);
      expect(result.items.first.monthGroup.photoCount, 15);
      expect(result.totalElements, 20);
    });

    test('getGroups sends GET with by query parameter', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'items': [
              {
                'groupKey': 'JPEG',
                'photoCount': 50,
                'photos': <Map<String, dynamic>>[],
              },
            ],
            'page': 1,
            'size': 12,
            'totalElements': 14,
            'totalPages': 2,
          },
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      final result = await api.getGroups('FORMAT', page: 1, size: 12);

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/photos/groups/page');
      expect(adapter.lastQueryParams, {'by': 'FORMAT', 'page': 1, 'size': 12});
      expect(result.items.first.groupKey, 'JPEG');
      expect(result.totalElements, 14);
    });

    test('getBatchDownloadTicket parses resumable archive metadata', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'url': 'https://storage.example/photos.zip',
            'fileName': 'photos_task-1.zip',
            'sizeBytes': 8192,
            'expiresAt': '2030-07-27T00:00:00Z',
            'sha256': 'abc123',
          },
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      final ticket = await api.getBatchDownloadTicket('task-1');

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/photos/batch/task-1/download-ticket');
      expect(ticket.fileName, 'photos_task-1.zip');
      expect(ticket.sizeBytes, 8192);
      expect(ticket.sha256, 'abc123');
      expect(ticket.expiresAt.toUtc(), DateTime.parse('2030-07-27T00:00:00Z'));
    });

    test('reanalyzeLibrary submits task and returns task id', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {'taskId': 'task-reanalyze', 'status': 'QUEUED'},
        },
      );
      final api = PhotoApi(_apiClient(adapter));

      final taskId = await api.reanalyzeLibrary();

      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastPath, '/photos/ai/reanalyze');
      expect(taskId, 'task-reanalyze');
    });

    test('throws AppException on 4xx response code', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {'code': 404, 'message': '照片不存在'},
      );
      final api = PhotoApi(_apiClient(adapter));

      expect(
        () => api.getPhoto('missing-id'),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', '404')
              .having((e) => e.message, 'message', contains('照片')),
        ),
      );
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
