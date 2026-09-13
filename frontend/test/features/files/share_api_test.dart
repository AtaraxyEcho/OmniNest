import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/files/data/file_api.dart';
import 'package:omninest/features/files/data/share_api.dart';
import 'package:omninest/features/files/domain/public_share.dart';

void main() {
  // ==================== FileApi 分享方法测试 ====================

  group('FileApi share methods', () {
    late _CapturingHttpClientAdapter adapter;
    late FileApi fileApi;

    setUp(() {
      adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'resourceType': 'FILE',
            'resourceId': 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
            'resourceName': 'doc.pdf',
            'shareCode': 'abc123',
            'status': 'ACTIVE',
            'accessCount': 0,
            'createdAt': '2026-05-21T12:00:00Z',
          },
        },
      );
      fileApi = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );
    });

    test(
      'createShareLink sends POST to /files/shares with correct body',
      () async {
        await fileApi.createShareLink(
          resourceId: 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
          resourceType: 'FILE',
        );

        expect(adapter.lastMethod, 'POST');
        expect(adapter.lastPath, '/files/shares');
        final data = adapter.lastData as Map<String, dynamic>;
        expect(data['resourceId'], 'f4c31072-ae0a-4617-a632-28f8d7cf48a6');
        expect(data['resourceType'], 'FILE');
      },
    );

    test('createShareLink sends maxAccessCount when provided', () async {
      await fileApi.createShareLink(
        resourceId: 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
        maxAccessCount: 50,
      );

      final data = adapter.lastData as Map<String, dynamic>;
      expect(data['maxAccessCount'], 50);
    });

    test('createShareLink sends expiresAt in UTC ISO 8601', () async {
      final expires = DateTime(2026, 6, 15, 18, 0);

      await fileApi.createShareLink(
        resourceId: 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
        expiresAt: expires,
      );

      final data = adapter.lastData as Map<String, dynamic>;
      expect(data['expiresAt'], contains('2026'));
      expect(data['expiresAt'], endsWith('Z'));
    });

    test('revokeShare sends DELETE to /files/shares/{id}', () async {
      adapter = _CapturingHttpClientAdapter();
      fileApi = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      await fileApi.revokeShare('share-id-123');

      expect(adapter.lastMethod, 'DELETE');
      expect(adapter.lastPath, '/files/shares/share-id-123');
    });

    test('revokeShare throws AppException on non-200 response', () async {
      adapter = _CapturingHttpClientAdapter(
        body: {'code': 404, 'message': '分享链接不存在', 'data': null},
      );
      fileApi = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      expect(
        () => fileApi.revokeShare('nonexistent'),
        throwsA(isA<AppException>()),
      );
    });

    test('previewShare sends GET to /s/{token}/preview', () async {
      adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'shareId': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'fileName': 'report.xlsx',
            'mimeType': 'application/vnd.ms-excel',
            'sizeBytes': 4096,
            'resourceType': 'FILE',
            'hasPassword': true,
          },
        },
      );
      fileApi = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      final preview = await fileApi.previewShare('abc123', password: 'secret');

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/s/abc123/preview');
      expect(adapter.lastQueryParameters, isEmpty);
      expect(adapter.lastHeaders?['X-OmniNest-Share-Session'], 'session-test');
      expect(preview.fileName, 'report.xlsx');
      expect(preview.hasPassword, isTrue);
      expect(preview.sizeBytes, 4096);
    });

    test('previewShare omits password when not provided', () async {
      adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'shareId': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'fileName': 'public.pdf',
            'sizeBytes': 1024,
            'resourceType': 'FILE',
            'hasPassword': false,
          },
        },
      );
      fileApi = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      await fileApi.previewShare('abc123');

      expect(adapter.lastQueryParameters?.containsKey('password'), isFalse);
    });

    test('previewShare throws AppException on error response', () async {
      adapter = _CapturingHttpClientAdapter(
        body: {'code': 401, 'message': '密码错误', 'data': null},
      );
      fileApi = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      expect(
        () => fileApi.previewShare('abc123', password: 'wrong'),
        throwsA(isA<AppException>()),
      );
    });

    test('listMyShares sends GET to /files/shares', () async {
      adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'items': [
              {
                'id': '55b17588-5475-4f8f-9b5d-89afd8f81dd6',
                'resourceType': 'FILE',
                'resourceId': 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
                'resourceName': 'clip.mp4',
                'shareCode': 'abcdef',
                'status': 'ACTIVE',
                'maxAccessCount': 10,
                'accessCount': 2,
                'expiresAt': '2026-05-22T12:00:00Z',
                'disabledAt': null,
                'createdAt': '2026-05-20T12:00:00Z',
              },
            ],
          },
        },
      );
      fileApi = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      final shares = await fileApi.listMyShares();

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/files/shares');
      expect(shares, hasLength(1));
      expect(shares.single.resourceName, 'clip.mp4');
      expect(shares.single.status, 'ACTIVE');
    });

    test('acceptShare sends POST to /s/{token}/accept', () async {
      adapter = _CapturingHttpClientAdapter(
        body: {'code': 200, 'message': 'success', 'data': null},
      );
      fileApi = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      await fileApi.acceptShare('abc123', password: 'xK9mN2');

      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastPath, '/s/abc123/accept');
      final data = adapter.lastData as Map<String, dynamic>;
      expect(data.containsKey('password'), isFalse);
      expect(adapter.lastHeaders?['X-OmniNest-Share-Session'], 'session-test');
    });

    test('acceptShare omits password when not provided', () async {
      adapter = _CapturingHttpClientAdapter(
        body: {'code': 200, 'message': 'success', 'data': null},
      );
      fileApi = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      await fileApi.acceptShare('abc123');

      expect(adapter.lastData, isEmpty);
      expect(adapter.lastHeaders?['X-OmniNest-Share-Session'], 'session-test');
    });

    test('acceptShare sends targetParentId when provided', () async {
      adapter = _CapturingHttpClientAdapter(
        body: {'code': 200, 'message': 'success', 'data': null},
      );
      fileApi = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      await fileApi.acceptShare(
        'abc123',
        password: 'secret',
        targetParentId: 'folder-id-456',
      );

      final data = adapter.lastData as Map<String, dynamic>;
      expect(data.containsKey('password'), isFalse);
      expect(data['targetParentId'], 'folder-id-456');
      expect(adapter.lastHeaders?['X-OmniNest-Share-Session'], 'session-test');
    });
  });

  // ==================== ShareApi 独立测试 ====================

  group('ShareApi', () {
    test(
      'preview authorizes with password then sends session header',
      () async {
        final adapter = _ShareCapturingAdapter(
          body: {
            'code': 200,
            'message': 'success',
            'data': {
              'fileName': 'photo.jpg',
              'mimeType': 'image/jpeg',
              'sizeBytes': 2048,
              'resourceType': 'FILE',
              'hasPassword': true,
            },
          },
        );
        final api = _createShareApi(adapter);

        final result = await api.preview('token-abc', password: 'secret123');

        expect(adapter.lastMethod, 'GET');
        expect(adapter.lastPath, '/s/token-abc/preview');
        expect(adapter.lastQueryParams, isEmpty);
        expect(
          adapter.lastHeaders?['X-OmniNest-Share-Session'],
          'session-test',
        );
        expect(adapter.lastAuthorizeData, {'password': 'secret123'});
        expect(result, isA<SharePreviewSuccess>());
        final success = result as SharePreviewSuccess;
        expect(success.fileName, 'photo.jpg');
        expect(success.mimeType, 'image/jpeg');
        expect(success.sizeBytes, 2048);
        expect(success.hasPassword, isTrue);
      },
    );

    test(
      'preview omits password from preview request when not provided',
      () async {
        final adapter = _ShareCapturingAdapter(
          body: {
            'code': 200,
            'message': 'success',
            'data': {
              'fileName': 'public.pdf',
              'sizeBytes': 512,
              'resourceType': 'FILE',
              'hasPassword': false,
            },
          },
        );
        final api = _createShareApi(adapter);

        final result = await api.preview('token-abc');

        expect(adapter.lastQueryParams, isEmpty);
        expect(
          adapter.lastHeaders?['X-OmniNest-Share-Session'],
          'session-test',
        );
        expect(result, isA<SharePreviewSuccess>());
        final success = result as SharePreviewSuccess;
        expect(success.fileName, 'public.pdf');
        expect(success.hasPassword, isFalse);
      },
    );

    test('preview returns needPassword when server returns 401', () async {
      final adapter = _ShareCapturingAdapter(
        body: {'code': 401, 'message': '密码错误', 'data': null},
        httpStatusCode: 401,
      );
      final api = _createShareApi(adapter);

      final result = await api.preview('token-abc', password: 'wrong');

      expect(result, isA<SharePreviewNeedPassword>());
      final needPwd = result as SharePreviewNeedPassword;
      expect(needPwd.message, '密码错误');
    });

    test('preview returns error when server returns non-200', () async {
      final adapter = _ShareCapturingAdapter(
        body: {'code': 404, 'message': '分享链接不存在', 'data': null},
        httpStatusCode: 404,
      );
      final api = _createShareApi(adapter);

      final result = await api.preview('expired-token');

      expect(result, isA<SharePreviewError>());
      final error = result as SharePreviewError;
      expect(error.message, '分享链接不存在');
    });

    test(
      'accept sends POST to /s/{token}/accept with session header',
      () async {
        final adapter = _ShareCapturingAdapter(
          body: {'code': 200, 'message': 'success', 'data': null},
        );
        final api = _createShareApi(adapter);

        final result = await api.accept('token-abc', password: 'xK9mN2');

        expect(adapter.lastMethod, 'POST');
        expect(adapter.lastPath, '/s/token-abc/accept');
        expect(adapter.lastData, isNull);
        expect(
          adapter.lastHeaders?['X-OmniNest-Share-Session'],
          'session-test',
        );
        expect(adapter.lastAuthorizeData, {'password': 'xK9mN2'});
        expect(result, isA<ShareAcceptSuccess>());
      },
    );

    test('accept omits password in body when not provided', () async {
      final adapter = _ShareCapturingAdapter(
        body: {'code': 200, 'message': 'success', 'data': null},
      );
      final api = _createShareApi(adapter);

      final result = await api.accept('token-abc');

      expect(adapter.lastData, isNull);
      expect(adapter.lastHeaders?['X-OmniNest-Share-Session'], 'session-test');
      expect(result, isA<ShareAcceptSuccess>());
    });

    test('accept sends Authorization header when authToken provided', () async {
      final adapter = _ShareCapturingAdapter(
        body: {'code': 200, 'message': 'success', 'data': null},
      );
      final api = _createShareApi(adapter);

      await api.accept(
        'token-abc',
        password: 'secret',
        authToken: 'jwt-token-123',
      );

      expect(adapter.lastHeaders?['Authorization'], 'Bearer jwt-token-123');
    });

    test('accept returns duplicate when server returns 409', () async {
      final adapter = _ShareCapturingAdapter(
        body: {'code': 409, 'message': '文件已存在', 'data': null},
        httpStatusCode: 409,
      );
      final api = _createShareApi(adapter);

      final result = await api.accept('token-abc');

      expect(result, isA<ShareAcceptDuplicate>());
      final duplicate = result as ShareAcceptDuplicate;
      expect(duplicate.message, '文件已存在');
    });

    test('accept returns error when server returns non-200/409', () async {
      final adapter = _ShareCapturingAdapter(
        body: {'code': 500, 'message': '服务器内部错误', 'data': null},
        httpStatusCode: 500,
      );
      final api = _createShareApi(adapter);

      final result = await api.accept('token-abc');

      expect(result, isA<ShareAcceptError>());
      final error = result as ShareAcceptError;
      expect(error.message, '服务器内部错误');
    });

    test('preview returns error when response data is null', () async {
      final adapter = _ShareCapturingAdapter(
        body: {'code': 200, 'message': 'success', 'data': null},
      );
      final api = _createShareApi(adapter);

      final result = await api.preview('token-abc');

      expect(result, isA<SharePreviewError>());
      final error = result as SharePreviewError;
      expect(error.message, AppErrorCodes.emptyResponse);
    });

    test('preview returns error on network failure', () async {
      final adapter = _ShareCapturingAdapter(
        body: {'code': 200, 'message': 'success', 'data': {}},
        throwException: DioException(
          type: DioExceptionType.connectionTimeout,
          requestOptions: RequestOptions(path: '/s/token/preview'),
          message: 'Connection timed out',
        ),
      );
      final api = _createShareApi(adapter);

      final result = await api.preview('token-abc');

      expect(result, isA<SharePreviewError>());
      final error = result as SharePreviewError;
      expect(error.message, AppErrorCodes.networkTimeout);
    });
  });
}

/// 用于 FileApi 的请求捕获适配器。
///
/// 复用 file_api_test.dart 中的模式。
class _CapturingHttpClientAdapter implements HttpClientAdapter {
  _CapturingHttpClientAdapter({
    this.body = const {'code': 200, 'message': 'success', 'data': {}},
  });

  final Map<String, dynamic> body;
  String? lastMethod;
  String? lastPath;
  Map<String, dynamic>? lastQueryParameters;
  Object? lastData;
  Map<String, dynamic>? lastHeaders;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastMethod = options.method;
    lastPath = options.path;
    lastQueryParameters = Map<String, dynamic>.from(options.queryParameters);
    lastData = options.data;
    lastHeaders = Map<String, dynamic>.from(options.headers);
    if (options.path.endsWith('/authorize') && body['code'] == 200) {
      return ResponseBody.fromString(
        jsonEncode({
          'code': 200,
          'message': 'success',
          'data': {'sessionToken': 'session-test'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
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

/// 用于 ShareApi 的请求捕获适配器。
///
/// ShareApi 使用独立的 Dio 实例，需要捕获 headers 和 queryParameters。
class _ShareCapturingAdapter implements HttpClientAdapter {
  _ShareCapturingAdapter({
    required this.body,
    this.httpStatusCode = 200,
    this.throwException,
  });

  final Map<String, dynamic> body;
  final int httpStatusCode;
  final DioException? throwException;
  String? lastMethod;
  String? lastPath;
  Map<String, dynamic>? lastQueryParams;
  Object? lastData;
  Map<String, dynamic>? lastHeaders;
  Object? lastAuthorizeData;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throwException != null) {
      throw throwException!;
    }
    lastMethod = options.method;
    lastPath = options.path;
    lastQueryParams = Map<String, dynamic>.from(options.queryParameters);
    lastData = options.data;
    lastHeaders = Map<String, dynamic>.from(options.headers);
    if (options.path.endsWith('/authorize') &&
        body['code'] != 401 &&
        body['code'] != 404) {
      lastAuthorizeData = options.data;
      return ResponseBody.fromString(
        jsonEncode({
          'code': 200,
          'message': 'success',
          'data': {'sessionToken': 'session-test'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      httpStatusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 创建注入了捕获适配器的 ShareApi 实例。
ShareApi _createShareApi(_ShareCapturingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080/api/v1'));
  dio.httpClientAdapter = adapter;
  // 直接访问 ShareApi 的内部 Dio，通过反射不可行，
  // 改为创建一个带可注入 Dio 的包装。
  return ShareApi.fromDio(dio);
}
