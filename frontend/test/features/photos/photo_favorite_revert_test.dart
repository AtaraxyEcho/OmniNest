// 收藏乐观写失败后的收敛契约。
//
// 失败回滚只还原这一张照片，且必须以发布时刻的实况为基准：整份回滚 `await` 之前抓的
// 快照会连带丢掉请求窗口内的多选、图库形态与续载写入（表现为取消收藏失败后，用户在
// 请求期间做出的选择被一起撤回）。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';

PhotoItem _photo(String id, {bool favorite = false}) => PhotoItem(
  id: id,
  fileNodeId: 'node-$id',
  title: id,
  format: 'jpg',
  fileSize: 1024,
  metadataStatus: 'READY',
  favorite: favorite,
  createdAt: DateTime.utc(2026, 9, 20),
);

/// 只备首屏四项与收藏两个动作的仓储替身；收藏请求由门控控制何时失败。
class _FailingFavoriteRepository implements PhotoRepository {
  _FailingFavoriteRepository({
    required List<PhotoItem> photos,
    List<PhotoItem> favorites = const <PhotoItem>[],
  }) : _photoPage = PhotoPage(
         items: photos,
         page: 0,
         size: 50,
         totalElements: photos.length,
         totalPages: 1,
       ),
       _favoritePage = PhotoPage(
         items: favorites,
         page: 0,
         size: 50,
         totalElements: favorites.length,
         totalPages: 1,
       );

  final PhotoPage _photoPage;
  final PhotoPage _favoritePage;

  /// 收藏写请求的闸门：complete 后请求才失败，用来制造「请求在飞、用户改选择」的窗口。
  Completer<void> favoriteGate = Completer<void>();

  @override
  Future<PhotoDashboard> dashboard() async => PhotoDashboard.empty();

  @override
  Future<PhotoPage> listPhotos({
    String? query,
    int page = 0,
    int size = 50,
    String sort = 'createdAt,desc',
  }) async => _photoPage;

  @override
  Future<PhotoPage> listFavorites({
    String? query,
    int page = 0,
    int size = 50,
    String sort = 'createdAt,desc',
  }) async => _favoritePage;

  @override
  Future<PhotoAlbumPage> listAlbumsPage({int page = 0, int size = 50}) async =>
      PhotoAlbumPage.empty();

  @override
  Future<void> addFavorite(String photoId) async {
    await favoriteGate.future;
    throw Exception('收藏请求失败');
  }

  @override
  Future<void> removeFavorite(String photoId) async {
    await favoriteGate.future;
    throw Exception('取消收藏请求失败');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('收藏失败只还原该张，请求窗口内的多选保留', () async {
    final repository = _FailingFavoriteRepository(
      photos: <PhotoItem>[_photo('p1'), _photo('p2')],
    );
    final container = ProviderContainer.test(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(photoCenterControllerProvider.future);

    final notifier = container.read(photoCenterControllerProvider.notifier);
    final pending = notifier.toggleFavorite('p1', currentFavorite: false);
    // 取数在飞期间用户改选择：这是旧写法会连带覆盖掉的写入。
    notifier.toggleSelectAllVisible();
    repository.favoriteGate.complete();
    await expectLater(
      pending,
      throwsA(isA<Exception>()),
      reason: '收藏失败仍按原口径外抛，由调用方呈现',
    );

    final state = container.read(photoCenterControllerProvider).value!;
    expect(
      state.photos.firstWhere((photo) => photo.id == 'p1').favorite,
      isFalse,
      reason: '乐观写必须还原',
    );
    expect(
      state.selectedPhotoIds,
      containsAll(<String>['p1', 'p2']),
      reason: '回滚只还原这一张，不得抹掉请求窗口内的多选',
    );
    expect(state.favorites, isEmpty);
    expect(state.errorMessage, isNotNull);
  });

  test('取消收藏失败不把该张丢回收藏列表外', () async {
    final repository = _FailingFavoriteRepository(
      photos: <PhotoItem>[_photo('p1', favorite: true)],
      favorites: <PhotoItem>[_photo('p1', favorite: true)],
    );
    final container = ProviderContainer.test(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(photoCenterControllerProvider.future);

    final notifier = container.read(photoCenterControllerProvider.notifier);
    final pending = notifier.toggleFavorite('p1', currentFavorite: true);
    repository.favoriteGate.complete();
    await expectLater(pending, throwsA(isA<Exception>()));

    final state = container.read(photoCenterControllerProvider).value!;
    expect(
      state.photos.firstWhere((photo) => photo.id == 'p1').favorite,
      isTrue,
    );
    expect(
      state.favorites.map((photo) => photo.id),
      contains('p1'),
      reason: '原本在收藏列表里的照片必须还原回去',
    );
  });
}
