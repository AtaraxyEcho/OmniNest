import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/reader/data/reader_api.dart';

void main() {
  group('ReaderApi', () {
    test('dashboard sends GET to /reader/dashboard', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'overview': {
              'totalItems': 42,
              'textCount': 30,
              'continueCount': 3,
              'collectionCount': 2,
            },
            'continueReading': <Map<String, dynamic>>[],
            'recentItems': <Map<String, dynamic>>[],
            'history': <Map<String, dynamic>>[],
            'collections': <Map<String, dynamic>>[],
          },
        },
      );
      final api = ReaderApi(_apiClient(adapter));

      final result = await api.dashboard();

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/reader/dashboard');
      expect(result.overview.totalItems, 42);
    });

    test('items sends GET to /reader/items with filters', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': [
            {
              'id': 'item-1',
              'title': 'Dart in Action',
              'itemType': 'NOVEL',
              'progressPercent': 45.5,
              'addedToBookshelf': true,
            },
          ],
        },
      );
      final api = ReaderApi(_apiClient(adapter));

      final result = await api.items(itemType: 'NOVEL', query: 'dart');

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/reader/items');
      expect(adapter.lastQueryParams, {'itemType': 'NOVEL', 'query': 'dart'});
      expect(result, hasLength(1));
      expect(result.first.title, 'Dart in Action');
      expect(result.first.progressPercent, 45.5);
    });

    test('items omits empty filters', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': <Map<String, dynamic>>[],
        },
      );
      final api = ReaderApi(_apiClient(adapter));

      await api.items();

      expect(adapter.lastQueryParams, isNull);
    });

    test('importCandidates parses typed candidates', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': [
            {
              'fileNodeId': 'file-1',
              'fileName': 'book.epub',
              'itemType': 'EPUB',
              'sizeDisplay': '2 MB',
            },
          ],
        },
      );
      final api = ReaderApi(_apiClient(adapter));

      final result = await api.importCandidates();

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/reader/import/candidates');
      expect(result, hasLength(1));
      expect(result.single.fileNodeId, 'file-1');
      expect(result.single.fileName, 'book.epub');
      expect(result.single.itemType, 'EPUB');
      expect(result.single.sizeDisplay, '2 MB');
    });

    test('detail sends GET to /reader/items/:id', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'item': {
              'id': 'item-10',
              'title': 'Flutter Cookbook',
              'itemType': 'TECHNICAL',
              'progressPercent': 80,
              'addedToBookshelf': true,
            },
            'chapters': [
              {'id': 'ch-1', 'chapterNumber': 1, 'title': 'Getting Started'},
            ],
            'progress': {'resourceId': 'item-10', 'progressPercent': 80},
          },
        },
      );
      final api = ReaderApi(_apiClient(adapter));

      final result = await api.detail('item-10');

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/reader/items/item-10');
      expect(result.item.id, 'item-10');
      expect(result.item.title, 'Flutter Cookbook');
      expect(result.chapters, hasLength(1));
      expect(result.progress, isNotNull);
      expect(result.progress!.progressPercent, 80);
    });

    test('getTextManifest parses persistent chapter offsets', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'itemId': 'item-10',
            'title': '测试书籍',
            'importStatus': 'READY',
            'chapters': [
              {
                'index': 0,
                'chapterKey': 'chapter_0',
                'title': '第一章',
                'charCount': 120,
                'sourceStartOffset': 0,
                'sourceEndOffset': 120,
                'level': 0,
              },
            ],
          },
        },
      );
      final api = ReaderApi(_apiClient(adapter));

      final result = await api.getTextManifest('item-10');

      expect(adapter.lastPath, '/reader/items/item-10/text/manifest');
      expect(result.importStatus, 'READY');
      expect(result.book.chapters, hasLength(1));
      expect(result.book.chapters.first.sourceEndOffset, 120);
    });

    test('toggleBookshelf sends POST to /reader/items/:id/bookshelf', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {'itemId': 'item-5', 'addedToBookshelf': true},
        },
      );
      final api = ReaderApi(_apiClient(adapter));

      await api.toggleBookshelf('item-5');

      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastPath, '/reader/items/item-5/bookshelf');
    });

    test('bookmarks sends GET to /reader/items/:id/bookmarks', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': [
            {
              'id': 'bm-1',
              'readerItemId': 'item-1',
              'scrollOffset': 1500,
              'progressPercent': 30,
            },
          ],
        },
      );
      final api = ReaderApi(_apiClient(adapter));

      final result = await api.bookmarks('item-1');

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/reader/items/item-1/bookmarks');
      expect(result, hasLength(1));
      expect(result.first.id, 'bm-1');
      expect(result.first.progressPercent, 30);
    });

    test('createAnnotation sends chapter ownership to the backend', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'id': 'annotation-1',
            'readerItemId': 'item-1',
            'chapterId': 'chapter_4',
            'startOffset': 10,
            'endOffset': 20,
            'color': '#FFEB3B',
            'createdAt': '2026-07-31T12:00:00Z',
          },
        },
      );
      final api = ReaderApi(_apiClient(adapter));

      final result = await api.createAnnotation(
        itemId: 'item-1',
        chapterId: 'chapter_4',
        startOffset: 10,
        endOffset: 20,
      );

      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastPath, '/reader/items/item-1/annotations');
      expect(adapter.lastData, containsPair('chapterId', 'chapter_4'));
      expect(result.chapterId, 'chapter_4');
    });

    test('deleteItem sends DELETE to /reader/items/:id', () async {
      final adapter = _CapturingHttpClientAdapter();
      final api = ReaderApi(_apiClient(adapter));

      await api.deleteItem('item-99');

      expect(adapter.lastMethod, 'DELETE');
      expect(adapter.lastPath, '/reader/items/item-99');
    });

    test('getFileTicket parses signed download metadata', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'itemId': 'item-99',
            'fileName': 'Large Book.epub',
            'downloadUrl': 'https://storage.example/book?signature=test',
            'sizeBytes': 2147483648,
            'sha256': 'abc123',
            'expiresAt': '2026-07-18T12:00:00Z',
          },
        },
      );
      final api = ReaderApi(_apiClient(adapter));

      final ticket = await api.getFileTicket('item-99');

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/reader/items/item-99/file-ticket');
      expect(ticket.fileName, 'Large Book.epub');
      expect(ticket.sizeBytes, 2147483648);
      expect(ticket.sha256, 'abc123');
    });

    test('Web 文件下载在正文请求前拒绝超过 32 MiB 的票据', () async {
      final adapter = _ReaderFileDownloadAdapter(
        sizeBytes: 32 * 1024 * 1024 + 1,
        bytes: Uint8List(0),
      );
      final api = ReaderApi(_apiClient(adapter));

      await expectLater(
        api.downloadFileBytes('item-large'),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            'READER_WEB_FILE_TOO_LARGE',
          ),
        ),
      );

      expect(adapter.fileRequestCount, 0);
    });

    test('Web 文件下载校验票据大小和 SHA-256', () async {
      final bytes = Uint8List.fromList(utf8.encode('bounded reader file'));
      final adapter = _ReaderFileDownloadAdapter(
        sizeBytes: bytes.length,
        sha256Value: sha256.convert(bytes).toString(),
        bytes: bytes,
      );
      final api = ReaderApi(_apiClient(adapter));

      final result = await api.downloadFileBytes('item-valid');

      expect(result, bytes);
      expect(adapter.fileRequestCount, 1);
    });

    test('Web 文件下载拒绝摘要不一致的正文', () async {
      final bytes = Uint8List.fromList(utf8.encode('tampered'));
      final adapter = _ReaderFileDownloadAdapter(
        sizeBytes: bytes.length,
        sha256Value: 'invalid-digest',
        bytes: bytes,
      );
      final api = ReaderApi(_apiClient(adapter));

      await expectLater(
        api.downloadFileBytes('item-invalid'),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            'READER_FILE_DIGEST_MISMATCH',
          ),
        ),
      );
    });

    test('reparseItem sends POST to /reader/items/:id/reparse', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'id': 'item-20',
            'title': 'Comic Volume',
            'itemType': 'CBZ',
            'contentKind': 'COMIC',
            'progressPercent': 0,
          },
        },
      );
      final api = ReaderApi(_apiClient(adapter));

      final result = await api.reparseItem('item-20');

      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastPath, '/reader/items/item-20/reparse');
      expect(result.id, 'item-20');
      expect(result.contentKind, 'COMIC');
      expect(result.isComic, isTrue);
    });

    test(
      'cover loading uses a bounded range and truncates oversized data',
      () async {
        final adapter = _BinaryHttpClientAdapter(
          Uint8List(12 * 1024 * 1024 + 32),
        );
        final api = ReaderApi(_apiClient(adapter));

        final bytes = await api.getCoverImage('item-cover');

        expect(adapter.lastPath, '/reader/items/item-cover/cover');
        expect(adapter.lastHeaders?['Range'], 'bytes=0-12582911');
        expect(bytes, hasLength(12 * 1024 * 1024));
      },
    );

    test('throws AppException on error response code', () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {'code': 404, 'message': '阅读条目不存在'},
      );
      final api = ReaderApi(_apiClient(adapter));

      expect(
        () => api.detail('missing'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('404'),
          ),
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

class _BinaryHttpClientAdapter implements HttpClientAdapter {
  _BinaryHttpClientAdapter(this.bytes);

  final Uint8List bytes;
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
    return ResponseBody(
      Stream.value(bytes),
      200,
      headers: {
        Headers.contentTypeHeader: ['image/jpeg'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ReaderFileDownloadAdapter implements HttpClientAdapter {
  _ReaderFileDownloadAdapter({
    required this.sizeBytes,
    required this.bytes,
    this.sha256Value,
  });

  final int sizeBytes;
  final Uint8List bytes;
  final String? sha256Value;
  int fileRequestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/file-ticket')) {
      return ResponseBody.fromString(
        jsonEncode({
          'code': 200,
          'message': 'success',
          'data': {
            'itemId': 'item',
            'fileName': 'book.epub',
            'downloadUrl': 'https://storage.example/book.epub',
            'sizeBytes': sizeBytes,
            'sha256': sha256Value,
            'expiresAt': '2026-07-30T12:00:00Z',
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    fileRequestCount++;
    return ResponseBody(
      Stream.value(bytes),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/epub+zip'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
