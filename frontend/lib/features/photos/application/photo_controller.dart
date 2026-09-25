import 'dart:async';
import 'package:omninest/app/session/session_epoch.dart';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/photos/application/photo_center_models.dart';
import 'package:omninest/features/photos/application/photo_detail_memory_cache.dart';
import 'package:omninest/features/photos/application/photo_repository_providers.dart';
import 'package:omninest/features/photos/application/photo_viewer_providers.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_batch_download_ticket.dart';
import 'package:omninest/features/photos/domain/photo_batch_task.dart';
import 'package:omninest/features/photos/domain/photo_edit_version.dart';
import 'package:omninest/features/photos/domain/photo_group.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';
import 'package:omninest/features/photos/platform/photo_save_channel.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

export 'package:omninest/features/photos/application/photo_album_picker_controller.dart';
export 'package:omninest/features/photos/application/photo_browse_scope.dart';
export 'package:omninest/features/photos/application/photo_center_models.dart';
export 'package:omninest/features/photos/application/photo_detail_memory_cache.dart';
export 'package:omninest/features/photos/application/photo_period_controller.dart';
export 'package:omninest/features/photos/application/photo_repository_providers.dart';
export 'package:omninest/features/photos/platform/photo_save_channel.dart';
export 'package:omninest/features/photos/application/photo_viewer_providers.dart';

part 'photo_controller_commands.dart';

part 'photo_center_providers.dart';

part 'photo_center_collection_loaders.dart';

enum _ImportTaskPollOutcome { completed, failed, pending, unavailable }

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
    .family<PhotoItem, String>((ref, photoId) async {
      final photo = await ref.watch(photoRepositoryProvider).getPhoto(photoId);
      ref.read(photoDetailMemoryCacheProvider).put(photo);
      return photo;
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
  Future<void>? _realtimeRefreshInFlight;

  @override
  Future<PhotoCenterState> build() async {
    // 换号时以依赖变化语义重建，避免渲染上一账号的旧值。
    ref.watch(sessionEpochProvider);
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
    if (!ref.mounted || generation != _refreshGeneration) {
      _listRefreshSuperseded = true;
      return;
    }
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
    // 永久删除由 Worker 异步落库；回收站已加载或当前在回收站视图时必须补查。
    final latest = state.asData?.value;
    final shouldReloadTrash =
        latest != null &&
        (latest.trashPhotos.isNotEmpty ||
            latest.frameView == FrameView.trash ||
            current.frameView == FrameView.trash ||
            current.trashPhotos.isNotEmpty);
    if (shouldReloadTrash) {
      if (!ref.mounted || generation != _refreshGeneration) return;
      await loadTrashPage(force: true);
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
    _maybeReissueSupersededRefresh();
  }

  /// refresh 结果被切视图/搜索/实时失效作废后，列表可能停留在旧快照
  /// （封面短签名过期即表现为网格空白）；在用户下一次交互时补发一次
  /// 刷新。补发本身再被作废则不再级联，避免事件风暴下死循环。
  void _maybeReissueSupersededRefresh() {
    if (!_listRefreshSuperseded) {
      return;
    }
    _listRefreshSuperseded = false;
    unawaited(refresh());
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
      final latest = state.asData?.value;
      if (latest == null) {
        return;
      }
      final latestQuery = latest.searchQuery;
      if (latestQuery != query) {
        return;
      }
      unawaited(_reloadVisiblePage(latest.tab, latestQuery));
    });
  }

  /// 切换收藏状态。
  ///
  /// [currentFavorite] 必须由调用方传入照片的真实当前值（如详情页持有的
  /// photo.favorite），避免分页快照缺失或过期时把取消收藏误判为收藏。
  ///
  /// 采用乐观更新：先改本地 photos/favorites，失败再回滚；成功不再整库
  /// refresh，避免单击心形触发 dashboard+列表四连请求。
  Future<void> toggleFavorite(
    String photoId, {
    required bool currentFavorite,
  }) async {
    final current = state.asData?.value;
    if (current == null) return;
    final nextFavorite = !currentFavorite;
    PhotoItem? seed;
    for (final photo in current.photos) {
      if (photo.id == photoId) {
        seed = photo;
        break;
      }
    }
    seed ??= () {
      for (final photo in current.favorites) {
        if (photo.id == photoId) {
          return photo;
        }
      }
      return null;
    }();
    final previous = state;
    if (seed != null) {
      final updated = seed.copyWith(favorite: nextFavorite);
      state = AsyncData(
        current.copyWith(
          photos: [
            for (final photo in current.photos)
              photo.id == photoId ? updated : photo,
          ],
          favorites:
              nextFavorite
                  ? [
                    for (final photo in current.favorites)
                      photo.id == photoId ? updated : photo,
                    if (!current.favorites.any((photo) => photo.id == photoId))
                      updated,
                  ]
                  : [
                    for (final photo in current.favorites)
                      if (photo.id != photoId) photo,
                  ],
        ),
      );
      final cache = ref.read(photoDetailMemoryCacheProvider);
      final cached = cache.get(photoId);
      // 列表种子通常无 sourceUrl；不得覆盖已有完整详情缓存。
      cache.put(
        cached != null ? cached.copyWith(favorite: nextFavorite) : updated,
      );
    }
    try {
      if (currentFavorite) {
        await _repo.removeFavorite(photoId);
      } else {
        await _repo.addFavorite(photoId);
      }
      ref.invalidate(photoDetailProvider(photoId));
    } on Exception catch (e) {
      if (ref.mounted) {
        state = previous;
      }
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 提交外部编辑器产出的整图字节，保存为新编辑版本。
  Future<void> applyEditedImage(String photoId, Uint8List bytes) async {
    try {
      await _repo.applyEditedImage(photoId, bytes);
      ref.invalidate(photoDetailProvider(photoId));
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
}

final photoCenterControllerProvider =
    AsyncNotifierProvider<PhotoCenterController, PhotoCenterState>(
      PhotoCenterController.new,
    );
