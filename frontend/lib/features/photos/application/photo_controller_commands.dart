part of 'photo_controller.dart';

/// 照片中心的选择、批量、编辑、分享与 AI 命令。
mixin PhotoCenterControllerCommands on AsyncNotifier<PhotoCenterState> {
  int _importRefreshEpoch = 0;
  int _refreshGeneration = 0;
  bool _listRefreshSuperseded = false;
  Future<bool>? _importRefreshInFlight;
  PhotoImportNotice? _lastImportNotice;
  String? _lastImportDetail;

  /// 最近一次导入后台任务的终态错误，供导入入口显示准确反馈。
  PhotoImportNotice? get lastImportNotice => _lastImportNotice;

  /// 后端任务返回的自定义错误信息（如安全隔离提示），仅 backendFailed 时有值。
  String? get lastImportDetail => _lastImportDetail;

  PhotoRepository get _repo;

  Future<void> refresh();

  void _setError(String message);

  int _subtractFloorZero(int value, int decrement) {
    final result = value - decrement;
    return result < 0 ? 0 : result;
  }

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
    bool includeLocation = true,
    bool originalQuality = true,
  }) => _repo.createPhotoShare(
    photoId,
    password: password,
    expiresAt: expiresAt,
    maxAccessCount: maxAccessCount,
    includeLocation: includeLocation,
    originalQuality: originalQuality,
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

  /// 将照片移入回收站。
  Future<void> movePhotoToTrash(String photoId) async {
    try {
      await _repo.movePhotoToTrash(photoId);
      _removePhotosOptimistically(<String>{photoId});
      await refresh();
      await loadTrashPage(force: true);
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 批量将照片移入回收站，并清空多选状态。
  Future<void> movePhotosToTrash(List<String> photoIds) async {
    try {
      await _repo.movePhotosToTrash(photoIds);
      _removePhotosOptimistically(photoIds.toSet());
      await refresh();
      await loadTrashPage(force: true);
      final current = state.asData?.value;
      if (current != null) {
        state = AsyncData(
          current.copyWith(isSelectionMode: false, selectedPhotoIds: const {}),
        );
      }
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 加载回收站分页数据。
  Future<void> loadTrashPage({bool force = false}) async {
    final current = state.asData?.value;
    if (current == null || current.isLoadingTrash) {
      return;
    }
    if (!force && current.trashPhotos.isNotEmpty) {
      return;
    }
    state = AsyncData(
      current.copyWith(isLoadingTrash: true, clearTrashPageError: true),
    );
    try {
      final page = await _repo.listTrash();
      final next = state.asData?.value;
      if (next == null) {
        return;
      }
      state = AsyncData(
        next.copyWith(
          trashPhotos: page.items,
          trashPage: page.page,
          trashTotalElements: page.totalElements,
          isLoadingTrash: false,
        ),
      );
    } on Exception catch (e) {
      final next = state.asData?.value;
      if (next == null) {
        return;
      }
      state = AsyncData(
        next.copyWith(
          isLoadingTrash: false,
          trashPageError: describeUserFacingError(e).message,
        ),
      );
    }
  }

  /// 创建相册
  Future<PhotoAlbum> createAlbum({
    required String name,
    String? description,
  }) async {
    try {
      final album = await _repo.createAlbum(
        name: name,
        description: description,
      );
      await refresh();
      return album;
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 删除相册
  Future<void> deleteAlbum(String albumId) async {
    try {
      await _repo.deleteAlbum(albumId);
      await refresh();
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 添加照片到相册
  Future<void> addPhotosToAlbum({
    required String albumId,
    required List<String> photoIds,
  }) async {
    try {
      await _repo.addPhotosToAlbum(albumId: albumId, photoIds: photoIds);
      await refresh();
      ref.invalidate(photoAlbumDetailProvider(albumId));
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 获取相册列表（用于选择对话框）
  Future<List<PhotoAlbum>> listAlbums() async {
    return _repo.listAlbums();
  }

  /// 触发照片扫描
  Future<Map<String, dynamic>> triggerScan() async {
    return _repo.triggerScan();
  }

  /// 查询扫描状态
  Future<Map<String, dynamic>> getScanStatus(String jobId) async {
    return _repo.getScanStatus(jobId);
  }

  /// 创建缩略图重建任务，返回任务 ID（进度在任务中心查看）。
  Future<String> regenerateThumbnails() async {
    return _repo.regenerateThumbnails();
  }

  /// 从相册移除照片
  Future<void> removePhotoFromAlbum({
    required String albumId,
    required String photoId,
  }) async {
    try {
      await _repo.removePhotoFromAlbum(albumId: albumId, photoId: photoId);
      await refresh();
      ref.invalidate(photoAlbumDetailProvider(albumId));
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 上传完成后立即刷新，并在异步自动导入尚未完成时执行有限补查。
  Future<bool> refreshAfterImport({
    Iterable<String> expectedFileIds = const <String>[],
    Iterable<String> taskIds = const <String>[],
  }) {
    final active = _importRefreshInFlight;
    if (active != null) return active;
    _lastImportNotice = null;
    _lastImportDetail = null;
    final baseline = state.asData?.value.dashboard.totalPhotos ?? 0;
    final epoch = ++_importRefreshEpoch;
    final generation = ++_refreshGeneration;
    final expectedIds = expectedFileIds.where((id) => id.isNotEmpty).toSet();
    final importTaskIds = taskIds.where((id) => id.isNotEmpty).toSet();
    late final Future<bool> future;
    future = _refreshAfterImport(
      baseline: baseline,
      epoch: epoch,
      generation: generation,
      expectedFileIds: expectedIds,
      taskIds: importTaskIds,
    );
    _importRefreshInFlight = future;
    unawaited(
      future.then(
        (_) {
          if (identical(_importRefreshInFlight, future)) {
            _importRefreshInFlight = null;
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_importRefreshInFlight, future)) {
            _importRefreshInFlight = null;
          }
        },
      ),
    );
    return future;
  }

  Future<bool> _refreshAfterImport({
    required int baseline,
    required int epoch,
    required int generation,
    required Set<String> expectedFileIds,
    required Set<String> taskIds,
  }) async {
    final imported = await _refreshImportSnapshot(
      baseline,
      epoch,
      generation,
      expectedFileIds,
    );
    if (imported) return true;
    if (!ref.mounted ||
        epoch != _importRefreshEpoch ||
        generation != _refreshGeneration) {
      return false;
    }

    if (taskIds.isNotEmpty) {
      final taskOutcome = await _pollImportTasks(
        taskIds,
        epoch: epoch,
        generation: generation,
      );
      if (taskOutcome == _ImportTaskPollOutcome.failed) {
        return false;
      }
      if (taskOutcome == _ImportTaskPollOutcome.completed) {
        final visible = await _refreshImportSnapshot(
          baseline,
          epoch,
          generation,
          expectedFileIds,
        );
        if (!visible && ref.mounted && epoch == _importRefreshEpoch) {
          _lastImportNotice = PhotoImportNotice.completedNotVisible;
        }
        return visible;
      }
    }

    final visible = await _pollImportedPhotos(
      baseline,
      epoch,
      generation,
      expectedFileIds,
    );
    if (!visible &&
        ref.mounted &&
        epoch == _importRefreshEpoch &&
        generation == _refreshGeneration) {
      _lastImportNotice = PhotoImportNotice.stillProcessing;
    }
    return visible;
  }

  Future<_ImportTaskPollOutcome> _pollImportTasks(
    Set<String> taskIds, {
    required int epoch,
    required int generation,
  }) async {
    if (!ref.mounted) {
      return _ImportTaskPollOutcome.pending;
    }
    final taskApi = ref.read(taskApiProvider);
    for (var attempt = 0; attempt < 15; attempt++) {
      if (!ref.mounted ||
          epoch != _importRefreshEpoch ||
          generation != _refreshGeneration) {
        return _ImportTaskPollOutcome.pending;
      }
      try {
        final tasks = await Future.wait(
          taskIds.map(taskApi.get),
          eagerError: true,
        );
        if (!ref.mounted ||
            epoch != _importRefreshEpoch ||
            generation != _refreshGeneration) {
          return _ImportTaskPollOutcome.pending;
        }
        TaskRecord? failed;
        for (final task in tasks) {
          if (task.isFailed || task.isCancelled) {
            failed = task;
            break;
          }
        }
        if (failed != null) {
          _lastImportDetail = failed.errorMessage?.trim();
          _lastImportNotice = PhotoImportNotice.backendFailed;
          return _ImportTaskPollOutcome.failed;
        }
        if (tasks.every((task) => task.isCompleted)) {
          return _ImportTaskPollOutcome.completed;
        }
      } on Exception {
        // 任务接口不可用时退回照片列表轮询，不阻断已完成的文件上传。
        return _ImportTaskPollOutcome.unavailable;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return _ImportTaskPollOutcome.pending;
  }

  Future<bool> _pollImportedPhotos(
    int baseline,
    int epoch,
    int generation,
    Set<String> expectedFileIds,
  ) async {
    for (var attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!ref.mounted ||
          epoch != _importRefreshEpoch ||
          generation != _refreshGeneration) {
        return false;
      }
      try {
        if (await _refreshImportSnapshot(
          baseline,
          epoch,
          generation,
          expectedFileIds,
        )) {
          return true;
        }
      } on Exception catch (error) {
        if (attempt == 14 &&
            ref.mounted &&
            epoch == _importRefreshEpoch &&
            generation == _refreshGeneration) {
          _setError(describeUserFacingError(error).message);
        }
      }
    }
    return false;
  }

  Future<bool> _refreshImportSnapshot(
    int baseline,
    int epoch,
    int generation,
    Set<String> expectedFileIds,
  ) async {
    final current = state.asData?.value ?? PhotoCenterState.empty();
    final query = current.searchQuery.trim();
    final photosFuture =
        current.tab == PhotoTab.favorites
            ? _repo.listFavorites(query: query)
            : _repo.listPhotos(
              query: current.tab == PhotoTab.all ? query : null,
            );
    final results = await Future.wait([_repo.dashboard(), photosFuture]);
    if (!ref.mounted ||
        epoch != _importRefreshEpoch ||
        generation != _refreshGeneration) {
      return false;
    }
    final dashboard = results[0] as PhotoDashboard;
    final photoPage = results[1] as PhotoPage;
    final containsExpected = expectedFileIds.any(
      (id) => photoPage.items.any((photo) => photo.fileNodeId == id),
    );
    final isFavorites = current.tab == PhotoTab.favorites;
    state = AsyncData(
      isFavorites
          ? current.copyWith(
            dashboard: dashboard,
            favorites: photoPage.items,
            favoritePage: photoPage.page,
            favoriteTotalElements: photoPage.totalElements,
            favoriteRefreshVersion: current.favoriteRefreshVersion + 1,
            clearFavoritePageError: true,
          )
          : current.copyWith(
            dashboard: dashboard,
            photos: photoPage.items,
            photoPage: photoPage.page,
            photoTotalElements: photoPage.totalElements,
            photoRefreshVersion: current.photoRefreshVersion + 1,
            clearPhotoPageError: true,
          ),
    );
    ref.read(photoDashboardProvider.notifier).replace(dashboard);
    final imported =
        expectedFileIds.isEmpty
            ? dashboard.totalPhotos > baseline
            : containsExpected || dashboard.totalPhotos > baseline;
    return imported;
  }

  /// 从回收站恢复照片。
  Future<void> restorePhotoFromTrash(String photoId) async {
    try {
      await _repo.restorePhoto(photoId);
      await refresh();
      await loadTrashPage(force: true);
    } on Exception catch (e) {
      if (_isPhotoTrashGoneError(e)) {
        _removePhotosFromTrash(<String>{photoId});
        unawaited(loadTrashPage(force: true));
      }
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 永久删除回收站中的照片。
  ///
  /// 后端仅创建异步 FILE_PURGE 任务；PhotoItem 由 Worker 在 finalizePurge 落库删除。
  /// 提交成功后立即从本地回收站移除，并在实时刷新/任务落库后补查服务端。
  Future<TaskSubmission> purgePhotoFromTrash(
    String photoId, {
    bool cascade = false,
  }) async {
    try {
      final submission = await _repo.purgePhoto(photoId, cascade: cascade);
      ref.invalidate(activeTaskSummaryProvider);
      unawaited(ref.read(taskListProvider.notifier).load());
      _removePhotosFromTrash(<String>{photoId});
      unawaited(ref.read(photoDashboardProvider.notifier).reload());
      return submission;
    } on Exception catch (e) {
      if (_isPhotoTrashGoneError(e)) {
        _removePhotosFromTrash(<String>{photoId});
        unawaited(loadTrashPage(force: true));
      }
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 清空回收站。
  Future<TaskSubmission> purgeTrash() async {
    try {
      final submission = await _repo.purgeTrash();
      ref.invalidate(activeTaskSummaryProvider);
      unawaited(ref.read(taskListProvider.notifier).load());
      final current = state.asData?.value;
      if (current != null && current.trashPhotos.isNotEmpty) {
        _removePhotosFromTrash(
          current.trashPhotos.map((photo) => photo.id).toSet(),
        );
      } else {
        state = AsyncData(
          (state.asData?.value ?? PhotoCenterState.empty()).copyWith(
            trashPhotos: const [],
            trashTotalElements: 0,
          ),
        );
      }
      unawaited(ref.read(photoDashboardProvider.notifier).reload());
      return submission;
    } on Exception catch (e) {
      if (_isPhotoTrashGoneError(e)) {
        unawaited(loadTrashPage(force: true));
      }
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 后端回收站中已不存在该照片（任务已落库删除，或重复提交）。
  bool _isPhotoTrashGoneError(Object error) {
    if (error is! AppException) {
      return false;
    }
    final code = error.code.toUpperCase();
    return code == 'NOT_FOUND' || code == '404';
  }

  /// 从本地回收站状态移除照片，并同步扣减总数与回收站徽章。
  void _removePhotosFromTrash(Set<String> photoIds) {
    final current = state.asData?.value;
    if (current == null || photoIds.isEmpty) {
      return;
    }
    final remaining = current.trashPhotos
        .where((photo) => !photoIds.contains(photo.id))
        .toList(growable: false);
    final removed = current.trashPhotos.length - remaining.length;
    if (removed == 0) {
      return;
    }
    final dashboard = current.dashboard;
    final nextTrashCount = _subtractFloorZero(dashboard.trashCount, removed);
    state = AsyncData(
      current.copyWith(
        trashPhotos: remaining,
        trashTotalElements: _subtractFloorZero(
          current.trashTotalElements,
          removed,
        ),
        dashboard: PhotoDashboard(
          totalPhotos: dashboard.totalPhotos,
          totalAlbums: dashboard.totalAlbums,
          totalFavorites: dashboard.totalFavorites,
          trashCount: nextTrashCount,
          recentPhotos: dashboard.recentPhotos,
          favoritePhotos: dashboard.favoritePhotos,
        ),
      ),
    );
    ref.read(photoDashboardProvider.notifier).removeTrashPhotos(photoIds);
  }

  void _removePhotosOptimistically(Set<String> photoIds) {
    final current = state.asData?.value;
    if (current == null || photoIds.isEmpty) return;
    final removedFavoriteCount =
        current.favorites.where((photo) => photoIds.contains(photo.id)).length;
    final dashboard = current.dashboard;
    state = AsyncData(
      current.copyWith(
        dashboard: PhotoDashboard(
          totalPhotos: _subtractFloorZero(
            dashboard.totalPhotos,
            photoIds.length,
          ),
          totalAlbums: dashboard.totalAlbums,
          totalFavorites: _subtractFloorZero(
            dashboard.totalFavorites,
            removedFavoriteCount,
          ),
          // 移入回收站：库内减少，回收站增加。
          trashCount: dashboard.trashCount + photoIds.length,
          recentPhotos: dashboard.recentPhotos
              .where((photo) => !photoIds.contains(photo.id))
              .toList(growable: false),
          favoritePhotos: dashboard.favoritePhotos
              .where((photo) => !photoIds.contains(photo.id))
              .toList(growable: false),
        ),
        photos: current.photos
            .where((photo) => !photoIds.contains(photo.id))
            .toList(growable: false),
        favorites: current.favorites
            .where((photo) => !photoIds.contains(photo.id))
            .toList(growable: false),
        selectedPhotoIds: current.selectedPhotoIds.difference(photoIds),
        photoTotalElements: _subtractFloorZero(
          current.photoTotalElements,
          photoIds.length,
        ),
        favoriteTotalElements: _subtractFloorZero(
          current.favoriteTotalElements,
          removedFavoriteCount,
        ),
      ),
    );
    ref.read(photoDashboardProvider.notifier).removePhotos(photoIds);
  }
}
