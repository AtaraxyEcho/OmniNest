import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_group.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/data/task_api.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

void main() {
  test('照片控制器按页追加且保留总数', () async {
    final repository = _MockPhotoRepository();
    _stubCommon(repository);
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((invocation) async {
      final page = invocation.namedArguments[#page] as int;
      return page == 0
          ? _page(<PhotoItem>[_photo('one'), _photo('two')], total: 3)
          : _page(<PhotoItem>[_photo('three')], page: 1, total: 3);
    });
    final container = ProviderContainer.test(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(photoCenterControllerProvider.future);
    await container
        .read(photoCenterControllerProvider.notifier)
        .loadMoreVisiblePhotos();

    final state = container.read(photoCenterControllerProvider).requireValue;
    expect(state.photos.map((item) => item.id), <String>[
      'one',
      'two',
      'three',
    ]);
    expect(state.photoPage, 1);
    expect(state.photoTotalElements, 3);
    expect(state.hasMorePhotos, isFalse);
  });

  test('实时刷新只替换首屏并保留已加载窗口长度', () async {
    final repository = _MockPhotoRepository();
    _stubCommon(repository);
    var realtimeRefresh = false;
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((invocation) async {
      final page = invocation.namedArguments[#page] as int;
      if (realtimeRefresh) {
        return _page(<PhotoItem>[_photo('new'), _photo('one')], total: 4);
      }
      return page == 0
          ? _page(<PhotoItem>[_photo('one'), _photo('two')], total: 3)
          : _page(<PhotoItem>[_photo('three')], page: 1, total: 3);
    });
    final container = ProviderContainer.test(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(photoCenterControllerProvider.future);
    final controller = container.read(photoCenterControllerProvider.notifier);
    await controller.loadMoreVisiblePhotos();

    realtimeRefresh = true;
    await controller.refreshForRealtime();

    final state = container.read(photoCenterControllerProvider).requireValue;
    expect(state.photos, hasLength(3));
    expect(state.photos.map((item) => item.id), <String>['new', 'one', 'two']);
    expect(state.photoTotalElements, 4);
  });

  test('时间线按月份页去重追加并保留总数', () async {
    final repository = _MockPhotoRepository();
    _stubCommon(repository);
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((_) async => PhotoPage.empty());
    when(
      () => repository.getTimeline(
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((invocation) async {
      final page = invocation.namedArguments[#page] as int;
      return page == 0
          ? _timelinePage([
            _timelineEntry(2026, 7),
            _timelineEntry(2026, 6),
          ], total: 3)
          : _timelinePage(
            [_timelineEntry(2026, 6), _timelineEntry(2026, 5)],
            page: 1,
            total: 3,
          );
    });
    final container = ProviderContainer.test(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(photoCenterControllerProvider.future);
    final controller = container.read(photoCenterControllerProvider.notifier);

    await controller.loadTimeline();
    await controller.loadMoreTimeline();

    final state = container.read(photoCenterControllerProvider).requireValue;
    expect(state.timeline!.monthEntries.map((entry) => entry.key), <String>[
      '2026-7',
      '2026-6',
      '2026-5',
    ]);
    expect(state.timelinePage, 1);
    expect(state.timelineTotalElements, 3);
    expect(state.hasMoreTimeline, isFalse);
  });

  test('照片分组按页去重追加并保留当前维度', () async {
    final repository = _MockPhotoRepository();
    _stubCommon(repository);
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((_) async => PhotoPage.empty());
    when(
      () => repository.getGroups(
        any(),
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((invocation) async {
      final page = invocation.namedArguments[#page] as int;
      return page == 0
          ? _groupPage([_group('jpg'), _group('png')], total: 3)
          : _groupPage([_group('png'), _group('raw')], page: 1, total: 3);
    });
    final container = ProviderContainer.test(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(photoCenterControllerProvider.future);
    final controller = container.read(photoCenterControllerProvider.notifier);

    await controller.loadGroups(GroupBy.format);
    await controller.loadMoreGroups();

    final state = container.read(photoCenterControllerProvider).requireValue;
    expect(state.groups!.map((group) => group.groupKey), <String>[
      'jpg',
      'png',
      'raw',
    ]);
    expect(state.groupBy, GroupBy.format);
    expect(state.groupPage, 1);
    expect(state.groupTotalElements, 3);
    expect(state.hasMoreGroups, isFalse);
  });

  test('导入完成回调会更新照片列表和仪表盘', () async {
    final repository = _MockPhotoRepository();
    _stubCommon(repository);
    var dashboardCalls = 0;
    var listCalls = 0;
    when(() => repository.dashboard()).thenAnswer((_) async {
      dashboardCalls++;
      if (dashboardCalls == 1) return PhotoDashboard.empty();
      return PhotoDashboard(
        totalPhotos: 1,
        totalAlbums: 0,
        totalFavorites: 0,
        recentPhotos: <PhotoItem>[_photo('imported')],
        favoritePhotos: const <PhotoItem>[],
      );
    });
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((_) async {
      listCalls++;
      return listCalls == 1
          ? PhotoPage.empty()
          : _page(<PhotoItem>[_photo('imported')], total: 1);
    });
    final container = ProviderContainer.test(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(photoCenterControllerProvider.future);

    await container
        .read(photoCenterControllerProvider.notifier)
        .refreshAfterImport();

    final state = container.read(photoCenterControllerProvider).requireValue;
    expect(state.dashboard.totalPhotos, 1);
    expect(state.photos.map((photo) => photo.id), <String>['imported']);
  });

  test('导入刷新按文件节点 ID确认重复文件并保留搜索条件', () async {
    final repository = _MockPhotoRepository();
    _stubCommon(repository);
    final existing = _photo('existing');
    var dashboardCalls = 0;
    when(() => repository.dashboard()).thenAnswer((_) async {
      dashboardCalls++;
      return PhotoDashboard(
        totalPhotos: 1,
        totalAlbums: 0,
        totalFavorites: 0,
        recentPhotos: <PhotoItem>[existing],
        favoritePhotos: const <PhotoItem>[],
      );
    });
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((invocation) async {
      final query = invocation.namedArguments[#query] as String?;
      return _page(
        query == 'holiday' ? <PhotoItem>[existing] : const <PhotoItem>[],
        total: query == 'holiday' ? 1 : 0,
      );
    });
    final container = ProviderContainer.test(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(photoCenterControllerProvider.future);
    final controller = container.read(photoCenterControllerProvider.notifier);

    controller.setSearchQuery('holiday');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await controller.refreshAfterImport(
      expectedFileIds: <String>['file-existing'],
    );

    final state = container.read(photoCenterControllerProvider).requireValue;
    expect(state.searchQuery, 'holiday');
    expect(state.photos.single.fileNodeId, 'file-existing');
    expect(dashboardCalls, greaterThanOrEqualTo(2));
    verify(
      () => repository.listPhotos(
        query: 'holiday',
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).called(greaterThanOrEqualTo(1));
  });

  test('重复触发导入刷新会合并为单个请求', () async {
    final repository = _MockPhotoRepository();
    _stubCommon(repository);
    final gate = Completer<void>();
    var holdRefresh = false;
    when(() => repository.dashboard()).thenAnswer((_) async {
      if (holdRefresh) {
        await gate.future;
      }
      return holdRefresh && gate.isCompleted
          ? const PhotoDashboard(
            totalPhotos: 1,
            totalAlbums: 0,
            totalFavorites: 0,
            recentPhotos: <PhotoItem>[],
            favoritePhotos: <PhotoItem>[],
          )
          : PhotoDashboard.empty();
    });
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((_) async => PhotoPage.empty());
    final container = ProviderContainer.test(
      overrides: [photoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(photoCenterControllerProvider.future);
    final controller = container.read(photoCenterControllerProvider.notifier);

    holdRefresh = true;
    final first = controller.refreshAfterImport();
    final second = controller.refreshAfterImport();
    expect(identical(first, second), isTrue);
    gate.complete();
    await Future.wait(<Future<bool>>[first, second]);
  });

  test('导入刷新使用后台任务终态确认完成', () async {
    final repository = _MockPhotoRepository();
    final taskApi = _MockTaskApi();
    _stubCommon(repository);
    var refreshCount = 0;
    when(() => repository.dashboard()).thenAnswer((_) async {
      refreshCount++;
      return refreshCount <= 2
          ? PhotoDashboard.empty()
          : PhotoDashboard(
            totalPhotos: 1,
            totalAlbums: 0,
            totalFavorites: 0,
            recentPhotos: <PhotoItem>[_photo('imported')],
            favoritePhotos: const <PhotoItem>[],
          );
    });
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((_) async {
      return refreshCount > 2
          ? _page(<PhotoItem>[_photo('imported')], total: 1)
          : PhotoPage.empty();
    });
    when(
      () => taskApi.get('import-task'),
    ).thenAnswer((_) async => _task('import-task', status: 'COMPLETED'));
    final container = ProviderContainer.test(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        taskApiProvider.overrideWithValue(taskApi),
      ],
    );
    addTearDown(container.dispose);
    await container.read(photoCenterControllerProvider.future);

    final visible = await container
        .read(photoCenterControllerProvider.notifier)
        .refreshAfterImport(
          expectedFileIds: <String>['file-imported'],
          taskIds: <String>['import-task'],
        );

    expect(visible, isTrue);
    verify(() => taskApi.get('import-task')).called(1);
  });

  test('导入刷新在后台任务失败时返回失败原因', () async {
    final repository = _MockPhotoRepository();
    final taskApi = _MockTaskApi();
    _stubCommon(repository);
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((_) async => PhotoPage.empty());
    when(() => taskApi.get('failed-task')).thenAnswer(
      (_) async =>
          _task('failed-task', status: 'DLQ', errorMessage: '安全扫描服务不可用，文件已隔离'),
    );
    final container = ProviderContainer.test(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        taskApiProvider.overrideWithValue(taskApi),
      ],
    );
    addTearDown(container.dispose);
    await container.read(photoCenterControllerProvider.future);

    final controller = container.read(photoCenterControllerProvider.notifier);
    final visible = await controller.refreshAfterImport(
      expectedFileIds: <String>['file-failed'],
      taskIds: <String>['failed-task'],
    );

    expect(visible, isFalse);
    expect(controller.lastImportNotice, PhotoImportNotice.backendFailed);
    expect(controller.lastImportDetail, '安全扫描服务不可用，文件已隔离');
  });

  test('照片移入回收站后乐观移除并刷新列表', () async {
    final repository = _MockPhotoRepository();
    final taskApi = _MockTaskApi();
    _stubCommon(repository);
    when(
      () => taskApi.list(page: any(named: 'page'), size: any(named: 'size')),
    ).thenAnswer((_) async => const <TaskRecord>[]);
    when(() => repository.dashboard()).thenAnswer(
      (_) async => PhotoDashboard(
        totalPhotos: 2,
        totalAlbums: 0,
        totalFavorites: 0,
        recentPhotos: <PhotoItem>[_photo('one'), _photo('two')],
        favoritePhotos: const <PhotoItem>[],
      ),
    );
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer(
      (_) async => _page(<PhotoItem>[_photo('one'), _photo('two')], total: 2),
    );
    when(() => repository.movePhotoToTrash('one')).thenAnswer((_) async {});
    var listCalls = 0;
    when(
      () => repository.listPhotos(
        query: any(named: 'query'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((_) {
      listCalls++;
      return Future.value(
        _page(
          listCalls == 1
              ? <PhotoItem>[_photo('one'), _photo('two')]
              : <PhotoItem>[_photo('two')],
          total: listCalls == 1 ? 2 : 1,
        ),
      );
    });
    final container = ProviderContainer.test(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        taskApiProvider.overrideWithValue(taskApi),
      ],
    );
    addTearDown(container.dispose);
    await container.read(photoCenterControllerProvider.future);

    await container
        .read(photoCenterControllerProvider.notifier)
        .movePhotoToTrash('one');

    final state = container.read(photoCenterControllerProvider).requireValue;
    // 移入回收站后乐观移除并刷新列表，刷新结果仅剩剩余照片。
    expect(state.photos.map((photo) => photo.id), <String>['two']);
    verify(() => repository.movePhotoToTrash('one')).called(1);
  });
}

void _stubCommon(_MockPhotoRepository repository) {
  when(
    () => repository.dashboard(),
  ).thenAnswer((_) async => PhotoDashboard.empty());
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
  ).thenAnswer((_) async => PhotoPage.empty());
}

PhotoPage _page(List<PhotoItem> items, {int page = 0, required int total}) {
  return PhotoPage(
    items: items,
    page: page,
    size: 50,
    totalElements: total,
    totalPages: total > items.length ? 2 : 1,
  );
}

PhotoTimelinePage _timelinePage(
  List<PhotoTimelineMonthEntry> items, {
  int page = 0,
  required int total,
}) {
  return PhotoTimelinePage(
    items: items,
    page: page,
    size: 50,
    totalElements: total,
    totalPages: total > items.length ? 2 : 1,
  );
}

PhotoTimelineMonthEntry _timelineEntry(int year, int month) {
  return PhotoTimelineMonthEntry(
    year: year,
    monthGroup: PhotoMonthGroup(
      month: month,
      photoCount: 1,
      previewPhotos: [_photo('$year-$month')],
    ),
  );
}

PhotoGroupPage _groupPage(
  List<PhotoGroup> items, {
  int page = 0,
  required int total,
}) {
  return PhotoGroupPage(
    items: items,
    page: page,
    size: 50,
    totalElements: total,
    totalPages: total > items.length ? 2 : 1,
  );
}

PhotoGroup _group(String key) {
  return PhotoGroup(groupKey: key, photoCount: 1, photos: [_photo(key)]);
}

PhotoItem _photo(String id) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: id,
    format: 'jpg',
    fileSize: 1,
    metadataStatus: 'MATCHED',
    favorite: false,
    createdAt: DateTime(2026),
  );
}

TaskRecord _task(String id, {required String status, String? errorMessage}) {
  return TaskRecord(
    id: id,
    taskType: 'MEDIA_AUTO_IMPORT',
    status: status,
    errorMessage: errorMessage,
    retryCount: 0,
    maxRetries: 3,
    createdAt: DateTime(2026),
  );
}

class _MockPhotoRepository extends Mock implements PhotoRepository {}

class _MockTaskApi extends Mock implements TaskApi {}
