part of 'file_browser_controller_upload_test.dart';

/// 上传/回收站/批量操作测试的 fake 仓储实现：从主测试文件拆出以满足
/// 1200 行源码上限；分页行为由 UploadTestPagedRepositoryFakes 提供。
class _FakeFileRepository
    with UploadTestPagedRepositoryFakes
    implements FileRepository {
  @override
  Future<FileMediaInfo> mediaInfo(String fileId) async => const FileMediaInfo();
  @override
  List<FileUploadQueueItem> uploadQueue = const [];
  List<ExternalStorageAccount> externalAccounts = const [];
  @override
  List<ExternalFileItem> externalFiles = const [];
  List<FileNode> recycleBin = const [];
  final purgedFileIds = <String>[];
  final batchPurgedFileIds = <String>[];
  final uploadedPartUrls = <String>[];
  final completedPartNumbers = <int>[];
  final completedSessions = <String>[];
  final cancelledUploadSessions = <String>[];
  final deletedFileIds = <String>[];
  final deletedSharedFileIds = <String>[];
  final createdSharedFolderNames = <String>[];
  final renamedSharedFileIds = <String>[];

  final sharedFilesByParent = <String?, List<FileNode>>{};
  final sharedParentRequests = <String?>[];
  final personalFilesByPage = <int, List<FileNode>>{};
  final personalPageRequests = <int>[];
  final firstUploadStarted = Completer<void>();
  final secondUploadStarted = Completer<void>();
  final firstUploadResult = Completer<String>();
  final secondUploadResult = Completer<String>();
  final List<Completer<String>> uploadResults = <Completer<String>>[];
  Completer<void>? deleteFileCompleter;
  Completer<List<ExternalFileItem>>? externalBrowseCompleter;
  Object? deleteFileError;
  @override
  Object? externalBrowseError;

  @override
  Future<List<FileNode>> listFiles({
    String? parentId,
    String? category,
  }) async => const [];

  @override
  Future<FileNodePage> listFilesPage({
    String? parentId,
    String? category,
    int page = 0,
    int size = 10,
  }) async {
    personalPageRequests.add(page);
    final files = personalFilesByPage[page] ?? const [];
    final totalElements =
        personalFilesByPage.values
            .expand((items) => items)
            .map((file) => file.id)
            .toSet()
            .length;
    return FileNodePage(
      items: files,
      page: page,
      size: size,
      totalElements: totalElements,
      totalPages: personalFilesByPage.isEmpty ? 0 : personalFilesByPage.length,
    );
  }

  @override
  Future<FileStorageStats> storageStats() async => const FileStorageStats(
    totalFiles: 0,
    totalFolders: 0,
    usedBytes: 0,
    quotaStatus: 'NORMAL',
    quotaBytes: 1024,
    typeDistribution: [],
  );

  @override
  Future<List<FileUploadQueueItem>> listUploadQueue() async => uploadQueue;

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
    return const FileUploadSession(
      id: 'session-id',
      uploadId: 'upload-123',
      parentId: null,
      fileName: 'large.bin',
      sizeBytes: 6,
      partSizeBytes: 3,
      totalParts: 2,
      mimeType: 'application/octet-stream',
      status: 'CREATED',
      bucket: 'files',
      objectKey: 'users/1/large.bin',
      uploadUrl: 'http://minio/part-1',
      parts: [
        FileUploadPart(
          partNumber: 1,
          sizeBytes: 3,
          status: 'PENDING',
          uploadUrl: 'http://minio/part-1',
        ),
        FileUploadPart(
          partNumber: 2,
          sizeBytes: 3,
          status: 'PENDING',
          uploadUrl: 'http://minio/part-2',
        ),
      ],
      expiresAt: null,
    );
  }

  @override
  Future<String> getUploadPartUrl({
    required String uploadId,
    required int partNumber,
  }) async => 'https://storage.test/$uploadId/part-$partNumber';

  @override
  Future<String> putUploadUrl({
    required String uploadUrl,
    required Stream<List<int>> data,
    required int contentLength,
    FileUploadCancellationToken? cancellationToken,
    FileUploadProgressCallback? onProgress,
  }) {
    uploadedPartUrls.add(uploadUrl);
    final index = uploadedPartUrls.length - 1;
    final Completer<String> result;
    if (index == 0) {
      result = firstUploadResult;
      firstUploadStarted.complete();
    } else if (index == 1) {
      result = secondUploadResult;
      secondUploadStarted.complete();
    } else {
      result = Completer<String>();
    }
    uploadResults.add(result);
    return _honorCancellation(result.future, cancellationToken);
  }

  Future<String> _honorCancellation(
    Future<String> base,
    FileUploadCancellationToken? token,
  ) {
    if (token == null) {
      return base;
    }
    final cancelled = Completer<String>();
    token.addListener(() {
      if (!cancelled.isCompleted) {
        cancelled.completeError(
          const AppException(code: 'UPLOAD_CANCELLED', message: 'cancelled'),
        );
      }
    });
    base.then(
      (value) {
        if (!cancelled.isCompleted) {
          cancelled.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!cancelled.isCompleted) {
          cancelled.completeError(error, stackTrace);
        }
      },
    );
    return cancelled.future;
  }

  /// 等待第 [count] 次分片上传请求进入仓储。
  Future<void> waitForUploadCount(int count) async {
    while (uploadedPartUrls.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// 完成指定序号的分片上传请求。
  void completeUploadAt(int index, String eTag) {
    if (!uploadResults[index].isCompleted) {
      uploadResults[index].complete(eTag);
    }
  }

  @override
  Future<void> completeUploadPart({
    required String uploadId,
    required int partNumber,
    required String eTag,
  }) async {
    completedPartNumbers.add(partNumber);
  }

  @override
  Future<FileUploadCompleteResult> completeUploadSession({
    required String sessionId,
    String? sha256,
    String? asVersionOfFileId,
  }) async {
    completedSessions.add(sessionId);
    return const FileUploadCompleteResult(
      uploadId: 'upload-1',
      status: 'SCANNING',
    );
  }

  @override
  Future<void> cancelUploadSession(String uploadId) async {
    cancelledUploadSessions.add(uploadId);
    uploadQueue =
        uploadQueue.where((item) => item.uploadId != uploadId).toList();
  }

  @override
  Future<FileNode> addFavorite(String fileId) => throw UnimplementedError();

  @override
  Future<ExternalStorageAccount> createExternalStorage({
    required String provider,
    required String displayName,
    required String encryptedCredentials,
  }) => throw UnimplementedError();

  @override
  Future<FileNode> createFolder({String? parentId, required String name}) =>
      throw UnimplementedError();

  @override
  Future<void> testExternalStorageConnection(String accountId) =>
      throw UnimplementedError();

  @override
  Future<String> startExternalOAuth({
    required String connectorCode,
    required String accountId,
  }) async => 'https://example.com/oauth';

  @override
  Future<FileShareLink> createShareLink({
    required String resourceId,
    String resourceType = 'FILE',
    String? password,
    bool generatePassword = false,
    DateTime? expiresAt,
    int? maxAccessCount,
  }) => throw UnimplementedError();

  @override
  Future<FileShareLink> updateShareLink({
    required String shareId,
    String? password,
    String? expiresAt,
    int? maxAccessCount,
  }) => throw UnimplementedError();

  @override
  Future<FileSharePreview> previewShare(String token, {String? password}) =>
      throw UnimplementedError();

  @override
  Future<void> acceptShare(
    String token, {
    String? password,
    String? targetParentId,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteFile(String fileId) async {
    deletedFileIds.add(fileId);
    final error = deleteFileError;
    if (error != null) {
      throw error;
    }
    final completer = deleteFileCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<FileNode> moveFile({
    required String fileId,
    required String parentId,
  }) => throw UnimplementedError();

  @override
  Future<FileNode> copyFile({required String fileId, String? targetParentId}) =>
      throw UnimplementedError();

  @override
  Future<List<FileVersion>> listFileVersions(String fileId) =>
      throw UnimplementedError();

  @override
  Future<FileNode> restoreFileVersion({
    required String fileId,
    required String versionId,
  }) => throw UnimplementedError();

  @override
  Future<String> downloadUrl(String fileId) => throw UnimplementedError();

  @override
  Future<String> loadTextPreview(String fileId) => throw UnimplementedError();

  @override
  Future<void> disableExternalStorage(String accountId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteExternalStorage(String accountId) =>
      throw UnimplementedError();

  @override
  Future<ExternalStorageAccount> updateExternalStorage({
    required String accountId,
    required String displayName,
    required String encryptedCredentials,
  }) => throw UnimplementedError();

  @override
  Future<List<ExternalStorageAccount>> listExternalStorages() =>
      Future.value(externalAccounts);

  @override
  Future<List<ExternalStorageConnector>> listExternalConnectors() async =>
      const [];

  @override
  Future<List<FileNode>> listFavoriteFiles() => throw UnimplementedError();

  @override
  Future<List<FileShareLink>> listMyShares() => throw UnimplementedError();

  @override
  Future<List<FileNode>> listRecentFiles() => throw UnimplementedError();

  @override
  Future<List<FileNode>> listRecycleBin({
    String spaceType = 'PERSONAL',
  }) async => recycleBin;

  @override
  Future<List<SharedFileItem>> listSharedWithMe() => throw UnimplementedError();

  @override
  Future<FilesSubPage<ShareChild>> listSharedFolderChildren({
    required String shareId,
    String? parentId,
    int page = 0,
    int size = 50,
  }) => throw UnimplementedError();

  @override
  Future<TaskSubmission> purgeFile(String fileId) async {
    purgedFileIds.add(fileId);
    return const TaskSubmission(taskId: 'purge-task', status: 'QUEUED');
  }

  @override
  Future<void> removeFavorite(String fileId) => throw UnimplementedError();

  @override
  Future<FileNode> renameFile({required String fileId, required String name}) =>
      throw UnimplementedError();

  @override
  Future<FileNode> restoreFile(String fileId) => throw UnimplementedError();

  @override
  Future<void> revokeShare(String shareId) => throw UnimplementedError();

  @override
  Future<FileUploadPolicy> uploadPolicy() async => const FileUploadPolicy(
    directUploadMaxBytes: 64 * 1024 * 1024,
    defaultPartSizeBytes: 10 * 1024 * 1024,
    maxPartSizeBytes: 100 * 1024 * 1024,
    maxTotalParts: 1000,
    maxConcurrentParts: 4,
  );

  @override
  Future<List<ExternalFileItem>> browseExternalStorage(
    String accountId,
    String path,
  ) async {
    final error = externalBrowseError;
    if (error != null) {
      throw error;
    }
    final completer = externalBrowseCompleter;
    if (completer != null) {
      return completer.future;
    }
    return externalFiles;
  }

  @override
  Future<ImportTask> createImportTask(
    String accountId, {
    required String sourcePath,
    required String sourceKind,
    String? targetParentId,
    String? spaceType,
    String? asVersionOfFileId,
  }) => throw UnimplementedError();

  @override
  Future<List<ImportTask>> listImportTasks() => throw UnimplementedError();

  @override
  Future<void> cancelImportTask(String taskId) => throw UnimplementedError();

  @override
  Future<List<FileNode>> batchDeleteFiles(List<String> fileIds) =>
      throw UnimplementedError();

  @override
  Future<List<FileNode>> batchRestoreFiles(List<String> fileIds) =>
      throw UnimplementedError();

  @override
  Future<TaskSubmission> batchPurgeFiles(List<String> fileIds) async {
    batchPurgedFileIds.addAll(fileIds);
    return const TaskSubmission(taskId: 'purge-batch-task', status: 'QUEUED');
  }

  @override
  Future<List<FileNode>> batchMoveFiles(
    List<String> fileIds,
    String parentId,
  ) => throw UnimplementedError();

  @override
  Future<List<FileNode>> batchAddFavorites(List<String> fileIds) =>
      throw UnimplementedError();

  @override
  Future<void> batchRemoveFavorites(List<String> fileIds) =>
      throw UnimplementedError();

  @override
  Future<ExternalSpaceUsage> getExternalStorageSpace(String accountId) =>
      Future.value(
        const ExternalSpaceUsage(
          totalBytes: 100,
          usedBytes: 25,
          freeBytes: 75,
          trashedBytes: 0,
        ),
      );

  // 共享空间相关方法
  @override
  Future<List<FileNode>> listSharedSpaceFiles({String? parentId}) async {
    sharedParentRequests.add(parentId);
    return sharedFilesByParent[parentId] ?? const [];
  }

  @override
  Future<FileNodePage> listSharedSpaceFilesPage({
    String? parentId,
    int page = 0,
    int size = 10,
  }) async {
    sharedParentRequests.add(parentId);
    final files = sharedFilesByParent[parentId] ?? const [];
    return FileNodePage(
      items: files,
      page: page,
      size: size,
      totalElements: files.length,
      totalPages: files.isEmpty ? 0 : 1,
    );
  }

  @override
  Future<FileNode> createSharedFolder({
    String? parentId,
    required String name,
  }) async {
    createdSharedFolderNames.add(name);
    return _folderNode('created-shared-folder', name);
  }

  @override
  Future<FileNode> renameSharedFile({
    required String fileId,
    required String name,
  }) async {
    renamedSharedFileIds.add(fileId);
    return _fileNode(fileId, name);
  }

  @override
  Future<void> moveToSharedSpace(String fileId) => throw UnimplementedError();

  @override
  Future<void> moveToPersonalSpace(String fileId) => throw UnimplementedError();

  @override
  Future<void> deleteSharedFile(String fileId) async {
    deletedSharedFileIds.add(fileId);
  }

  @override
  Future<SharedSpaceUsage> getSharedSpaceUsage() async =>
      const SharedSpaceUsage(usedBytes: 0, maxBytes: -1, fileCount: 0);
}

/// 分页回收站 fake：变更后刷新必须继续走分页接口并同步 meta，
/// 不得回退到全量 listRecycleBin。
class _RecyclePagedRepository extends _FakeFileRepository {
  final recyclePages = <int, List<FileNode>>{};
  final recyclePageRequests = <int>[];
  int recycleFullListRequests = 0;
  int totalElements = 0;

  @override
  Future<FileNodePage> listRecycleBinPage({
    String spaceType = 'PERSONAL',
    int page = 0,
    int size = 50,
  }) async {
    recyclePageRequests.add(page);
    return FileNodePage(
      items: recyclePages[page] ?? const [],
      page: page,
      size: size,
      totalElements: totalElements,
      totalPages: recyclePages.length,
    );
  }

  @override
  Future<List<FileNode>> listRecycleBin({String spaceType = 'PERSONAL'}) async {
    recycleFullListRequests += 1;
    return recyclePages.values.expand((items) => items).toList();
  }
}

class _BatchFileRepository extends _FakeFileRepository {
  final List<String> directUploadNames = [];
  int _uploadCallCount = 0;

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
      id: 'session-$fileName',
      uploadId: 'upload-$fileName',
      parentId: parentId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      partSizeBytes: sizeBytes,
      totalParts: 1,
      mimeType: mimeType ?? 'application/octet-stream',
      status: 'CREATED',
      bucket: 'files',
      objectKey: 'users/1/$fileName',
      uploadUrl: 'http://upload/$fileName',
      parts: const [],
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
    final fileName = Uri.parse(uploadUrl).pathSegments.last;
    directUploadNames.add(fileName);
    _uploadCallCount += 1;
    if (_uploadCallCount == 1) {
      throw StateError('upload failed');
    }
    onProgress?.call(contentLength, contentLength);
    return 'etag-$fileName';
  }
}

FileNode _folderNode(String id, String name) {
  return FileNode(
    id: id,
    parentId: null,
    name: name,
    isFolder: true,
    nodeType: 'FOLDER',
    normalizedPath: '/$name',
    sizeBytes: 0,
    updatedAt: DateTime.parse('2026-05-21T12:00:00Z'),
  );
}

FileNode _fileNode(String id, String name) {
  return FileNode(
    id: id,
    parentId: null,
    name: name,
    isFolder: false,
    nodeType: 'FILE',
    normalizedPath: '/$name',
    mimeType: 'application/octet-stream',
    sizeBytes: 6,
    updatedAt: DateTime.parse('2026-05-21T12:00:00Z'),
  );
}
