import 'dart:convert' as convert;
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/features/files/data/file_api.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_upload_complete_result.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';
import 'package:omninest/features/files/domain/upload_part_size.dart';
import 'package:omninest/features/tasks/data/task_api.dart';

/// 媒体导入进度回调。
typedef ImportProgressCallback =
    void Function(String fileName, int uploadedBytes, int totalBytes);

/// 单个媒体文件上传完成后的稳定标识。
class ImportedMediaFile {
  const ImportedMediaFile({
    required this.fileName,
    required this.fileNodeId,
    this.mediaAutoImportTaskId,
  });

  final String fileName;
  final String fileNodeId;
  final String? mediaAutoImportTaskId;
}

/// 单个未能导入的文件及其失败原因。
class MediaImportFailure {
  const MediaImportFailure({required this.fileName, required this.error});

  final String fileName;
  final Object error;
}

/// 保留逐文件结果的批量导入结果。
class MediaImportBatchResult {
  const MediaImportBatchResult({
    required this.imported,
    required this.failures,
  });

  final List<ImportedMediaFile> imported;
  final List<MediaImportFailure> failures;

  List<String> get importedNames =>
      imported.map((file) => file.fileName).toList(growable: false);
}

enum MediaImportCompletionState { completed, processing, failed }

const List<Duration> _completionConflictRetryDelays = <Duration>[
  Duration(milliseconds: 250),
  Duration(milliseconds: 600),
  Duration(milliseconds: 1200),
];

/// 媒体导入取消信号。取消会同时终止当前 HTTP 上传并清理服务端会话。
class MediaImportCancellationToken {
  final List<VoidCallback> _listeners = <VoidCallback>[];
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void addListener(VoidCallback listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const MediaImportCancelledException();
  }
}

class MediaImportCancelledException implements Exception {
  const MediaImportCancelledException();
}

/// 轻量媒体导入服务，供各子系统直接上传文件到 FileManager。
///
/// 不依赖 FileBrowserState，直接调用 FileApi 完成上传；
/// 上传受理后进入安全扫描时，等待扫描任务终态再返回稳定文件节点。
class MediaImportService {
  MediaImportService(this._fileApi, this._taskApi);

  final FileApi _fileApi;
  final TaskApi _taskApi;

  /// 查找或创建子系统默认目录，返回目录 ID。
  ///
  /// [directoryName] 目录名称（如 'Movies'、'Music'）。
  /// [spaceType] 空间类型：'PERSONAL' 或 'SHARED'。
  Future<String?> ensureDefaultDirectory({
    required String directoryName,
    String? spaceType,
  }) async {
    final isShared = spaceType == 'SHARED';

    // 查找已有目录
    final files =
        isShared
            ? await _fileApi.listSharedSpaceFiles(parentId: null)
            : await _fileApi.listFiles(parentId: null);
    for (final file in files) {
      if (file.nodeType == 'FOLDER' && file.name == directoryName) {
        return file.id;
      }
    }

    // 目录不存在，创建
    if (isShared) {
      final folder = await _fileApi.createSharedFolder(name: directoryName);
      return folder.id;
    }
    final folder = await _fileApi.createFolder(name: directoryName);
    return folder.id;
  }

  /// 上传文件列表到指定目录。
  ///
  /// 返回成功上传的文件名列表。
  Future<List<String>> importFiles({
    required List<XFile> files,
    required String parentId,
    String? spaceType,
    bool reuseExistingFiles = false,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    final result = await _performImport(
      files: files,
      parentId: parentId,
      spaceType: spaceType,
      reuseExistingFiles: reuseExistingFiles,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
    return result.importedNames;
  }

  Future<MediaImportBatchResult> importFilesDetailed({
    required List<XFile> files,
    required String parentId,
    String? spaceType,
    bool reuseExistingFiles = false,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    return _performImport(
      files: files,
      parentId: parentId,
      spaceType: spaceType,
      reuseExistingFiles: reuseExistingFiles,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
  }

  Future<MediaImportBatchResult> _performImport({
    required List<XFile> files,
    required String parentId,
    String? spaceType,
    bool reuseExistingFiles = false,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    final policy = await _fileApi.uploadPolicy();
    cancellationToken?.throwIfCancelled();
    final imported = <ImportedMediaFile>[];
    final failures = <MediaImportFailure>[];

    for (final file in files) {
      try {
        cancellationToken?.throwIfCancelled();
        final importedFile = await importFile(
          file: file,
          parentId: parentId,
          spaceType: spaceType,
          policy: policy,
          reuseExistingFiles: reuseExistingFiles,
          onProgress: onProgress,
          cancellationToken: cancellationToken,
        );
        imported.add(importedFile);
      } on MediaImportCancelledException {
        rethrow;
      } on Object catch (error) {
        failures.add(MediaImportFailure(fileName: file.name, error: error));
        if (kDebugMode) {
          debugPrint('媒体文件导入失败: file=${file.name}, error=$error');
        }
      }
    }
    final result = MediaImportBatchResult(
      imported: imported,
      failures: failures,
    );
    return result;
  }

  /// 上传一个文件并直接返回后端创建或复用的文件节点，避免再按文件名轮询。
  Future<ImportedMediaFile> importFile({
    required XFile file,
    required String parentId,
    String? spaceType,
    FileUploadPolicy? policy,
    required bool reuseExistingFiles,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final sizeBytes = await file.length();
    cancellationToken?.throwIfCancelled();
    final fileName = file.name.isNotEmpty ? file.name : '未命名文件';
    final mimeType = file.mimeType ?? 'application/octet-stream';

    final effectivePolicy = policy ?? await _fileApi.uploadPolicy();
    cancellationToken?.throwIfCancelled();
    final needsMultipart = sizeBytes > effectivePolicy.directUploadMaxBytes;
    final partSizeBytes =
        needsMultipart
            ? calculatePartSizeBytes(
              fileSizeBytes: sizeBytes,
              defaultPartSizeBytes: effectivePolicy.defaultPartSizeBytes,
              maxPartSizeBytes: effectivePolicy.maxPartSizeBytes,
              maxTotalParts: effectivePolicy.maxTotalParts,
            )
            : null;

    FileUploadSession? session;
    try {
      session = await _fileApi.createUploadSession(
        parentId: parentId,
        fileName: fileName,
        sizeBytes: sizeBytes,
        mimeType: mimeType,
        partSizeBytes: partSizeBytes,
        spaceType: spaceType,
      );
      cancellationToken?.throwIfCancelled();
    } on MediaImportCancelledException {
      final createdSession = session;
      if (createdSession != null) {
        await _cancelUploadSession(createdSession.uploadId);
      }
      rethrow;
    } on AppException catch (error) {
      final reusedFile =
          reuseExistingFiles
              ? await _reuseExistingFile(
                error: error,
                fileName: fileName,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                onProgress: onProgress,
                cancellationToken: cancellationToken,
              )
              : null;
      if (reusedFile != null) {
        return reusedFile;
      }
      rethrow;
    }

    final uploadSession = session;

    final uploadCancellation = FileUploadCancellationToken();
    final cancelUpload = uploadCancellation.cancel;
    cancellationToken?.addListener(cancelUpload);
    try {
      cancellationToken?.throwIfCancelled();
      final result =
          uploadSession.isDirectUpload
              ? await _runDirectUpload(
                file,
                uploadSession,
                sizeBytes,
                onProgress,
                uploadCancellation,
                cancellationToken,
              )
              : await _runMultipartUpload(
                file,
                uploadSession,
                sizeBytes,
                onProgress,
                uploadCancellation,
                cancellationToken,
              );
      final promoted = await _waitForPromotion(
        result,
        fileName: fileName,
        parentId: parentId,
      );
      return ImportedMediaFile(
        fileName: fileName,
        fileNodeId: promoted.fileNodeId,
        mediaAutoImportTaskId: promoted.mediaAutoImportTaskId,
      );
    } on Object {
      if (cancellationToken?.isCancelled ?? false) {
        await _cancelUploadSession(uploadSession.uploadId);
        throw const MediaImportCancelledException();
      }
      rethrow;
    } finally {
      cancellationToken?.removeListener(cancelUpload);
    }
  }

  Future<ImportedMediaFile?> _reuseExistingFile({
    required AppException error,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
    ImportProgressCallback? onProgress,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    if (error.code != '409') {
      return null;
    }
    final details = error.details;
    final existingFileId = details['existingFileId']?.toString();
    final softDeletedFileId = details['softDeletedFileId']?.toString();
    final fileId = existingFileId ?? softDeletedFileId;
    if (fileId == null || fileId.isEmpty) {
      return null;
    }
    final existingSize = _asInt(details['sizeBytes']);
    if (existingSize == null || existingSize != sizeBytes) {
      return null;
    }
    final existingMimeType = details['mimeType']?.toString();
    if (mimeType != 'application/octet-stream' &&
        existingMimeType != null &&
        existingMimeType.isNotEmpty &&
        existingMimeType != mimeType) {
      return null;
    }

    cancellationToken?.throwIfCancelled();
    onProgress?.call(fileName, 0, sizeBytes);
    if (softDeletedFileId != null) {
      await _fileApi.restoreFile(softDeletedFileId);
      cancellationToken?.throwIfCancelled();
    }
    final reprocessed = await _fileApi.reprocessFile(fileId);
    cancellationToken?.throwIfCancelled();
    onProgress?.call(fileName, sizeBytes, sizeBytes);
    return ImportedMediaFile(
      fileName: fileName,
      fileNodeId: reprocessed.id,
      mediaAutoImportTaskId: reprocessed.mediaAutoImportTaskId,
    );
  }

  int? _asInt(Object? value) {
    return switch (value) {
      final int number => number,
      final num number => number.toInt(),
      final String text => int.tryParse(text),
      _ => null,
    };
  }

  Future<FileUploadCompleteResult> _runDirectUpload(
    XFile file,
    FileUploadSession session,
    int sizeBytes,
    ImportProgressCallback? onProgress,
    FileUploadCancellationToken cancellationToken,
    MediaImportCancellationToken? mediaCancellationToken,
  ) async {
    final uploadUrl = session.uploadUrl;
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw const AppException(
        code: AppErrorCodes.uploadUrlMissing,
        message: AppErrorCodes.uploadUrlMissing,
      );
    }
    onProgress?.call(file.name, 0, sizeBytes);
    await _fileApi.putUploadUrl(
      uploadUrl: uploadUrl,
      data: file.openRead(),
      contentLength: sizeBytes,
      cancellationToken: cancellationToken,
    );
    mediaCancellationToken?.throwIfCancelled();
    final result = await _completeUploadSessionWithRetry(
      sessionId: session.uploadId,
      cancellationToken: mediaCancellationToken,
    );
    onProgress?.call(file.name, sizeBytes, sizeBytes);
    return result;
  }

  Future<FileUploadCompleteResult> _runMultipartUpload(
    XFile file,
    FileUploadSession session,
    int sizeBytes,
    ImportProgressCallback? onProgress,
    FileUploadCancellationToken uploadCancellation,
    MediaImportCancellationToken? cancellationToken,
  ) async {
    var uploadedBytes = 0;
    for (final part in session.parts) {
      cancellationToken?.throwIfCancelled();
      final start = (part.partNumber - 1) * session.partSizeBytes;
      final end = math.min(start + part.sizeBytes, sizeBytes);
      final uploadUrl = part.uploadUrl;
      if (uploadUrl == null || uploadUrl.isEmpty) {
        throw AppException(
          code: AppErrorCodes.uploadUrlMissing,
          message: '${AppErrorCodes.uploadUrlMissing}:${part.partNumber}',
        );
      }
      final eTag = await _fileApi.putUploadUrl(
        uploadUrl: uploadUrl,
        data: file.openRead(start, end),
        contentLength: part.sizeBytes,
        cancellationToken: uploadCancellation,
      );
      cancellationToken?.throwIfCancelled();
      await _fileApi.completeUploadPart(
        uploadId: session.uploadId,
        partNumber: part.partNumber,
        eTag: eTag,
      );
      cancellationToken?.throwIfCancelled();
      uploadedBytes += part.sizeBytes;
      onProgress?.call(file.name, uploadedBytes, sizeBytes);
    }
    cancellationToken?.throwIfCancelled();
    return _completeUploadSessionWithRetry(
      sessionId: session.uploadId,
      cancellationToken: cancellationToken,
    );
  }

  Future<FileUploadCompleteResult> _completeUploadSessionWithRetry({
    required String sessionId,
    MediaImportCancellationToken? cancellationToken,
  }) async {
    var retryIndex = 0;
    while (true) {
      cancellationToken?.throwIfCancelled();
      try {
        return await _fileApi.completeUploadSession(sessionId: sessionId);
      } on AppException catch (error) {
        if (error.code != '409' ||
            retryIndex >= _completionConflictRetryDelays.length) {
          rethrow;
        }
        await Future<void>.delayed(_completionConflictRetryDelays[retryIndex]);
        retryIndex++;
        cancellationToken?.throwIfCancelled();
      }
    }
  }

  /// 等待安全扫描晋升完成，返回稳定的文件节点与媒体导入任务标识。
  Future<({String fileNodeId, String? mediaAutoImportTaskId})>
  _waitForPromotion(
    FileUploadCompleteResult result, {
    required String fileName,
    required String? parentId,
  }) async {
    if (!result.isScanning) {
      final fileNodeId = result.fileNodeId;
      if (fileNodeId == null || fileNodeId.isEmpty) {
        throw const AppException(
          code: AppErrorCodes.securityScanFailed,
          message: '安全扫描未完成，文件已保留；请稍后在书库查看或重新导入',
        );
      }
      return (fileNodeId: fileNodeId, mediaAutoImportTaskId: null);
    }
    final taskId = result.taskId;
    if (taskId == null || taskId.isEmpty) {
      throw const AppException(
        code: AppErrorCodes.securityScanFailed,
        message: '安全扫描未完成，文件已保留；请稍后在书库查看或重新导入',
      );
    }
    // 扫描时限护栏 30 分钟 + 重试窗口，超时按扫描失败处理。
    final task = await _taskApi.waitForTerminal(
      taskId,
      timeout: const Duration(minutes: 90),
      interval: const Duration(seconds: 3),
    );
    if (kDebugMode) {
      debugPrint(
        'MediaImport: scan task terminal — taskId=$taskId, '
        'status=${task.status}, hasResult=${task.result != null}',
      );
    }
    if (task.status != 'COMPLETED') {
      final detail = task.errorMessage ?? '';
      throw AppException(
        code: AppErrorCodes.securityScanFailed,
        message:
            '安全扫描未完成，文件已保留；请稍后在书库查看或重新导入'
            '${detail.isEmpty ? '' : '（$detail）'}',
      );
    }
    final payload =
        task.result == null
            ? const <String, dynamic>{}
            : (convert.jsonDecode(task.result!) as Map<String, dynamic>);
    final fileNodeId = payload['fileNodeId']?.toString();
    if (fileNodeId != null && fileNodeId.isNotEmpty) {
      return (
        fileNodeId: fileNodeId,
        mediaAutoImportTaskId: payload['mediaAutoImportTaskId']?.toString(),
      );
    }
    // 旧版本后端的任务结果不含晋升产物标识，按文件名回退解析。
    if (kDebugMode) {
      debugPrint(
        'MediaImport: scan task result missing fileNodeId, '
        'falling back to directory lookup for $fileName',
      );
    }
    final resolved = await findImportedNode(
      parentId: parentId,
      fileName: fileName,
      timeout: const Duration(minutes: 2),
    );
    if (resolved == null) {
      if (kDebugMode) {
        debugPrint(
          'MediaImport: promoted node not found in parent directory — '
          'fileName=$fileName, parentId=$parentId',
        );
      }
      throw AppException(
        code: AppErrorCodes.securityScanFailed,
        message: '安全扫描已完成但未能定位文件「$fileName」；请刷新书库查看或重新导入',
      );
    }
    return (fileNodeId: resolved, mediaAutoImportTaskId: null);
  }

  /// 在目标目录按文件名轮询查找晋升后的文件节点。
  ///
  /// 供导入队列在扫描等待异常时自愈：后端晋升与自动导入链完成即能找回。
  Future<String?> findImportedNode({
    required String? parentId,
    required String fileName,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final nodes = await _fileApi.listFiles(parentId: parentId);
        for (final node in nodes) {
          if (!node.isFolder && node.name == fileName) {
            return node.id;
          }
        }
      } on AppException {
        // 列表查询失败按未找到处理，继续下一轮。
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return null;
  }

  Future<void> _cancelUploadSession(String uploadId) async {
    try {
      await _fileApi.cancelUploadSession(uploadId);
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint('取消媒体上传会话失败: uploadId=$uploadId, error=$error');
      }
    }
  }
}
