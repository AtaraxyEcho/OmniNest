import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/data/task_api.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

class _MockTaskApi extends Mock implements TaskApi {}

PhotoItem _photo(String id) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2026),
  );
}

PhotoPage _page(List<PhotoItem> items, {required int total}) {
  return PhotoPage(
    items: items,
    page: 0,
    size: 50,
    totalElements: total,
    totalPages: 1,
  );
}

void _stubRepository(
  _MockPhotoRepository repository, {
  required List<PhotoItem> Function() trashReader,
}) {
  when(() => repository.dashboard()).thenAnswer(
    (_) async => PhotoDashboard(
      totalPhotos: 1,
      totalAlbums: 0,
      totalFavorites: 0,
      trashCount: trashReader().length,
      recentPhotos: const [],
      favoritePhotos: const [],
    ),
  );
  when(
    () => repository.listPhotos(
      query: any(named: 'query'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      sort: any(named: 'sort'),
    ),
  ).thenAnswer((_) async => PhotoPage.empty());
  when(
    () => repository.listFavorites(
      query: any(named: 'query'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      sort: any(named: 'sort'),
    ),
  ).thenAnswer((_) async => PhotoPage.empty());
  when(
    () => repository.listAlbums(),
  ).thenAnswer((_) async => const <PhotoAlbum>[]);
  when(
    () => repository.listTrash(
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async {
    final items = trashReader();
    return _page(items, total: items.length);
  });
  when(
    () => repository.purgePhoto(any(), cascade: any(named: 'cascade')),
  ).thenAnswer(
    (_) async => const TaskSubmission(taskId: 'task-purge', status: 'QUEUED'),
  );
  when(() => repository.purgeTrash()).thenAnswer(
    (_) async =>
        const TaskSubmission(taskId: 'task-purge-all', status: 'QUEUED'),
  );
}

void main() {
  test('永久删除回收站照片后立即从本地回收站移除，不依赖 Worker 落库', () async {
    final repository = _MockPhotoRepository();
    final taskApi = _MockTaskApi();
    when(
      () => taskApi.list(page: any(named: 'page'), size: any(named: 'size')),
    ).thenAnswer((_) async => <TaskRecord>[]);
    final serverTrash = <PhotoItem>[_photo('t1'), _photo('t2')];
    _stubRepository(repository, trashReader: () => List.of(serverTrash));
    when(
      () => repository.purgePhoto(any(), cascade: any(named: 'cascade')),
    ).thenAnswer((invocation) async {
      serverTrash.removeWhere((photo) => photo.id == 't1');
      return const TaskSubmission(taskId: 'task-purge', status: 'QUEUED');
    });

    final container = ProviderContainer.test(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        taskApiProvider.overrideWithValue(taskApi),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(photoCenterControllerProvider.notifier);
    await container.read(photoCenterControllerProvider.future);
    await controller.loadTrashPage(force: true);
    expect(
      container.read(photoCenterControllerProvider).requireValue.trashPhotos,
      hasLength(2),
    );

    await controller.purgePhotoFromTrash('t1');

    final state = container.read(photoCenterControllerProvider).requireValue;
    expect(state.trashPhotos.map((item) => item.id), <String>['t2']);
    expect(state.trashTotalElements, 1);
    expect(state.dashboard.trashCount, 1);
  });

  test('清空回收站任务提交后立即清空本地回收站列表', () async {
    final repository = _MockPhotoRepository();
    final taskApi = _MockTaskApi();
    when(
      () => taskApi.list(page: any(named: 'page'), size: any(named: 'size')),
    ).thenAnswer((_) async => <TaskRecord>[]);
    final serverTrash = <PhotoItem>[_photo('t1'), _photo('t2')];
    _stubRepository(repository, trashReader: () => List.of(serverTrash));
    when(() => repository.purgeTrash()).thenAnswer((_) async {
      serverTrash.clear();
      return const TaskSubmission(taskId: 'task-purge-all', status: 'QUEUED');
    });

    final container = ProviderContainer.test(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        taskApiProvider.overrideWithValue(taskApi),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(photoCenterControllerProvider.notifier);
    await container.read(photoCenterControllerProvider.future);
    await controller.loadTrashPage(force: true);

    await controller.purgeTrash();

    final state = container.read(photoCenterControllerProvider).requireValue;
    expect(state.trashPhotos, isEmpty);
    expect(state.trashTotalElements, 0);
  });

  test('回收站 404 时视为已删除并刷新列表', () async {
    final repository = _MockPhotoRepository();
    final taskApi = _MockTaskApi();
    when(
      () => taskApi.list(page: any(named: 'page'), size: any(named: 'size')),
    ).thenAnswer((_) async => <TaskRecord>[]);
    final serverTrash = <PhotoItem>[_photo('t1')];
    _stubRepository(repository, trashReader: () => List.of(serverTrash));
    when(
      () => repository.purgePhoto(any(), cascade: any(named: 'cascade')),
    ).thenAnswer((_) async {
      // 服务端已无该照片，返回 404；随后应本地移除并按空列表补查。
      serverTrash.clear();
      throw const AppException(code: 'NOT_FOUND', message: '回收站中不存在该图片');
    });

    final container = ProviderContainer.test(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        taskApiProvider.overrideWithValue(taskApi),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(photoCenterControllerProvider.notifier);
    await container.read(photoCenterControllerProvider.future);
    await controller.loadTrashPage(force: true);

    await expectLater(
      controller.purgePhotoFromTrash('t1'),
      throwsA(isA<AppException>()),
    );
    await controller.loadTrashPage(force: true);

    final state = container.read(photoCenterControllerProvider).requireValue;
    expect(state.trashPhotos, isEmpty);
  });

  test('实时刷新在回收站已有数据时会重新拉取回收站', () async {
    final repository = _MockPhotoRepository();
    final taskApi = _MockTaskApi();
    when(
      () => taskApi.list(page: any(named: 'page'), size: any(named: 'size')),
    ).thenAnswer((_) async => <TaskRecord>[]);
    final serverTrash = <PhotoItem>[_photo('t1')];
    _stubRepository(repository, trashReader: () => List.of(serverTrash));

    final container = ProviderContainer.test(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        taskApiProvider.overrideWithValue(taskApi),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(photoCenterControllerProvider.notifier);
    await container.read(photoCenterControllerProvider.future);
    await controller.loadTrashPage(force: true);
    expect(
      container.read(photoCenterControllerProvider).requireValue.trashPhotos,
      hasLength(1),
    );

    // 模拟 Worker 已落库删除，服务端回收站变空。
    serverTrash.clear();
    await controller.refreshForRealtime();

    final state = container.read(photoCenterControllerProvider).requireValue;
    expect(state.trashPhotos, isEmpty);
  });
}
