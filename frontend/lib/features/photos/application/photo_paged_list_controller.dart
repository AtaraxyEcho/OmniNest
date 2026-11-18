import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/features/photos/application/photo_repository_providers.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';

final photoListProvider = AsyncNotifierProvider<PhotoListController, PhotoPage>(
  PhotoListController.new,
);

final photoFavoritesProvider =
    AsyncNotifierProvider<PhotoFavoritesController, PhotoPage>(
      PhotoFavoritesController.new,
    );

abstract base class _PagedPhotoListController extends AsyncNotifier<PhotoPage> {
  int _generation = 0;
  bool _loadingMore = false;

  Future<PhotoPage> loadFirstPage();

  Future<PhotoPage> loadPage({required int page, required int size});

  @override
  Future<PhotoPage> build() {
    ref.watch(sessionEpochProvider);
    _generation++;
    _loadingMore = false;
    return loadFirstPage();
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (_loadingMore || current == null || !current.hasMore) return;
    _loadingMore = true;
    final generation = _generation;
    try {
      final next = await loadPage(page: current.page + 1, size: current.size);
      if (!ref.mounted || generation != _generation) return;
      final live = state.asData?.value;
      if (live == null || next.page <= live.page) return;
      final seen = live.items.map((photo) => photo.id).toSet();
      state = AsyncData(
        PhotoPage(
          items: List<PhotoItem>.unmodifiable([
            ...live.items,
            ...next.items.where((photo) => seen.add(photo.id)),
          ]),
          page: next.page,
          size: next.size,
          totalElements: next.totalElements,
          totalPages: next.totalPages,
        ),
      );
    } finally {
      if (generation == _generation) _loadingMore = false;
    }
  }
}

final class PhotoListController extends _PagedPhotoListController {
  PhotoRepository get _repository => ref.read(photoRepositoryProvider);

  @override
  Future<PhotoPage> loadFirstPage() =>
      ref.watch(photoRepositoryProvider).listPhotos();

  @override
  Future<PhotoPage> loadPage({required int page, required int size}) =>
      _repository.listPhotos(page: page, size: size);
}

final class PhotoFavoritesController extends _PagedPhotoListController {
  PhotoRepository get _repository => ref.read(photoRepositoryProvider);

  @override
  Future<PhotoPage> loadFirstPage() =>
      ref.watch(photoRepositoryProvider).listFavorites();

  @override
  Future<PhotoPage> loadPage({required int page, required int size}) =>
      _repository.listFavorites(page: page, size: size);
}
