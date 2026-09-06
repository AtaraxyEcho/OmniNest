import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/photos/application/photo_center_models.dart';
import 'package:omninest/features/photos/data/photo_api.dart';
import 'package:omninest/features/photos/data/photo_repository_impl.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_batch_task.dart';
import 'package:omninest/features/photos/domain/photo_batch_download_ticket.dart';
import 'package:omninest/features/photos/domain/photo_edit_version.dart';
import 'package:omninest/features/photos/domain/photo_group.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

export 'package:omninest/features/photos/application/photo_center_models.dart';

part 'photo_controller_commands.dart';

part 'photo_center_providers.dart';

part 'photo_center_collection_loaders.dart';

enum _ImportTaskPollOutcome { completed, failed, pending, unavailable }

// -- 数据 Provider --

final photoListProvider = FutureProvider<PhotoPage>((ref) {
  return ref.watch(photoRepositoryProvider).listPhotos();
});

final photoFavoritesProvider = FutureProvider<PhotoPage>((ref) {
  return ref.watch(photoRepositoryProvider).listFavorites();
});

final photoAlbumsProvider = FutureProvider<List<PhotoAlbum>>((ref) {
  return ref.watch(photoRepositoryProvider).listAlbums();
});

final photoDetailProvider = FutureProvider.autoDispose
    .family<PhotoItem, String>((ref, photoId) {
      return ref.watch(photoRepositoryProvider).getPhoto(photoId);
    });

final photoAlbumDetailProvider = FutureProvider.autoDispose
    .family<PhotoAlbumDetail, String>((ref, albumId) {
      return ref.watch(photoRepositoryProvider).getAlbumDetail(albumId);
    });

/// 照片中心控制器
class PhotoCenterController extends AsyncNotifier<PhotoCenterState>
    with PhotoCenterControllerCommands, PhotoCenterCollectionLoaders {
  @override
  PhotoRepository get _repo => ref.read(photoRepositoryProvider);
  Timer? _searchDebounce;
  int _importRefreshEpoch = 0;
  int _refreshGeneration = 0;
  Future<bool>? _importRefreshInFlight;
  Future<void>? _realtimeRefreshInFlight;
  PhotoImportNotice? _lastImportNotice;
  String? _lastImportDetail;

  /// 最近一次导入后台任务的终态错误，供导入入口显示准确反馈。
  PhotoImportNotice? get lastImportNotice => _lastImportNotice;

  /// 后端任务返回的自定义错误信息（如安全隔离提示），仅 backendFailed 时有值。
  String? get lastImportDetail => _lastImportDetail;

  @override
  Future<PhotoCenterState> build() async {
    ref.onDispose(() {
      _searchDebounce?.cancel();
      _importRefreshEpoch++;
      _refreshGeneration++;
      _importRefreshInFlight = null;
      _realtimeRefreshInFlight = null;
    });
    return _loadState();
  }

  Future<PhotoCenterState> _loadState() async {
    final partialErrors = <String>[];
    final previous = state.asData?.value;
    final results = await Future.wait([
      _safe(_repo.dashboard, PhotoDashboard.empty(), partialErrors),
      _safe(_repo.listPhotos, PhotoPage.empty(), partialErrors),
      _safe(_repo.listFavorites, PhotoPage.empty(), partialErrors),
      _safe(_repo.listAlbums, <PhotoAlbum>[], partialErrors),
    ]);
    final photoPage = results[1] as PhotoPage;
    final favoritePage = results[2] as PhotoPage;
    return PhotoCenterState(
      dashboard: results[0] as PhotoDashboard,
      photos: photoPage.items,
      favorites: favoritePage.items,
      albums: results[3] as List<PhotoAlbum>,
      tab: previous?.tab ?? PhotoTab.all,
      libraryView: previous?.libraryView ?? PhotoLibraryView.gridDay,
      frameView: previous?.frameView ?? FrameView.grid,
      selectedPhotoIds: previous?.selectedPhotoIds ?? const {},
      isSelectionMode: previous?.isSelectionMode ?? false,
      groupBy: previous?.groupBy ?? GroupBy.date,
      searchQuery: previous?.searchQuery ?? '',
      timeline: previous?.timeline,
      timelinePage: previous?.timelinePage ?? 0,
      timelineTotalElements: previous?.timelineTotalElements ?? 0,
      trashPhotos: previous?.trashPhotos ?? const [],
      trashTotalElements: previous?.trashTotalElements ?? 0,
      photoPage: photoPage.page,
      favoritePage: favoritePage.page,
      photoTotalElements: photoPage.totalElements,
      favoriteTotalElements: favoritePage.totalElements,
      errorMessage: partialErrors.isEmpty ? null : partialErrors.join('；'),
    );
  }

  /// 刷新全部数据
  @override
  Future<void> refresh() async {
    _importRefreshEpoch++;
    final generation = ++_refreshGeneration;
    final current = state.asData?.value ?? PhotoCenterState.empty();
    final partialErrors = <String>[];
    final results = await Future.wait([
      _safe(_repo.dashboard, PhotoDashboard.empty(), partialErrors),
      _safe(
        () => _repo.listPhotos(
          query: current.tab == PhotoTab.all ? current.searchQuery : null,
        ),
        PhotoPage.empty(),
        partialErrors,
      ),
      _safe(
        () => _repo.listFavorites(
          query: current.tab == PhotoTab.favorites ? current.searchQuery : null,
        ),
        PhotoPage.empty(),
        partialErrors,
      ),
      _safe(_repo.listAlbums, <PhotoAlbum>[], partialErrors),
    ]);
    final photoPage = results[1] as PhotoPage;
    final favoritePage = results[2] as PhotoPage;
    if (!ref.mounted || generation != _refreshGeneration) return;
    state = AsyncData(
      current.copyWith(
        dashboard: results[0] as PhotoDashboard,
        photos: photoPage.items,
        favorites: favoritePage.items,
        albums: results[3] as List<PhotoAlbum>,
        photoPage: photoPage.page,
        favoritePage: favoritePage.page,
        photoTotalElements: photoPage.totalElements,
        favoriteTotalElements: favoritePage.totalElements,
        photoRefreshVersion: current.photoRefreshVersion + 1,
        favoriteRefreshVersion: current.favoriteRefreshVersion + 1,
        clearPhotoPageError: true,
        clearFavoritePageError: true,
        errorMessage: partialErrors.isEmpty ? null : partialErrors.join('；'),
      ),
    );
    // 时间线在移入回收站/恢复后计数会变化：已加载过则强制重载，保证徽章与列表一致。
    if (current.timeline != null) {
      unawaited(loadTimeline(force: true));
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

  /// 严格刷新实时事件涉及的核心照片数据。
  Future<void> refreshForRealtime() {
    final active = _realtimeRefreshInFlight;
    if (active != null) return active;
    _importRefreshEpoch++;
    final generation = ++_refreshGeneration;
    late final Future<void> future;
    future = _refreshForRealtime(generation);
    _realtimeRefreshInFlight = future;
    unawaited(
      future.then(
        (_) {
          if (identical(_realtimeRefreshInFlight, future)) {
            _realtimeRefreshInFlight = null;
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_realtimeRefreshInFlight, future)) {
            _realtimeRefreshInFlight = null;
          }
        },
      ),
    );
    return future;
  }

  Future<void> _refreshForRealtime(int generation) async {
    final current = state.asData?.value ?? PhotoCenterState.empty();
    final results = await Future.wait([
      _repo.dashboard(),
      _repo.listPhotos(
        query: current.tab == PhotoTab.all ? current.searchQuery : null,
      ),
      _repo.listFavorites(
        query: current.tab == PhotoTab.favorites ? current.searchQuery : null,
      ),
      _repo.listAlbums(),
    ]);
    if (!ref.mounted || generation != _refreshGeneration) return;
    final photoPage = results[1] as PhotoPage;
    final favoritePage = results[2] as PhotoPage;
    state = AsyncData(
      current.copyWith(
        dashboard: results[0] as PhotoDashboard,
        photos: _mergeRefreshedPage(
          current.photos,
          photoPage.items,
          photoPage.totalElements,
        ),
        favorites: _mergeRefreshedPage(
          current.favorites,
          favoritePage.items,
          favoritePage.totalElements,
        ),
        albums: results[3] as List<PhotoAlbum>,
        photoTotalElements: photoPage.totalElements,
        favoriteTotalElements: favoritePage.totalElements,
        photoRefreshVersion: current.photoRefreshVersion + 1,
        favoriteRefreshVersion: current.favoriteRefreshVersion + 1,
        clearError: true,
      ),
    );
    if (current.timeline != null) {
      if (!ref.mounted || generation != _refreshGeneration) return;
      await loadTimeline(force: true);
    }
    if (current.groups != null) {
      if (!ref.mounted || generation != _refreshGeneration) return;
      await loadGroups(current.groupBy, force: true);
    }
  }

  Future<T> _safe<T>(
    Future<T> Function() call,
    T fallback,
    List<String> partialErrors,
  ) async {
    try {
      return await call();
    } on Exception catch (e) {
      partialErrors.add(describeUserFacingError(e).message);
      return fallback;
    }
  }

  @override
  void _setError(String message) {
    final current = state.asData?.value;
    if (current != null) {
      state = AsyncData(current.copyWith(errorMessage: message));
    }
  }

  void clearError() {
    final current = state.asData?.value;
    if (current != null) {
      state = AsyncData(current.copyWith(clearError: true));
    }
  }

  /// 切换 Tab
  void selectTab(PhotoTab tab) {
    final current = state.asData?.value;
    if (current == null) return;
    _importRefreshEpoch++;
    _refreshGeneration++;
    state = AsyncData(current.copyWith(tab: tab, searchQuery: ''));
    _searchDebounce?.cancel();
    if (current.searchQuery.isNotEmpty &&
        (tab == PhotoTab.all || tab == PhotoTab.favorites)) {
      unawaited(_reloadVisiblePage(tab, ''));
    }
  }

  /// 切换图库内容形态；时间线与分组视图按需懒加载。
  void setLibraryView(PhotoLibraryView view) {
    final current = state.asData?.value;
    if (current == null || current.libraryView == view) return;
    state = AsyncData(current.copyWith(libraryView: view));
    switch (view) {
      case PhotoLibraryView.timeline:
        if (current.timeline == null) {
          unawaited(loadTimeline());
        }
      case PhotoLibraryView.groups:
        unawaited(loadGroups(current.groupBy));
      case PhotoLibraryView.gridDay || PhotoLibraryView.gridMonth:
        break;
    }
  }

  /// 切换 Frame 设计稿的图库视图；切出当前视图时退出多选模式。
  ///
  /// 收藏视图与图库数据源联动：进入收藏视图切换到收藏 Tab，
  /// 切回其他视图恢复全部照片 Tab。
  void setFrameView(FrameView view) {
    final current = state.asData?.value;
    if (current == null || current.frameView == view) return;
    PhotoTab? targetTab;
    if (view == FrameView.favorites && current.tab != PhotoTab.favorites) {
      targetTab = PhotoTab.favorites;
    }
    if (view != FrameView.favorites && current.tab == PhotoTab.favorites) {
      targetTab = PhotoTab.all;
    }
    final hadQuery = current.searchQuery.trim().isNotEmpty;
    state = AsyncData(
      current.copyWith(
        frameView: view,
        isSelectionMode: false,
        selectedPhotoIds: const {},
        tab: targetTab ?? current.tab,
        searchQuery: targetTab != null ? '' : null,
      ),
    );
    _importRefreshEpoch++;
    _refreshGeneration++;
    _searchDebounce?.cancel();
    final tab = targetTab ?? current.tab;
    if (targetTab != null || hadQuery) {
      unawaited(_reloadVisiblePage(tab, ''));
    }
    if (view == FrameView.trash) {
      unawaited(loadTrashPage());
    }
  }

  /// 全选/取消全选当前视图可见照片；已全选时清空选择。
  void toggleSelectAllVisible() {
    final current = state.asData?.value;
    if (current == null) return;
    final visibleIds = current.visiblePhotos.map((photo) => photo.id).toSet();
    final allSelected =
        visibleIds.isNotEmpty &&
        visibleIds.every(current.selectedPhotoIds.contains);
    final next =
        allSelected
            ? const <String>{}
            : <String>{...current.selectedPhotoIds, ...visibleIds};
    state = AsyncData(current.copyWith(selectedPhotoIds: next));
  }

  /// 切换分组浏览的维度。
  void setGroupBy(GroupBy groupBy) {
    final current = state.asData?.value;
    if (current == null || current.groupBy == groupBy) return;
    state = AsyncData(current.copyWith(groupBy: groupBy));
    if (current.libraryView == PhotoLibraryView.groups) {
      unawaited(loadGroups(groupBy));
    }
  }

  /// 设置搜索关键字
  void setSearchQuery(String query) {
    final current = state.asData?.value;
    if (current == null) return;
    _importRefreshEpoch++;
    _refreshGeneration++;
    state = AsyncData(current.copyWith(searchQuery: query));
    if (current.tab != PhotoTab.all && current.tab != PhotoTab.favorites) {
      return;
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_reloadVisiblePage(current.tab, query));
    });
  }

  /// 切换收藏状态。
  ///
  /// [currentFavorite] 必须由调用方传入照片的真实当前值（如详情页持有的
  /// photo.favorite），避免分页快照缺失或过期时把取消收藏误判为收藏。
  Future<void> toggleFavorite(
    String photoId, {
    required bool currentFavorite,
  }) async {
    final current = state.asData?.value;
    if (current == null) return;
    try {
      if (currentFavorite) {
        await _repo.removeFavorite(photoId);
      } else {
        await _repo.addFavorite(photoId);
      }
      await refresh();
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

  /// 提交外部编辑器产出的整图字节，保存为新编辑版本。
  Future<void> applyEditedImage(String photoId, Uint8List bytes) async {
    try {
      await _repo.applyEditedImage(photoId, bytes);
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 为有 GPS 坐标但缺少地名的照片补充逆地理编码。
  Future<void> backfillGeocode(String photoId) async {
    try {
      await _repo.backfillGeocode(photoId);
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 从回收站恢复照片。
  Future<void> restorePhotoFromTrash(String photoId) async {
    try {
      await _repo.restorePhoto(photoId);
      await refresh();
      await loadTrashPage(force: true);
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 永久删除回收站中的照片。
  Future<TaskSubmission> purgePhotoFromTrash(
    String photoId, {
    bool cascade = false,
  }) async {
    try {
      final submission = await _repo.purgePhoto(photoId, cascade: cascade);
      ref.invalidate(activeTaskSummaryProvider);
      unawaited(ref.read(taskListProvider.notifier).load());
      await refresh();
      await loadTrashPage(force: true);
      return submission;
    } on Exception catch (e) {
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
      await refresh();
      await loadTrashPage(force: true);
      return submission;
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
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

  int _subtractFloorZero(int value, int decrement) {
    final result = value - decrement;
    return result < 0 ? 0 : result;
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
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }
}

/// 浏览来源类型：锚定幻灯片等播放集合的业务数据源。
enum PhotoBrowseSource { library, favorites, album, timeline, locations, tag }

/// 当前浏览的照片序列与来源：详情页的上一张/下一张与幻灯片范围来源。
///
/// 由各浏览视图（全部照片、收藏、时间线、影集详情等）在用户打开照片时写入；
/// 序列为该入口对应的完整业务集合（大集合由幻灯片按需分页补齐）。
class PhotoBrowseScope {
  const PhotoBrowseScope({
    this.photos = const [],
    this.source = PhotoBrowseSource.library,
    this.sourceKey,
  });

  final List<PhotoItem> photos;
  final PhotoBrowseSource source;

  /// 来源限定键：影集=影集 ID，标签=标签名，时间线=年月范围；其余为空。
  final String? sourceKey;

  bool contains(String photoId) => photos.any((p) => p.id == photoId);
}

class PhotoBrowseScopeNotifier extends Notifier<PhotoBrowseScope> {
  @override
  PhotoBrowseScope build() => const PhotoBrowseScope();

  void set(
    List<PhotoItem> photos,
    PhotoBrowseSource source, {
    String? sourceKey,
  }) {
    state = PhotoBrowseScope(
      photos: List.unmodifiable(photos),
      source: source,
      sourceKey: sourceKey,
    );
  }
}

final photoBrowseScopeProvider =
    NotifierProvider<PhotoBrowseScopeNotifier, PhotoBrowseScope>(
      PhotoBrowseScopeNotifier.new,
    );

/// 照片详情页信息面板的展开状态；在上一张/下一张切换间保持。
class PhotoInfoPanelVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// 用户的标签清单（用于标签视图芯片）。
final photoTagsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(photoRepositoryProvider).listTags();
});

/// 按标签查询的照片列表。
final photosByTagProvider = FutureProvider.autoDispose
    .family<List<PhotoItem>, String>((ref, tag) {
      return ref.watch(photoRepositoryProvider).listByTag(tag);
    });

final photoInfoPanelVisibleProvider =
    NotifierProvider<PhotoInfoPanelVisibleNotifier, bool>(
      PhotoInfoPanelVisibleNotifier.new,
    );

/// 照片详情页幻灯片播放状态；跨上一张/下一张路由替换保持，
/// 由详情页在路由真实退出（关闭/系统返回）时复位为暂停。
class PhotoSlideshowPlayingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void start() => state = true;

  void stop() => state = false;
}

final photoSlideshowPlayingProvider =
    NotifierProvider<PhotoSlideshowPlayingNotifier, bool>(
      PhotoSlideshowPlayingNotifier.new,
    );

final photoCenterControllerProvider =
    AsyncNotifierProvider<PhotoCenterController, PhotoCenterState>(
      PhotoCenterController.new,
    );

/// 指定年月照片分页状态；由时间线月份进入的期间浏览页消费。
class PhotoPeriodState {
  const PhotoPeriodState({
    this.period,
    this.photos = const [],
    this.totalElements = 0,
    this.nextPage = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.error,
  });

  /// 当前查看的年月，进入前为空。
  final (int, int)? period;

  final List<PhotoItem> photos;
  final int totalElements;

  /// 下一页页码；首页尚未成功返回时为 0，成功后从 1 起递增。
  final int nextPage;
  final bool hasMore;
  final bool isLoadingMore;
  final String? error;

  /// 首页尚未返回（nextPage 仍为 0）且无错误时视为首次加载中。
  bool get isInitialLoading => period != null && nextPage == 0 && error == null;

  bool get isEmpty => photos.isEmpty && !isInitialLoading;
}

/// 指定年月照片分页控制器：期间浏览页进入时调用 open，滚动到底部时调用 loadMore。
///
/// 使用代计数防止快速切换年月后旧响应覆盖新状态；页面退出不清理，重入由 open 复位。
class PhotoPeriodNotifier extends Notifier<PhotoPeriodState> {
  int _generation = 0;

  @override
  PhotoPeriodState build() => const PhotoPeriodState();

  /// 打开指定年月：复位状态并拉取首页。
  Future<void> open(int year, int month) async {
    final generation = ++_generation;
    state = PhotoPeriodState(period: (year, month));
    try {
      final page = await ref
          .read(photoRepositoryProvider)
          .listByPeriod(year: year, month: month);
      if (generation != _generation) {
        return;
      }
      state = PhotoPeriodState(
        period: (year, month),
        photos: page.items,
        totalElements: page.totalElements,
        nextPage: 1,
        hasMore: page.hasMore,
      );
    } on Exception catch (e) {
      if (generation != _generation) {
        return;
      }
      state = PhotoPeriodState(
        period: (year, month),
        error: describeUserFacingError(e).message,
      );
    }
  }

  /// 加载下一页；无更多、正在加载或存在错误时忽略重复触发。
  Future<void> loadMore() async {
    final current = state;
    final period = current.period;
    if (period == null ||
        !current.hasMore ||
        current.isLoadingMore ||
        current.error != null) {
      return;
    }
    final generation = _generation;
    state = PhotoPeriodState(
      period: current.period,
      photos: current.photos,
      totalElements: current.totalElements,
      nextPage: current.nextPage,
      hasMore: current.hasMore,
      isLoadingMore: true,
    );
    try {
      final page = await ref
          .read(photoRepositoryProvider)
          .listByPeriod(
            year: period.$1,
            month: period.$2,
            page: current.nextPage,
          );
      if (generation != _generation) {
        return;
      }
      final existingIds = current.photos.map((p) => p.id).toSet();
      final merged = [
        ...current.photos,
        ...page.items.where((p) => !existingIds.contains(p.id)),
      ];
      state = PhotoPeriodState(
        period: current.period,
        photos: merged,
        totalElements: page.totalElements,
        nextPage: current.nextPage + 1,
        hasMore: page.hasMore,
      );
    } on Exception catch (e) {
      if (generation != _generation) {
        return;
      }
      state = PhotoPeriodState(
        period: current.period,
        photos: current.photos,
        totalElements: current.totalElements,
        nextPage: current.nextPage,
        hasMore: current.hasMore,
        error: describeUserFacingError(e).message,
      );
    }
  }
}

final photoPeriodProvider =
    NotifierProvider<PhotoPeriodNotifier, PhotoPeriodState>(
      PhotoPeriodNotifier.new,
    );

/// 相册候选照片选择状态；影集"添加照片"选择页消费。
class PhotoAlbumPickerState {
  const PhotoAlbumPickerState({
    this.albumId,
    this.candidates = const [],
    this.selectedIds = const <String>{},
    this.totalElements = 0,
    this.nextPage = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.isSubmitting = false,
    this.error,
  });

  /// 正在选择照片的相册，进入前为空。
  final String? albumId;
  final List<PhotoItem> candidates;
  final Set<String> selectedIds;
  final int totalElements;

  /// 下一页页码；首页尚未成功返回时为 0，成功后从 1 起递增。
  final int nextPage;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isSubmitting;
  final String? error;

  bool get isInitialLoading =>
      albumId != null && nextPage == 0 && error == null;

  bool get isEmpty => candidates.isEmpty && !isInitialLoading;
}

/// 相册候选照片选择控制器：选择页进入时 open，滚动到底部 loadMore，确认时 submit。
///
/// 使用代计数防止快速切换相册后旧响应覆盖新状态；页面退出不清理，重入由 open 复位。
class PhotoAlbumPickerNotifier extends Notifier<PhotoAlbumPickerState> {
  int _generation = 0;

  @override
  PhotoAlbumPickerState build() => const PhotoAlbumPickerState();

  /// 打开指定相册的选择器：复位选择并拉取候选首页。
  Future<void> open(String albumId) async {
    final generation = ++_generation;
    state = PhotoAlbumPickerState(albumId: albumId);
    try {
      final page = await ref
          .read(photoRepositoryProvider)
          .listAlbumCandidates(albumId: albumId);
      if (generation != _generation) {
        return;
      }
      state = PhotoAlbumPickerState(
        albumId: albumId,
        candidates: page.items,
        totalElements: page.totalElements,
        nextPage: 1,
        hasMore: page.hasMore,
      );
    } on Exception catch (e) {
      if (generation != _generation) {
        return;
      }
      state = PhotoAlbumPickerState(
        albumId: albumId,
        error: describeUserFacingError(e).message,
      );
    }
  }

  /// 加载下一页候选；无更多、正在加载或存在错误时忽略重复触发。
  Future<void> loadMore() async {
    final current = state;
    final albumId = current.albumId;
    if (albumId == null ||
        !current.hasMore ||
        current.isLoadingMore ||
        current.error != null) {
      return;
    }
    final generation = _generation;
    state = PhotoAlbumPickerState(
      albumId: current.albumId,
      candidates: current.candidates,
      selectedIds: current.selectedIds,
      totalElements: current.totalElements,
      nextPage: current.nextPage,
      hasMore: current.hasMore,
      isLoadingMore: true,
    );
    try {
      final page = await ref
          .read(photoRepositoryProvider)
          .listAlbumCandidates(albumId: albumId, page: current.nextPage);
      if (generation != _generation) {
        return;
      }
      final existingIds = current.candidates.map((p) => p.id).toSet();
      final merged = [
        ...current.candidates,
        ...page.items.where((p) => !existingIds.contains(p.id)),
      ];
      state = PhotoAlbumPickerState(
        albumId: current.albumId,
        candidates: merged,
        selectedIds: current.selectedIds,
        totalElements: page.totalElements,
        nextPage: current.nextPage + 1,
        hasMore: page.hasMore,
      );
    } on Exception catch (e) {
      if (generation != _generation) {
        return;
      }
      state = PhotoAlbumPickerState(
        albumId: current.albumId,
        candidates: current.candidates,
        selectedIds: current.selectedIds,
        totalElements: current.totalElements,
        nextPage: current.nextPage,
        hasMore: current.hasMore,
        error: describeUserFacingError(e).message,
      );
    }
  }

  /// 切换一张候选照片的选中状态。
  void toggle(String photoId) {
    final current = state;
    final updated = Set<String>.of(current.selectedIds);
    if (!updated.add(photoId)) {
      updated.remove(photoId);
    }
    state = PhotoAlbumPickerState(
      albumId: current.albumId,
      candidates: current.candidates,
      selectedIds: updated,
      totalElements: current.totalElements,
      nextPage: current.nextPage,
      hasMore: current.hasMore,
      isLoadingMore: current.isLoadingMore,
      isSubmitting: current.isSubmitting,
      error: current.error,
    );
  }

  /// 提交所选照片到相册；提交中或无选择时直接返回结果。
  Future<bool> submit() async {
    final current = state;
    final albumId = current.albumId;
    if (albumId == null ||
        current.selectedIds.isEmpty ||
        current.isSubmitting) {
      return false;
    }
    state = PhotoAlbumPickerState(
      albumId: current.albumId,
      candidates: current.candidates,
      selectedIds: current.selectedIds,
      totalElements: current.totalElements,
      nextPage: current.nextPage,
      hasMore: current.hasMore,
      isSubmitting: true,
    );
    try {
      await ref
          .read(photoRepositoryProvider)
          .addPhotosToAlbum(
            albumId: albumId,
            photoIds: current.selectedIds.toList(),
          );
      return true;
    } on Exception catch (e) {
      state = PhotoAlbumPickerState(
        albumId: current.albumId,
        candidates: current.candidates,
        selectedIds: current.selectedIds,
        totalElements: current.totalElements,
        nextPage: current.nextPage,
        hasMore: current.hasMore,
        error: describeUserFacingError(e).message,
      );
      return false;
    }
  }
}

final photoAlbumPickerProvider =
    NotifierProvider<PhotoAlbumPickerNotifier, PhotoAlbumPickerState>(
      PhotoAlbumPickerNotifier.new,
    );
