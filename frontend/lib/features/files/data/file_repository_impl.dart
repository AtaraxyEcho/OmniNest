import 'package:omninest/features/files/data/file_api.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/files/domain/file_upload_complete_result.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

class FileRepositoryImpl implements FileRepository {
  const FileRepositoryImpl(this.fileApi);

  final FileApi fileApi;

  @override
  Future<List<FileNode>> listFiles({String? parentId, String? category}) async {
    return fileApi.listFiles(parentId: parentId, category: category);
  }

  @override
  Future<FileNodePage> listFilesPage({
    String? parentId,
    String? category,
    int page = 0,
    int size = 100,
  }) {
    return fileApi.listFilesPage(
      parentId: parentId,
      category: category,
      page: page,
      size: size,
    );
  }

  @override
  Future<List<FileNode>> listRecycleBin({String spaceType = 'PERSONAL'}) {
    return fileApi.listRecycleBin(spaceType: spaceType);
  }

  @override
  Future<List<FileNode>> listRecentFiles() {
    return fileApi.listRecentFiles();
  }

  @override
  Future<List<FileNode>> listFavoriteFiles() {
    return fileApi.listFavoriteFiles();
  }

  @override
  Future<FileNode> createFolder({String? parentId, required String name}) {
    return fileApi.createFolder(parentId: parentId, name: name);
  }

  @override
  Future<FileNode> renameFile({required String fileId, required String name}) {
    return fileApi.renameFile(fileId: fileId, name: name);
  }

  @override
  Future<FileNode> moveFile({
    required String fileId,
    required String parentId,
  }) {
    return fileApi.moveFile(fileId: fileId, parentId: parentId);
  }

  @override
  Future<FileNode> copyFile({required String fileId, String? targetParentId}) {
    return fileApi.copyFile(fileId: fileId, targetParentId: targetParentId);
  }

  @override
  Future<List<FileVersion>> listFileVersions(String fileId) {
    return fileApi.listFileVersions(fileId);
  }

  @override
  Future<FileNode> restoreFileVersion({
    required String fileId,
    required String versionId,
  }) {
    return fileApi.restoreFileVersion(fileId: fileId, versionId: versionId);
  }

  @override
  Future<String> downloadUrl(String fileId) {
    return fileApi.downloadUrl(fileId);
  }

  @override
  Future<String> loadTextPreview(String fileId) {
    return fileApi.loadTextPreview(fileId);
  }

  @override
  Future<void> deleteFile(String fileId) {
    return fileApi.deleteFile(fileId);
  }

  @override
  Future<FileNode> restoreFile(String fileId) {
    return fileApi.restoreFile(fileId);
  }

  @override
  Future<TaskSubmission> purgeFile(String fileId) {
    return fileApi.purgeFile(fileId);
  }

  @override
  Future<FileNode> addFavorite(String fileId) {
    return fileApi.addFavorite(fileId);
  }

  @override
  Future<void> removeFavorite(String fileId) {
    return fileApi.removeFavorite(fileId);
  }

  @override
  Future<List<FileNode>> batchDeleteFiles(List<String> fileIds) {
    return fileApi.batchDeleteFiles(fileIds);
  }

  @override
  Future<List<FileNode>> batchRestoreFiles(List<String> fileIds) {
    return fileApi.batchRestoreFiles(fileIds);
  }

  @override
  Future<TaskSubmission> batchPurgeFiles(List<String> fileIds) {
    return fileApi.batchPurgeFiles(fileIds);
  }

  @override
  Future<List<FileNode>> batchMoveFiles(List<String> fileIds, String parentId) {
    return fileApi.batchMoveFiles(fileIds, parentId);
  }

  @override
  Future<List<FileNode>> batchAddFavorites(List<String> fileIds) {
    return fileApi.batchAddFavorites(fileIds);
  }

  @override
  Future<void> batchRemoveFavorites(List<String> fileIds) {
    return fileApi.batchRemoveFavorites(fileIds);
  }

  @override
  Future<List<SharedFileItem>> listSharedWithMe() {
    return fileApi.listSharedWithMe();
  }

  @override
  Future<List<FileShareLink>> listMyShares() {
    return fileApi.listMyShares();
  }

  @override
  Future<List<FileShareLink>> listShareLinks() {
    return fileApi.listShareLinks();
  }

  @override
  Future<FileShareLink> createShareLink({
    required String resourceId,
    String resourceType = 'FILE',
    String? password,
    bool generatePassword = false,
    DateTime? expiresAt,
    int? maxAccessCount,
  }) {
    return fileApi.createShareLink(
      resourceId: resourceId,
      resourceType: resourceType,
      password: password,
      generatePassword: generatePassword,
      expiresAt: expiresAt,
      maxAccessCount: maxAccessCount,
    );
  }

  @override
  Future<void> revokeShare(String shareId) {
    return fileApi.revokeShare(shareId);
  }

  @override
  Future<FileSharePreview> previewShare(String token, {String? password}) {
    return fileApi.previewShare(token, password: password);
  }

  @override
  Future<void> acceptShare(
    String token, {
    String? password,
    String? targetParentId,
  }) {
    return fileApi.acceptShare(
      token,
      password: password,
      targetParentId: targetParentId,
    );
  }

  @override
  Future<FileStorageStats> storageStats() {
    return fileApi.storageStats();
  }

  @override
  Future<FileUploadPolicy> uploadPolicy() {
    return fileApi.uploadPolicy();
  }

  @override
  Future<List<FileUploadQueueItem>> listUploadQueue() {
    return fileApi.listUploadQueue();
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
  }) {
    return fileApi.createUploadSession(
      parentId: parentId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      sha256: sha256,
      partSizeBytes: partSizeBytes,
      spaceType: spaceType,
      asVersionOfFileId: asVersionOfFileId,
    );
  }

  @override
  Future<void> completeUploadPart({
    required String uploadId,
    required int partNumber,
    required String eTag,
  }) {
    return fileApi.completeUploadPart(
      uploadId: uploadId,
      partNumber: partNumber,
      eTag: eTag,
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
    return fileApi.putUploadUrl(
      uploadUrl: uploadUrl,
      data: data,
      contentLength: contentLength,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );
  }

  @override
  Future<FileUploadCompleteResult> completeUploadSession({
    required String sessionId,
    String? sha256,
    String? asVersionOfFileId,
  }) {
    return fileApi.completeUploadSession(
      sessionId: sessionId,
      sha256: sha256,
      asVersionOfFileId: asVersionOfFileId,
    );
  }

  @override
  Future<void> cancelUploadSession(String uploadId) {
    return fileApi.cancelUploadSession(uploadId);
  }

  @override
  Future<List<OfflineDownloadTask>> listOfflineDownloads() {
    return fileApi.listOfflineDownloads();
  }

  @override
  Future<OfflineDownloadTask> createOfflineDownload({
    required String sourceUri,
    String? targetParentId,
    String? spaceType,
  }) {
    return fileApi.createOfflineDownload(
      sourceUri: sourceUri,
      targetParentId: targetParentId,
      spaceType: spaceType,
    );
  }

  @override
  Future<void> cancelOfflineDownload(String taskId) {
    return fileApi.cancelOfflineDownload(taskId);
  }

  @override
  Future<List<ExternalStorageAccount>> listExternalStorages() {
    return fileApi.listExternalStorages();
  }

  @override
  Future<ExternalStorageAccount> createExternalStorage({
    required String provider,
    required String displayName,
    required String encryptedCredentials,
  }) {
    return fileApi.createExternalStorage(
      provider: provider,
      displayName: displayName,
      encryptedCredentials: encryptedCredentials,
    );
  }

  @override
  Future<void> disableExternalStorage(String accountId) {
    return fileApi.disableExternalStorage(accountId);
  }

  @override
  Future<void> deleteExternalStorage(String accountId) {
    return fileApi.deleteExternalStorage(accountId);
  }

  @override
  Future<ExternalStorageAccount> updateExternalStorage({
    required String accountId,
    required String displayName,
    required String encryptedCredentials,
  }) {
    return fileApi.updateExternalStorage(
      accountId: accountId,
      displayName: displayName,
      encryptedCredentials: encryptedCredentials,
    );
  }

  @override
  Future<List<ExternalFileItem>> browseExternalStorage(
    String accountId,
    String path,
  ) {
    return fileApi.browseExternalStorage(accountId, path);
  }

  @override
  Future<ImportTask> createImportTask(
    String accountId, {
    required String sourcePath,
    required String sourceKind,
    String? targetParentId,
    String? spaceType,
  }) {
    return fileApi.createImportTask(
      accountId,
      sourcePath: sourcePath,
      sourceKind: sourceKind,
      targetParentId: targetParentId,
      spaceType: spaceType,
    );
  }

  @override
  Future<List<ImportTask>> listImportTasks() {
    return fileApi.listImportTasks();
  }

  @override
  Future<void> cancelImportTask(String taskId) {
    return fileApi.cancelImportTask(taskId);
  }

  @override
  Future<ExternalSpaceUsage> getExternalStorageSpace(String accountId) {
    return fileApi.getExternalStorageSpace(accountId);
  }

  @override
  Future<void> testExternalStorageConnection(String accountId) {
    return fileApi.testExternalStorageConnection(accountId);
  }

  // ============================================================
  // 共享空间相关方法
  // ============================================================

  @override
  Future<List<FileNode>> listSharedSpaceFiles({String? parentId}) {
    return fileApi.listSharedSpaceFiles(parentId: parentId);
  }

  @override
  Future<FileNodePage> listSharedSpaceFilesPage({
    String? parentId,
    int page = 0,
    int size = 100,
  }) {
    return fileApi.listSharedSpaceFilesPage(
      parentId: parentId,
      page: page,
      size: size,
    );
  }

  @override
  Future<FileNode> createSharedFolder({
    String? parentId,
    required String name,
  }) {
    return fileApi.createSharedFolder(parentId: parentId, name: name);
  }

  @override
  Future<FileNode> renameSharedFile({
    required String fileId,
    required String name,
  }) {
    return fileApi.renameSharedFile(fileId: fileId, name: name);
  }

  @override
  Future<void> moveToSharedSpace(String fileId) {
    return fileApi.moveToSharedSpace(fileId);
  }

  @override
  Future<void> moveToPersonalSpace(String fileId) {
    return fileApi.moveToPersonalSpace(fileId);
  }

  @override
  Future<void> deleteSharedFile(String fileId) {
    return fileApi.deleteSharedFile(fileId);
  }

  @override
  Future<SharedSpaceUsage> getSharedSpaceUsage() {
    return fileApi.getSharedSpaceUsage();
  }
}
