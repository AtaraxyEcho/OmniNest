import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/files/application/media_import_service.dart';
import 'package:omninest/features/files/data/file_api.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';

void main() {
  test('单文件复用会返回稳定的文件节点 ID', () async {
    final fileApi = _ConflictFileApi(
      error: const AppException(
        code: '409',
        message: '同级目录下已存在同名文件',
        details: <String, Object?>{
          'existingFileId': 'existing-file',
          'sizeBytes': 4,
          'mimeType': 'image/jpeg',
        },
      ),
    );
    final service = MediaImportService(fileApi);

    final imported = await service.importFile(
      file: await _photoFile(),
      parentId: 'photos',
      reuseExistingFiles: true,
    );

    expect(imported.fileName, 'photo.jpg');
    expect(imported.fileNodeId, 'existing-file');
  });

  test('取消导入会终止传输并清理服务端上传会话', () async {
    final fileApi = _CancellableFileApi();
    final service = MediaImportService(fileApi);
    final cancellationToken = MediaImportCancellationToken();

    final future = service.importFile(
      file: await _photoFile(),
      parentId: 'photos',
      reuseExistingFiles: false,
      cancellationToken: cancellationToken,
    );
    await fileApi.uploadStarted.future;
    cancellationToken.cancel();

    await expectLater(future, throwsA(isA<MediaImportCancelledException>()));
    expect(fileApi.cancelledUploadIds, <String>['upload-1']);
  });

  test('活动同名同大小文件直接重新处理而不重复上传', () async {
    final fileApi = _ConflictFileApi(
      error: const AppException(
        code: '409',
        message: '同级目录下已存在同名文件',
        details: <String, Object?>{
          'existingFileId': 'existing-file',
          'sizeBytes': 4,
          'mimeType': 'image/jpeg',
        },
      ),
    );
    final service = MediaImportService(fileApi);

    final imported = await service.importFiles(
      files: <XFile>[await _photoFile()],
      parentId: 'photos',
      reuseExistingFiles: true,
    );

    expect(imported, <String>['photo.jpg']);
    expect(fileApi.restoredFileIds, isEmpty);
    expect(fileApi.reprocessedFileIds, <String>['existing-file']);
  });

  test('回收站同名同大小文件先恢复再重新处理', () async {
    final fileApi = _ConflictFileApi(
      error: const AppException(
        code: '409',
        message: '回收站存在同名文件',
        details: <String, Object?>{
          'softDeletedFileId': 'deleted-file',
          'sizeBytes': 4,
          'mimeType': 'image/jpeg',
        },
      ),
    );
    final service = MediaImportService(fileApi);

    final imported = await service.importFiles(
      files: <XFile>[await _photoFile()],
      parentId: 'photos',
      reuseExistingFiles: true,
    );

    expect(imported, <String>['photo.jpg']);
    expect(fileApi.restoredFileIds, <String>['deleted-file']);
    expect(fileApi.reprocessedFileIds, <String>['deleted-file']);
  });

  test('同名文件大小不一致时拒绝复用', () async {
    final fileApi = _ConflictFileApi(
      error: const AppException(
        code: '409',
        message: '同级目录下已存在同名文件',
        details: <String, Object?>{
          'existingFileId': 'different-file',
          'sizeBytes': 1024,
          'mimeType': 'image/jpeg',
        },
      ),
    );
    final service = MediaImportService(fileApi);

    final imported = await service.importFiles(
      files: <XFile>[await _photoFile()],
      parentId: 'photos',
      reuseExistingFiles: true,
    );

    expect(imported, isEmpty);
    expect(fileApi.restoredFileIds, isEmpty);
    expect(fileApi.reprocessedFileIds, isEmpty);
  });

  test('批量导入保留逐文件失败原因', () async {
    final fileApi = _ConflictFileApi(
      error: const AppException(
        code: 'DEPENDENCY_UNAVAILABLE',
        message: '安全扫描服务不可用，文件已隔离',
      ),
    );
    final service = MediaImportService(fileApi);

    final result = await service.importFilesDetailed(
      files: <XFile>[await _photoFile()],
      parentId: 'photos',
    );

    expect(result.imported, isEmpty);
    expect(result.failures, hasLength(1));
    expect(result.failures.single.fileName, 'photo.jpg');
    expect(result.failures.single.error, isA<AppException>());
  });

  test('直接上传完成后取消不会提交完成请求', () async {
    final fileApi = _PostUploadCancellationFileApi();
    final service = MediaImportService(fileApi);
    final cancellationToken = MediaImportCancellationToken();
    fileApi.afterPut = cancellationToken.cancel;

    final future = service.importFile(
      file: await _photoFile(),
      parentId: 'photos',
      reuseExistingFiles: false,
      cancellationToken: cancellationToken,
    );

    await expectLater(future, throwsA(isA<MediaImportCancelledException>()));
    expect(fileApi.completeCalled, isFalse);
    expect(fileApi.cancelledUploadIds, <String>['upload-1']);
  });

  test('创建上传会话返回后取消会清理已创建会话', () async {
    final fileApi = _PostUploadCancellationFileApi();
    final service = MediaImportService(fileApi);
    final cancellationToken = MediaImportCancellationToken();
    fileApi.afterCreate = cancellationToken.cancel;

    final future = service.importFile(
      file: await _photoFile(),
      parentId: 'photos',
      reuseExistingFiles: false,
      cancellationToken: cancellationToken,
    );

    await expectLater(future, throwsA(isA<MediaImportCancelledException>()));
    expect(fileApi.completeCalled, isFalse);
    expect(fileApi.cancelledUploadIds, <String>['upload-1']);
  });

  test('完成请求开始后取消不会删除已完成会话', () async {
    final fileApi = _PostUploadCancellationFileApi();
    final service = MediaImportService(fileApi);
    final cancellationToken = MediaImportCancellationToken();
    fileApi.duringComplete = cancellationToken.cancel;

    final result = await service.importFile(
      file: await _photoFile(),
      parentId: 'photos',
      reuseExistingFiles: false,
      cancellationToken: cancellationToken,
    );

    expect(result.fileNodeId, 'photo-id');
    expect(fileApi.completeCalled, isTrue);
    expect(fileApi.cancelledUploadIds, isEmpty);
  });

  test('retries upload completion after a transient conflict', () async {
    final fileApi = _RetryingCompleteFileApi();
    final service = MediaImportService(fileApi);

    final imported = await service.importFile(
      file: await _photoFile(),
      parentId: 'photos',
      reuseExistingFiles: false,
    );

    expect(imported.fileNodeId, 'photo-id');
    expect(fileApi.completeAttempts, 3);
  });
}

Future<XFile> _photoFile() async {
  final directory = await Directory.systemTemp.createTemp(
    'omninest-media-import-',
  );
  addTearDown(() => directory.delete(recursive: true));
  final file = File('${directory.path}${Platform.pathSeparator}photo.jpg');
  await file.writeAsBytes(<int>[1, 2, 3, 4]);
  return XFile(file.path, mimeType: 'image/jpeg');
}

class _ConflictFileApi extends FileApi {
  _ConflictFileApi({required this.error})
    : super(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      );

  final AppException error;
  final List<String> restoredFileIds = <String>[];
  final List<String> reprocessedFileIds = <String>[];

  @override
  Future<FileUploadPolicy> uploadPolicy() async {
    return const FileUploadPolicy(
      directUploadMaxBytes: 64 * 1024 * 1024,
      defaultPartSizeBytes: 10 * 1024 * 1024,
      maxPartSizeBytes: 100 * 1024 * 1024,
      maxTotalParts: 1000,
      maxConcurrentParts: 4,
    );
  }

  @override
  Future<FileUploadSession> createUploadSession({
    String? parentId,
    required String fileName,
    required int sizeBytes,
    String? mimeType,
    String? sha256,
    int? partSizeBytes,
    String? spaceType,
    String? asVersionOfFileId,
  }) async {
    throw error;
  }

  @override
  Future<FileNode> restoreFile(String fileId) async {
    restoredFileIds.add(fileId);
    return _fileNode(fileId);
  }

  @override
  Future<FileNode> reprocessFile(String fileId) async {
    reprocessedFileIds.add(fileId);
    return _fileNode(fileId);
  }

  FileNode _fileNode(String fileId) {
    return FileNode(
      id: fileId,
      parentId: 'photos',
      name: 'photo.jpg',
      isFolder: false,
      nodeType: 'FILE',
      normalizedPath: '/Photos/photo.jpg',
      sizeBytes: 4,
      updatedAt: null,
      mimeType: 'image/jpeg',
    );
  }
}

class _CancellableFileApi extends FileApi {
  _CancellableFileApi()
    : super(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      );

  final Completer<void> uploadStarted = Completer<void>();
  final List<String> cancelledUploadIds = <String>[];

  @override
  Future<FileUploadPolicy> uploadPolicy() async {
    return const FileUploadPolicy(
      directUploadMaxBytes: 64 * 1024 * 1024,
      defaultPartSizeBytes: 10 * 1024 * 1024,
      maxPartSizeBytes: 100 * 1024 * 1024,
      maxTotalParts: 1000,
      maxConcurrentParts: 4,
    );
  }

  @override
  Future<FileUploadSession> createUploadSession({
    String? parentId,
    required String fileName,
    required int sizeBytes,
    String? mimeType,
    String? sha256,
    int? partSizeBytes,
    String? spaceType,
    String? asVersionOfFileId,
  }) async {
    return FileUploadSession(
      id: 'session-1',
      uploadId: 'upload-1',
      parentId: parentId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      partSizeBytes: sizeBytes,
      totalParts: 1,
      mimeType: mimeType ?? 'application/octet-stream',
      status: 'UPLOADING',
      bucket: 'private',
      objectKey: 'photos/photo.jpg',
      uploadUrl: 'http://localhost/upload-1',
      parts: const <FileUploadPart>[],
      expiresAt: null,
    );
  }

  @override
  Future<String> putUploadUrl({
    required String uploadUrl,
    required Stream<List<int>> data,
    required int contentLength,
    FileUploadCancellationToken? cancellationToken,
    FileUploadProgressCallback? onProgress,
  }) {
    final completer = Completer<String>();
    cancellationToken?.addListener(
      () => completer.completeError(StateError('upload cancelled')),
    );
    uploadStarted.complete();
    return completer.future;
  }

  @override
  Future<void> cancelUploadSession(String uploadId) async {
    cancelledUploadIds.add(uploadId);
  }
}

class _PostUploadCancellationFileApi extends FileApi {
  _PostUploadCancellationFileApi()
    : super(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      );

  VoidCallback? afterPut;
  VoidCallback? afterCreate;
  VoidCallback? duringComplete;
  bool completeCalled = false;
  final List<String> cancelledUploadIds = <String>[];

  @override
  Future<FileUploadPolicy> uploadPolicy() async {
    return const FileUploadPolicy(
      directUploadMaxBytes: 64 * 1024 * 1024,
      defaultPartSizeBytes: 10 * 1024 * 1024,
      maxPartSizeBytes: 100 * 1024 * 1024,
      maxTotalParts: 1000,
      maxConcurrentParts: 4,
    );
  }

  @override
  Future<FileUploadSession> createUploadSession({
    String? parentId,
    required String fileName,
    required int sizeBytes,
    String? mimeType,
    String? sha256,
    int? partSizeBytes,
    String? spaceType,
    String? asVersionOfFileId,
  }) async {
    afterCreate?.call();
    return FileUploadSession(
      id: 'session-1',
      uploadId: 'upload-1',
      parentId: parentId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      partSizeBytes: sizeBytes,
      totalParts: 1,
      mimeType: mimeType ?? 'application/octet-stream',
      status: 'UPLOADING',
      bucket: 'private',
      objectKey: 'photos/photo.jpg',
      uploadUrl: 'http://localhost/upload-1',
      parts: const <FileUploadPart>[],
      expiresAt: null,
    );
  }

  @override
  Future<String> putUploadUrl({
    required String uploadUrl,
    required Stream<List<int>> data,
    required int contentLength,
    FileUploadCancellationToken? cancellationToken,
    FileUploadProgressCallback? onProgress,
  }) async {
    afterPut?.call();
    return 'etag';
  }

  @override
  Future<FileNode> completeUploadSession({
    required String sessionId,
    String? sha256,
    String? asVersionOfFileId,
  }) async {
    completeCalled = true;
    duringComplete?.call();
    return FileNode(
      id: 'photo-id',
      parentId: 'photos',
      name: 'photo.jpg',
      isFolder: false,
      nodeType: 'FILE',
      normalizedPath: '/Photos/photo.jpg',
      sizeBytes: 4,
      updatedAt: null,
      mimeType: 'image/jpeg',
    );
  }

  @override
  Future<void> cancelUploadSession(String uploadId) async {
    cancelledUploadIds.add(uploadId);
  }
}

class _RetryingCompleteFileApi extends _PostUploadCancellationFileApi {
  int completeAttempts = 0;

  @override
  Future<FileNode> completeUploadSession({
    required String sessionId,
    String? sha256,
    String? asVersionOfFileId,
  }) async {
    completeAttempts++;
    if (completeAttempts < 3) {
      throw const AppException(
        code: '409',
        message: 'transient conflict',
        details: <String, Object?>{'retryable': true},
      );
    }
    return FileNode(
      id: 'photo-id',
      parentId: 'photos',
      name: 'photo.jpg',
      isFolder: false,
      nodeType: 'FILE',
      normalizedPath: '/Photos/photo.jpg',
      sizeBytes: 4,
      updatedAt: null,
      mimeType: 'image/jpeg',
    );
  }
}
