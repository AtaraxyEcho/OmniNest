part of 'photo_controller.dart';

/// 照片中心的选择、批量、编辑、分享与 AI 命令。
mixin PhotoCenterControllerCommands on AsyncNotifier<PhotoCenterState> {
  PhotoRepository get _repo;

  Future<void> refresh();

  void _setError(String message);

  /// 切换选择模式
  void toggleSelectionMode() {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        isSelectionMode: !current.isSelectionMode,
        selectedPhotoIds:
            current.isSelectionMode ? const {} : current.selectedPhotoIds,
      ),
    );
  }

  /// 切换照片选中状态
  void togglePhotoSelection(String photoId) {
    final current = state.asData?.value;
    if (current == null) return;
    final ids = Set<String>.from(current.selectedPhotoIds);
    if (ids.contains(photoId)) {
      ids.remove(photoId);
    } else {
      ids.add(photoId);
    }
    state = AsyncData(current.copyWith(selectedPhotoIds: ids));
  }

  /// 创建批量任务
  Future<PhotoBatchTask> createBatchTask({
    required String taskType,
    Map<String, dynamic>? params,
  }) async {
    final current = state.asData?.value;
    if (current == null) {
      throw StateError('状态未初始化');
    }
    return _repo.createBatchTask(
      taskType: taskType,
      photoIds: current.selectedPhotoIds.toList(),
      params: params,
    );
  }

  /// 分页获取相册内照片。
  Future<PhotoPage> listAlbumPhotos({
    required String albumId,
    int page = 0,
    int size = 50,
  }) => _repo.listAlbumPhotos(albumId: albumId, page: page, size: size);

  /// 添加标签
  Future<void> addTag(String photoId, String tag) async {
    try {
      await _repo.addTag(photoId, tag);
      await refresh();
      ref.invalidate(photoTagsProvider);
      ref.invalidate(photoDetailProvider(photoId));
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 移除标签
  Future<void> removeTag(String photoId, String tag) async {
    try {
      await _repo.removeTag(photoId, tag);
      await refresh();
      ref.invalidate(photoTagsProvider);
      ref.invalidate(photoDetailProvider(photoId));
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 查询所有标签
  Future<List<String>> listTags() => _repo.listTags();

  /// 查询批量任务状态
  Future<PhotoBatchTask> getBatchTask(String taskId) =>
      _repo.getBatchTask(taskId);

  /// 获取照片批量 ZIP 的下载票据。
  Future<PhotoBatchDownloadTicket> getBatchDownloadTicket(String taskId) =>
      _repo.getBatchDownloadTicket(taskId);

  /// 续传并保存照片批量 ZIP。
  Future<void> downloadBatchArchive(
    PhotoBatchDownloadTicket ticket,
    String destinationPath,
  ) => _repo.downloadBatchArchive(ticket, destinationPath);

  /// 弹出系统保存对话框并下载批量 ZIP 到所选位置。
  ///
  /// 返回保存路径；用户取消选择时返回 null。
  Future<String?> saveBatchArchiveToDisk(
    PhotoBatchDownloadTicket ticket,
  ) async {
    final location = await getSaveLocation(suggestedName: ticket.fileName);
    if (location == null) {
      return null;
    }
    await _repo.downloadBatchArchive(ticket, location.path);
    return location.path;
  }

  /// 弹出系统保存对话框并下载单张照片原片到所选位置。
  ///
  /// 返回保存路径；用户取消选择时返回 null。
  Future<String?> savePhotoFileToDisk({
    required String url,
    required int sizeBytes,
    required String suggestedName,
  }) async {
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) {
      return null;
    }
    await _repo.downloadPhotoFile(
      url: url,
      sizeBytes: sizeBytes,
      destinationPath: location.path,
    );
    return location.path;
  }

  /// 应用编辑操作
  Future<PhotoEditVersion> applyEdit(
    String photoId,
    String editType,
    Map<String, dynamic> editParams,
  ) => _repo.applyEdit(photoId, editType, editParams);

  /// 获取编辑版本列表
  Future<List<PhotoEditVersion>> listVersions(String photoId) =>
      _repo.listVersions(photoId);

  /// 回滚到指定版本
  Future<void> revertToVersion(String photoId, String versionId) async {
    try {
      await _repo.revertToVersion(photoId, versionId);
      await refresh();
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 创建相册分享链接
  Future<PhotoShareLink> createAlbumShare(
    String albumId, {
    String? password,
    DateTime? expiresAt,
    int? maxAccessCount,
  }) => _repo.createAlbumShare(
    albumId,
    password: password,
    expiresAt: expiresAt,
    maxAccessCount: maxAccessCount,
  );

  /// 列出相册分享链接
  Future<List<PhotoShareLink>> listAlbumShares(String albumId) =>
      _repo.listAlbumShares(albumId);

  /// 撤销分享链接
  Future<void> revokeAlbumShare(String shareId) =>
      _repo.revokeAlbumShare(shareId);

  /// 创建单张照片分享链接
  Future<PhotoShareLink> createPhotoShare(
    String photoId, {
    String? password,
    DateTime? expiresAt,
    int? maxAccessCount,
  }) => _repo.createPhotoShare(
    photoId,
    password: password,
    expiresAt: expiresAt,
    maxAccessCount: maxAccessCount,
  );

  /// 列出单张照片分享链接
  Future<List<PhotoShareLink>> listPhotoShares(String photoId) =>
      _repo.listPhotoShares(photoId);

  /// 发起共享单张照片会话
  Future<String> authorizeSharedPhoto(String token, {String? password}) =>
      _repo.authorizeSharedPhoto(token, password: password);

  /// 访问共享单张照片
  Future<PhotoItem> accessSharedPhoto(
    String token, {
    required String sessionToken,
  }) => _repo.accessSharedPhoto(token, sessionToken: sessionToken);

  /// 访问共享相册
  Future<String> authorizeSharedAlbum(String token, {String? password}) =>
      _repo.authorizeSharedAlbum(token, password: password);

  Future<PhotoSharedAlbum> accessSharedAlbum(
    String token, {
    required String sessionToken,
    int page = 0,
    int size = 50,
  }) => _repo.accessSharedAlbum(
    token,
    sessionToken: sessionToken,
    page: page,
    size: size,
  );

  /// 提交照片库存量 AI 重分析任务
  Future<String> reanalyzeLibrary() async {
    try {
      return await _repo.reanalyzeLibrary();
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }
}
