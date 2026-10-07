// 相册搜索取数路径回归：查询词只交给服务端，前端不得再对服务端结果做本地
// 标题复筛——那会误删按 EXIF、标签、地名命中的条目。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

PhotoPage _page(List<PhotoItem> items) {
  return PhotoPage(
    items: items,
    page: 0,
    size: 50,
    totalElements: items.length,
    totalPages: 1,
  );
}

/// 标题不含查询词的照片：服务端按标签/地名命中，本地标题匹配必然漏删。
PhotoItem _photoByTagHit() {
  return PhotoItem(
    id: 'img-2048',
    fileNodeId: 'file-img-2048',
    title: 'IMG_2048.jpg',
    format: 'jpg',
    fileSize: 1,
    metadataStatus: 'MATCHED',
    favorite: false,
    createdAt: DateTime(2026),
  );
}

void _stubLibrary(
  _MockPhotoRepository repository, {
  required List<PhotoItem> photos,
  required List<String?> observedQueries,
}) {
  when(
    () => repository.dashboard(),
  ).thenAnswer((_) async => PhotoDashboard.empty());
  when(
    () => repository.listPhotos(
      query: any(named: 'query'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      sort: any(named: 'sort'),
    ),
  ).thenAnswer((invocation) async {
    observedQueries.add(invocation.namedArguments[#query] as String?);
    return _page(photos);
  });
  when(
    () => repository.listFavorites(
      query: any(named: 'query'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      sort: any(named: 'sort'),
    ),
  ).thenAnswer((_) async => PhotoPage.empty());
  when(
    () => repository.listAlbumsPage(
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => PhotoAlbumPage.empty());
  when(
    () => repository.listTrash(
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => PhotoPage.empty());
}

void main() {
  test('服务端命中的条目不因标题不含关键词而被本地复筛删除', () async {
    final repository = _MockPhotoRepository();
    final observedQueries = <String?>[];
    _stubLibrary(
      repository,
      photos: <PhotoItem>[_photoByTagHit()],
      observedQueries: observedQueries,
    );
    final container = ProviderContainer.test(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(photoCenterControllerProvider.future);
    container
        .read(photoCenterControllerProvider.notifier)
        .setSearchQuery('东京塔');
    // 查询经 300ms 防抖后重查当前页。
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final state = container.read(photoCenterControllerProvider).requireValue;
    expect(state.searchQuery, '东京塔');
    // 关键词必须进请求，结果由数据侧覆盖全库。
    expect(observedQueries, contains('东京塔'));
    expect(state.photos.map((item) => item.id), <String>['img-2048']);
    expect(state.visiblePhotos.map((item) => item.id), <String>['img-2048']);
  });
}
