part of 'photo_controller.dart';

// -- 数据 Provider --

final photoDashboardProvider =
    AsyncNotifierProvider<PhotoDashboardController, PhotoDashboard>(
      PhotoDashboardController.new,
    );

/// 照片概览状态，允许删除提交后立即同步更新 Portal，后台完成后再权威刷新。
class PhotoDashboardController extends AsyncNotifier<PhotoDashboard> {
  final Set<String> _optimisticallyRemovedIds = <String>{};

  @override
  Future<PhotoDashboard> build() async {
    ref.watch(sessionEpochProvider);
    final dashboard = await ref.watch(photoRepositoryProvider).dashboard();
    return _withoutRemovedPhotos(dashboard);
  }

  Future<void> reload() async {
    final dashboard = await ref.read(photoRepositoryProvider).dashboard();
    if (ref.mounted) {
      state = AsyncData(dashboard);
      _optimisticallyRemovedIds.clear();
    }
  }

  void replace(PhotoDashboard dashboard) {
    state = AsyncData(_withoutRemovedPhotos(dashboard));
  }

  void removePhotos(Set<String> photoIds) {
    _optimisticallyRemovedIds.addAll(photoIds);
    final dashboard = state.asData?.value;
    if (dashboard == null || photoIds.isEmpty) {
      return;
    }
    final removedFavoriteCount =
        dashboard.favoritePhotos
            .where((photo) => photoIds.contains(photo.id))
            .length;
    state = AsyncData(
      PhotoDashboard(
        totalPhotos: _subtractFloorZero(dashboard.totalPhotos, photoIds.length),
        totalAlbums: dashboard.totalAlbums,
        totalFavorites: _subtractFloorZero(
          dashboard.totalFavorites,
          removedFavoriteCount,
        ),
        trashCount: dashboard.trashCount,
        recentPhotos: dashboard.recentPhotos
            .where((photo) => !photoIds.contains(photo.id))
            .toList(growable: false),
        favoritePhotos: dashboard.favoritePhotos
            .where((photo) => !photoIds.contains(photo.id))
            .toList(growable: false),
      ),
    );
  }

  /// 永久删除回收站照片后立即扣减回收站徽章。
  void removeTrashPhotos(Set<String> photoIds) {
    final dashboard = state.asData?.value;
    if (dashboard == null || photoIds.isEmpty) {
      return;
    }
    state = AsyncData(
      PhotoDashboard(
        totalPhotos: dashboard.totalPhotos,
        totalAlbums: dashboard.totalAlbums,
        totalFavorites: dashboard.totalFavorites,
        trashCount: _subtractFloorZero(dashboard.trashCount, photoIds.length),
        recentPhotos: dashboard.recentPhotos,
        favoritePhotos: dashboard.favoritePhotos,
      ),
    );
  }

  int _subtractFloorZero(int value, int decrement) {
    final result = value - decrement;
    return result < 0 ? 0 : result;
  }

  PhotoDashboard _withoutRemovedPhotos(PhotoDashboard dashboard) {
    if (_optimisticallyRemovedIds.isEmpty) {
      return dashboard;
    }
    final removedFavoriteCount =
        dashboard.favoritePhotos
            .where((photo) => _optimisticallyRemovedIds.contains(photo.id))
            .length;
    return PhotoDashboard(
      totalPhotos: _subtractFloorZero(
        dashboard.totalPhotos,
        _optimisticallyRemovedIds.length,
      ),
      totalAlbums: dashboard.totalAlbums,
      totalFavorites: _subtractFloorZero(
        dashboard.totalFavorites,
        removedFavoriteCount,
      ),
      trashCount: dashboard.trashCount,
      recentPhotos: dashboard.recentPhotos
          .where((photo) => !_optimisticallyRemovedIds.contains(photo.id))
          .toList(growable: false),
      favoritePhotos: dashboard.favoritePhotos
          .where((photo) => !_optimisticallyRemovedIds.contains(photo.id))
          .toList(growable: false),
    );
  }
}
