import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';

abstract interface class FileRepository {
  Future<List<FileNode>> listFiles({String? parentId, String? category});

  Future<FileNodePage> listFilesPage({
    String? parentId,
    String? category,
    int page = 0,
    int size = 100,
  });

  Future<List<FileNode>> listRecycleBin({String spaceType = 'PERSONAL'});

  Future<List<FileNode>> listRecentFiles();

  Future<List<FileNode>> listFavoriteFiles();

  Future<FileNode> createFolder({String? parentId, required String name});

  Future<FileNode> renameFile({required String fileId, required String name});

  Future<FileNode> moveFile({required String fileId, required String parentId});

  /// 复制文件节点到目标目录（null 表示根目录）。
  Future<FileNode> copyFile({required String fileId, String? targetParentId});

  /// 查询文件版本历史。
  Future<List<FileVersion>> listFileVersions(String fileId);

  /// 恢复历史版本为当前内容。
  Future<FileNode> restoreFileVersion({
    required String fileId,
    required String versionId,
  });

  Future<String> downloadUrl(String fileId);

  Future<String> loadTextPreview(String fileId);

  Future<void> deleteFile(String fileId);

  Future<FileNode> restoreFile(String fileId);

  Future<void> purgeFile(String fileId);

  Future<FileNode> addFavorite(String fileId);

  Future<void> removeFavorite(String fileId);

  Future<List<FileNode>> batchDeleteFiles(List<String> fileIds);

  Future<List<FileNode>> batchRestoreFiles(List<String> fileIds);

  Future<void> batchPurgeFiles(List<String> fileIds);

  Future<List<FileNode>> batchMoveFiles(List<String> fileIds, String parentId);

  Future<List<FileNode>> batchAddFavorites(List<String> fileIds);

  Future<void> batchRemoveFavorites(List<String> fileIds);

  Future<List<SharedFileItem>> listSharedWithMe();

  Future<List<FileShareLink>> listMyShares();

  Future<List<FileShareLink>> listShareLinks();

  Future<FileShareLink> createShareLink({
    required String resourceId,
    String resourceType,
    String? password,
    bool generatePassword,
    DateTime? expiresAt,
    int? maxAccessCount,
  });

  Future<void> revokeShare(String shareId);

  Future<FileSharePreview> previewShare(String token, {String? password});

  Future<void> acceptShare(
    String token, {
    String? password,
    String? targetParentId,
  });

  Future<FileStorageStats> storageStats();

  Future<FileUploadPolicy> uploadPolicy();

  Future<List<FileUploadQueueItem>> listUploadQueue();

  Future<FileUploadSession> createUploadSession({
    String? parentId,
    required String fileName,
    required int sizeBytes,
    String? mimeType,
    String? sha256,
    int? partSizeBytes,
    String? spaceType,
    String? asVersionOfFileId,
  });

  Future<void> completeUploadPart({
    required String uploadId,
    required int partNumber,
    required String eTag,
  });

  Future<String> putUploadUrl({
    required String uploadUrl,
    required Stream<List<int>> data,
    required int contentLength,
    FileUploadCancellationToken? cancellationToken,
    FileUploadProgressCallback? onProgress,
  });

  Future<FileNode> completeUploadSession({
    required String sessionId,
    String? sha256,
    String? asVersionOfFileId,
  });

  Future<void> cancelUploadSession(String uploadId);

  Future<List<OfflineDownloadTask>> listOfflineDownloads();

  Future<OfflineDownloadTask> createOfflineDownload({
    required String sourceUri,
    String? targetParentId,
  });

  Future<void> cancelOfflineDownload(String taskId);

  Future<List<ExternalStorageAccount>> listExternalStorages();

  Future<ExternalStorageAccount> createExternalStorage({
    required String provider,
    required String displayName,
    required String encryptedCredentials,
  });

  Future<void> disableExternalStorage(String accountId);

  Future<void> deleteExternalStorage(String accountId);

  Future<ExternalStorageAccount> updateExternalStorage({
    required String accountId,
    required String displayName,
    required String encryptedCredentials,
  });

  Future<List<ExternalFileItem>> browseExternalStorage(
    String accountId,
    String path,
  );

  Future<ImportTask> createImportTask(
    String accountId, {
    required String sourcePath,
    required String sourceKind,
    String? targetParentId,
    String? spaceType,
  });

  Future<List<ImportTask>> listImportTasks();

  Future<void> cancelImportTask(String taskId);

  /// 获取外部存储空间用量
  Future<ExternalSpaceUsage> getExternalStorageSpace(String accountId);

  /// 创建远程目录
  Future<void> mkdirExternalStorage(String accountId, String remotePath);

  /// 删除远程文件
  Future<void> deleteExternalFile(String accountId, String remotePath);

  /// 重命名远程文件
  Future<void> renameExternalFile(
    String accountId, {
    required String oldPath,
    required String newName,
  });

  // ============================================================
  // 共享空间相关方法
  // ============================================================

  /// 浏览共享空间目录
  Future<List<FileNode>> listSharedSpaceFiles({String? parentId});

  Future<FileNodePage> listSharedSpaceFilesPage({
    String? parentId,
    int page = 0,
    int size = 100,
  });

  /// 在共享空间创建文件夹
  Future<FileNode> createSharedFolder({String? parentId, required String name});

  Future<FileNode> renameSharedFile({
    required String fileId,
    required String name,
  });

  /// 移动文件到共享空间
  Future<void> moveToSharedSpace(String fileId);

  /// 从共享空间移回个人空间
  Future<void> moveToPersonalSpace(String fileId);

  /// 删除共享空间文件
  Future<void> deleteSharedFile(String fileId);

  /// 获取共享空间使用情况
  Future<SharedSpaceUsage> getSharedSpaceUsage();
}
