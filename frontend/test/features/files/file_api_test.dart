import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/files/data/dtos/file_node_dto.dart';
import 'package:omninest/features/files/data/dtos/file_upload_session_dto.dart';
import 'package:omninest/features/files/data/file_api.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';

void main() {
  late FileApi fileApi;

  setUp(() {
    fileApi = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
      ),
    );
  });

  test('maps backend file node json to domain model', () {
    final dto = FileNodeDto.fromJson({
      'id': 'c216e4f0-b0d2-4621-92dd-b74cbf7fb522',
      'parentId': null,
      'nodeType': 'FOLDER',
      'name': 'Movies',
      'normalizedPath': '/Movies',
      'mimeType': null,
      'sizeBytes': 0,
      'updatedAt': '2026-05-19T12:00:00Z',
      'mediaAutoImportTaskId': '0c216e4f-b0d2-4621-92dd-b74cbf7fb522',
    });

    final node = dto.toDomain();

    expect(node.id, 'c216e4f0-b0d2-4621-92dd-b74cbf7fb522');
    expect(node.name, 'Movies');
    expect(node.isFolder, isTrue);
    expect(node.normalizedPath, '/Movies');
    expect(node.mediaAutoImportTaskId, '0c216e4f-b0d2-4621-92dd-b74cbf7fb522');
  });

  test('parses successful paged file response', () {
    final result = fileApi.parseFilePageResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'items': [
          {
            'id': 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
            'parentId': null,
            'nodeType': 'FILE',
            'name': 'clip.mp4',
            'normalizedPath': '/clip.mp4',
            'mimeType': 'video/mp4',
            'sizeBytes': 4096,
            'updatedAt': '2026-05-19T12:00:00Z',
          },
        ],
        'page': 0,
        'size': 50,
        'totalElements': 1,
        'totalPages': 1,
      },
    });

    expect(result.items, hasLength(1));
    expect(result.items.single.name, 'clip.mp4');
    expect(result.items.single.isFolder, isFalse);
    expect(result.items.single.sizeBytes, 4096);
    expect(result.page, 0);
    expect(result.totalElements, 1);
    expect(result.hasNextPage, isFalse);
  });

  test('preserves structured file conflict details', () {
    expect(
      () => fileApi.parseEnvelope(<String, dynamic>{
        'code': 409,
        'message': '同级目录下已存在同名文件',
        'details': <String, Object?>{
          'existingFileId': 'existing-file',
          'sizeBytes': 4096,
        },
      }),
      throwsA(
        isA<AppException>()
            .having((error) => error.code, 'code', '409')
            .having(
              (error) => error.details['existingFileId'],
              'existing file id',
              'existing-file',
            )
            .having((error) => error.details['sizeBytes'], 'size bytes', 4096),
      ),
    );
  });

  test('parses safe external storage metadata without credential secrets', () {
    final accounts = fileApi.parseExternalStoragePageResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'items': [
          {
            'id': 'storage-id',
            'provider': 'S3',
            'displayName': '家庭对象存储',
            'connectionMetadata': {
              'provider': 'Minio',
              'access_key_id': 'saved-access-key',
              'endpoint': 'https://storage.example.com',
              'region': 'cn-east-1',
            },
            'credentialsConfigured': true,
            'status': 'ACTIVE',
          },
        ],
        'page': 0,
        'size': 50,
        'totalElements': 1,
        'totalPages': 1,
      },
    });

    expect(accounts.single.connectionMetadata, {
      'provider': 'Minio',
      'access_key_id': 'saved-access-key',
      'endpoint': 'https://storage.example.com',
      'region': 'cn-east-1',
    });
    expect(accounts.single.credentialsConfigured, isTrue);
  });

  test('list files sends category query parameter', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'items': [],
          'page': 0,
          'size': 50,
          'totalElements': 0,
          'totalPages': 0,
        },
      },
    );
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );

    await api.listFiles(category: 'video');

    expect(adapter.lastPath, '/files');
    expect(adapter.lastQueryParameters, {
      'category': 'video',
      'page': 0,
      'size': 200,
    });
  });

  test('list files omits all category query parameter', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'items': [],
          'page': 0,
          'size': 50,
          'totalElements': 0,
          'totalPages': 0,
        },
      },
    );
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );

    await api.listFiles(category: 'all');

    expect(adapter.lastQueryParameters, {'page': 0, 'size': 200});
  });

  test('presigned upload sends mapped byte stream as binary content', () async {
    final adapter = _CapturingHttpClientAdapter();
    final uploadDio = Dio()..httpClientAdapter = adapter;
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
      ),
      uploadDio: uploadDio,
    );
    addTearDown(api.close);
    final data = Stream<List<int>>.value(const <int>[
      1,
      2,
      3,
    ]).map(Uint8List.fromList);

    await api.putUploadUrl(
      uploadUrl: 'http://minio/upload',
      data: data,
      contentLength: 3,
    );

    expect(adapter.lastContentType, 'application/octet-stream');
    expect(adapter.lastHeaders?[Headers.contentLengthHeader], 3);
  });

  test('text preview reads signed URL with a bounded range', () async {
    final apiAdapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {'downloadUrl': 'http://minio/preview.txt'},
      },
    );
    final textAdapter = _TextHttpClientAdapter('preview content');
    final externalDio = Dio()..httpClientAdapter = textAdapter;
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: apiAdapter,
      ),
      uploadDio: externalDio,
    );
    addTearDown(api.close);

    final content = await api.loadTextPreview('file-1');

    expect(apiAdapter.lastPath, '/files/file-1/download-url');
    expect(textAdapter.lastPath, 'http://minio/preview.txt');
    expect(textAdapter.lastHeaders?['Range'], 'bytes=0-1048575');
    expect(content, 'preview content');
  });

  test('text preview truncates oversized responses to one MiB', () async {
    final apiAdapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {'downloadUrl': 'http://minio/oversized.txt'},
      },
    );
    final textAdapter = _TextHttpClientAdapter(
      List<String>.filled(1024 * 1024 + 32, 'a').join(),
      statusCode: 200,
    );
    final externalDio = Dio()..httpClientAdapter = textAdapter;
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: apiAdapter,
      ),
      uploadDio: externalDio,
    );
    addTearDown(api.close);

    final content = await api.loadTextPreview('file-2');

    expect(content.length, 1024 * 1024);
  });

  test('presigned upload cancellation interrupts the active request', () async {
    final adapter = _BlockingHttpClientAdapter();
    final uploadDio = Dio()..httpClientAdapter = adapter;
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
      ),
      uploadDio: uploadDio,
    );
    addTearDown(api.close);
    final cancellation = FileUploadCancellationToken();

    final upload = api.putUploadUrl(
      uploadUrl: 'http://localhost/upload',
      data: Stream<List<int>>.value([1, 2, 3]),
      contentLength: 3,
      cancellationToken: cancellation,
    );
    await adapter.started.future;
    cancellation.cancel();

    await expectLater(
      upload,
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
  });

  test('throws app exception when file response is not success', () {
    expect(
      () => fileApi.parseFilePageResponse({
        'code': 404,
        'message': '文件不存在',
        'data': null,
      }),
      throwsA(isA<AppException>()),
    );
  });

  test('maps backend upload session json to domain model', () {
    final dto = FileUploadSessionDto.fromJson({
      'id': '55b17588-5475-4f8f-9b5d-89afd8f81dd6',
      'parentId': null,
      'fileName': 'archive.zip',
      'sizeBytes': 1048576,
      'mimeType': 'application/zip',
      'status': 'CREATED',
      'bucket': 'omninest-files',
      'objectKey': 'users/root/uploads/archive.zip',
      'uploadUrl': 'http://localhost:9000/omninest-files/archive.zip',
      'expiresAt': '2026-05-20T12:30:00Z',
    });

    final session = dto.toDomain();

    expect(session.id, '55b17588-5475-4f8f-9b5d-89afd8f81dd6');
    expect(session.fileName, 'archive.zip');
    expect(session.sizeBytes, 1048576);
    expect(session.uploadUrl, contains('localhost:9000'));
    expect(session.expiresAt, DateTime.parse('2026-05-20T12:30:00Z').toLocal());
  });

  test('complete upload part sends part number in request body', () async {
    final adapter = _CapturingHttpClientAdapter();
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );

    await api.completeUploadPart(
      uploadId: 'upload-123',
      partNumber: 2,
      eTag: 'etag-2',
    );

    expect(adapter.lastPath, '/uploads/upload-123/parts/2/complete');
    expect(adapter.lastData, {'partNumber': 2, 'eTag': 'etag-2'});
  });

  test('cancel upload session sends delete request', () async {
    final adapter = _CapturingHttpClientAdapter();
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );

    await api.cancelUploadSession('upload-123');

    expect(adapter.lastMethod, 'DELETE');
    expect(adapter.lastPath, '/uploads/upload-123');
  });

  test('batchDownload sends POST with fileIds', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {'code': 200, 'message': 'success', 'data': {}},
    );
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );

    final response = await api.batchDownload([
      'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
      'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    ]);

    expect(adapter.lastMethod, 'POST');
    expect(adapter.lastPath, '/files/batch/download');
    expect(adapter.lastData, {
      'fileIds': [
        'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
        'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      ],
    });
    expect(response.data, isA<List<int>>());
  });

  test('parses storage stats response', () {
    final stats = fileApi.parseStorageStatsResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'totalFiles': 8,
        'totalFolders': 2,
        'usedBytes': 4096,
        'quotaBytes': 8192,
        'typeDistribution': [
          {'category': '视频', 'count': 3, 'sizeBytes': 2048},
          {'category': '文档', 'count': 5, 'sizeBytes': 2048},
        ],
      },
    });

    expect(stats.totalFiles, 8);
    expect(stats.quotaBytes, 8192);
    expect(stats.typeDistribution.first.category, '视频');
  });

  test('parses share link page response', () {
    final shares = fileApi.parseShareLinkPageResponse({
      'code': 200,
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
    });

    expect(shares.single.resourceName, 'clip.mp4');
    expect(shares.single.status, 'ACTIVE');
  });

  test('parses offline download progress response', () {
    final tasks = fileApi.parseOfflineTaskPageResponse({
      'code': 200,
      'data': {
        'items': [
          {
            'id': '55b17588-5475-4f8f-9b5d-89afd8f81dd6',
            'sourceUri': 'magnet:?xt=urn:btih:0123456789abcdef',
            'targetParentId': null,
            'taskId': '55b17588-5475-4f8f-9b5d-89afd8f81dd6',
            'status': 'RUNNING',
            'aria2Gid': 'abcdef1234567890',
            'fileName': 'movie.mkv',
            'totalBytes': 100,
            'completedBytes': 25,
            'downloadSpeedBytes': 10,
            'errorSummary': null,
            'completedFileId': null,
            'completedAt': null,
            'createdAt': '2026-05-21T12:00:00Z',
            'updatedAt': '2026-05-21T12:01:00Z',
          },
        ],
      },
    });

    expect(tasks.single.fileName, 'movie.mkv');
    expect(tasks.single.progress, 0.25);
    expect(tasks.single.downloadSpeedBytes, 10);
  });

  // ==================== 分享链接测试 ====================

  test('parseShareLink includes generatedPassword when present', () {
    final result = fileApi.parseShareLinkResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        'resourceType': 'FILE',
        'resourceId': 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
        'resourceName': 'doc.pdf',
        'shareCode': 'abc123def456',
        'status': 'ACTIVE',
        'maxAccessCount': null,
        'accessCount': 0,
        'expiresAt': null,
        'disabledAt': null,
        'createdAt': '2026-05-21T12:00:00Z',
        'generatedPassword': 'Ab3xK9',
      },
    });

    expect(result.generatedPassword, 'Ab3xK9');
    expect(result.shareCode, 'abc123def456');
    expect(result.resourceName, 'doc.pdf');
  });

  test('parseShareLink has null generatedPassword when not present', () {
    final result = fileApi.parseShareLinkResponse({
      'code': 200,
      'message': 'success',
      'data': {
        'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        'resourceType': 'FILE',
        'resourceId': 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
        'resourceName': 'doc.pdf',
        'shareCode': 'abc123def456',
        'status': 'ACTIVE',
        'maxAccessCount': 10,
        'accessCount': 3,
        'expiresAt': null,
        'disabledAt': null,
        'createdAt': '2026-05-21T12:00:00Z',
      },
    });

    expect(result.generatedPassword, isNull);
    expect(result.maxAccessCount, 10);
    expect(result.accessCount, 3);
  });

  test(
    'createShareLink sends password and generatePassword in request body',
    () async {
      final adapter = _CapturingHttpClientAdapter(
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
            'generatedPassword': 'Xy7mN2',
          },
        },
      );
      final api = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      await api.createShareLink(
        resourceId: 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
        resourceType: 'FILE',
        generatePassword: true,
      );

      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastPath, '/files/shares');
      expect(adapter.lastData, isA<Map<String, dynamic>>());
      final data = adapter.lastData as Map<String, dynamic>;
      expect(data['generatePassword'], isTrue);
      expect(data.containsKey('password'), isFalse);
    },
  );

  test('createShareLink sends custom password when provided', () async {
    final adapter = _CapturingHttpClientAdapter(
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
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );

    await api.createShareLink(
      resourceId: 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
      password: 'secret123',
    );

    final data = adapter.lastData as Map<String, dynamic>;
    expect(data['password'], 'secret123');
    expect(data['generatePassword'], isFalse);
  });

  // ==================== 端到端分享流程测试 ====================

  test('share flow: create with random password → preview → accept', () async {
    // 步骤1：创建分享，后端返回 generatedPassword
    final createAdapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
          'resourceType': 'FILE',
          'resourceId': 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
          'resourceName': 'report.xlsx',
          'shareCode': 'abc123def456',
          'status': 'ACTIVE',
          'accessCount': 0,
          'createdAt': '2026-06-04T12:00:00Z',
          'generatedPassword': 'xK9mN2',
        },
      },
    );
    final createApi = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: createAdapter,
      ),
    );

    final shareLink = await createApi.createShareLink(
      resourceId: 'f4c31072-ae0a-4617-a632-28f8d7cf48a6',
      generatePassword: true,
    );

    expect(shareLink.generatedPassword, 'xK9mN2');
    expect(shareLink.shareCode, 'abc123def456');

    // 步骤2：用正确密码预览 → 成功
    final previewAdapter = _CapturingHttpClientAdapter(
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
    final previewApi = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: previewAdapter,
      ),
    );

    final preview = await previewApi.previewShare(
      'abc123def456',
      password: 'xK9mN2',
    );

    expect(preview.fileName, 'report.xlsx');
    expect(preview.hasPassword, isTrue);
    expect(preview.sizeBytes, 4096);
    expect(previewAdapter.lastQueryParameters, isEmpty);
    expect(
      previewAdapter.lastHeaders?['X-OmniNest-Share-Session'],
      'session-test',
    );
  });

  test('share flow: preview with wrong password throws', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {'code': 401, 'message': '密码错误', 'data': null},
    );
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );

    expect(
      () => api.previewShare('abc123def456', password: 'wrong'),
      throwsA(isA<AppException>()),
    );
  });

  test(
    'share flow: preview without password on protected link throws',
    () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {'code': 401, 'message': '密码错误', 'data': null},
      );
      final api = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      expect(
        () => api.previewShare('abc123def456'),
        throwsA(isA<AppException>()),
      );
    },
  );

  test(
    'share flow: accept sends session header and omits password body',
    () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {'code': 200, 'message': 'success', 'data': null},
      );
      final api = FileApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          httpClientAdapter: adapter,
        ),
      );

      await api.acceptShare('abc123def456', password: 'xK9mN2');

      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastPath, '/s/abc123def456/accept');
      final data = adapter.lastData as Map<String, dynamic>;
      expect(data.containsKey('password'), isFalse);
      expect(adapter.lastHeaders?['X-OmniNest-Share-Session'], 'session-test');
    },
  );

  test('share flow: preview sends empty password when not provided', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'shareId': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
          'fileName': 'public.pdf',
          'mimeType': 'application/pdf',
          'sizeBytes': 1024,
          'resourceType': 'FILE',
          'hasPassword': false,
        },
      },
    );
    final api = FileApi(
      ApiClient(
        const AppEnvironment(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          wsBaseUrl: 'ws://localhost:8080/ws',
        ),
        httpClientAdapter: adapter,
      ),
    );

    final preview = await api.previewShare('abc123def456');

    expect(preview.fileName, 'public.pdf');
    expect(preview.hasPassword, isFalse);
    expect(adapter.lastQueryParameters, isEmpty);
    expect(adapter.lastHeaders?['X-OmniNest-Share-Session'], 'session-test');
  });
}

class _CapturingHttpClientAdapter implements HttpClientAdapter {
  _CapturingHttpClientAdapter({
    this.body = const {'code': 200, 'message': 'success', 'data': {}},
  });

  final Map<String, dynamic> body;
  String? lastMethod;
  String? lastPath;
  Map<String, dynamic>? lastQueryParameters;
  Object? lastData;
  String? lastContentType;
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
    lastContentType = options.contentType;
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

class _BlockingHttpClientAdapter implements HttpClientAdapter {
  final Completer<void> started = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await cancelFuture;
    throw DioException.requestCancelled(
      requestOptions: options,
      reason: 'cancelled',
    );
  }

  @override
  void close({bool force = false}) {}
}

class _TextHttpClientAdapter implements HttpClientAdapter {
  _TextHttpClientAdapter(this.content, {this.statusCode = 206});

  final String content;
  final int statusCode;
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
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
