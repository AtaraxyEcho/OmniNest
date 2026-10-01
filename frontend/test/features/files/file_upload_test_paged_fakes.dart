part of 'file_browser_controller_upload_test.dart';

/// 上传测试 fake 仓储的分页方法集：从主测试文件拆出以满足 1200 行
/// 源码上限；各页数据取宿主字段，宿主未提供时返回空页。
mixin UploadTestPagedRepositoryFakes implements FileRepository {
  /// 宿主 fake 需提供的页数据字段与浏览错误桩。
  List<FileUploadQueueItem> get uploadQueue;
  Object? get externalBrowseError;
  List<OfflineDownloadTask> get offlineTasks;
  List<ExternalFileItem> get externalFiles;

  @override
  Future<FilesSubPage<FileUploadQueueItem>> listUploadQueuePage({
    int page = 0,
    int size = 10,
  }) async {
    return FilesSubPage(
      items: uploadQueue,
      page: page,
      size: size,
      totalElements: uploadQueue.length,
      totalPages:
          uploadQueue.isEmpty ? 0 : ((uploadQueue.length / size).ceil()),
    );
  }

  @override
  Future<FilesSubPage<OfflineDownloadTask>> listOfflineDownloadsPage({
    int page = 0,
    int size = 10,
  }) async {
    return FilesSubPage(
      items: offlineTasks,
      page: page,
      size: size,
      totalElements: offlineTasks.length,
      totalPages: offlineTasks.isEmpty ? 0 : 1,
    );
  }

  @override
  Future<FilesSubPage<ImportTask>> listImportTasksPage({
    int page = 0,
    int size = 10,
  }) async {
    return const FilesSubPage<ImportTask>(
      items: <ImportTask>[],
      page: 0,
      size: 10,
      totalElements: 0,
      totalPages: 0,
    );
  }

  @override
  Future<FilesSubPage<SharedFileItem>> listSharedWithMePage({
    int page = 0,
    int size = 10,
  }) async {
    return const FilesSubPage<SharedFileItem>(
      items: <SharedFileItem>[],
      page: 0,
      size: 10,
      totalElements: 0,
      totalPages: 0,
    );
  }

  @override
  Future<FilesSubPage<FileShareLink>> listMySharesPage({
    int page = 0,
    int size = 10,
  }) async {
    return const FilesSubPage<FileShareLink>(
      items: <FileShareLink>[],
      page: 0,
      size: 10,
      totalElements: 0,
      totalPages: 0,
    );
  }

  @override
  Future<({List<ExternalFileItem> items, FilesSubPageMeta meta})>
  browseExternalStoragePage(
    String accountId,
    String path, {
    int page = 0,
    int size = 10,
  }) async {
    if (externalBrowseError != null) {
      throw externalBrowseError!;
    }
    return (
      items: externalFiles,
      meta: FilesSubPageMeta(
        page: page,
        size: size,
        totalElements: externalFiles.length,
        totalPages: externalFiles.isEmpty ? 0 : 1,
      ),
    );
  }

  @override
  Future<FileNodePage> listRecentFilesPage({
    int page = 0,
    int size = 50,
  }) async {
    return const FileNodePage(
      items: <FileNode>[],
      page: 0,
      size: 50,
      totalElements: 0,
      totalPages: 0,
    );
  }

  @override
  Future<FileNodePage> listFavoriteFilesPage({
    int page = 0,
    int size = 50,
  }) async {
    return const FileNodePage(
      items: <FileNode>[],
      page: 0,
      size: 50,
      totalElements: 0,
      totalPages: 0,
    );
  }

  @override
  Future<FileNodePage> listRecycleBinPage({
    String spaceType = 'PERSONAL',
    int page = 0,
    int size = 50,
  }) async {
    return const FileNodePage(
      items: <FileNode>[],
      page: 0,
      size: 50,
      totalElements: 0,
      totalPages: 0,
    );
  }
}
