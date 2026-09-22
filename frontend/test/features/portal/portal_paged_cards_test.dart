import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/portal/application/portal_paged_cards.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_paged_list_card.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/domain/reader_item.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

MovieContinueWatching _movie(String id) {
  return MovieContinueWatching(
    id: id,
    title: 'Movie $id',
    positionSeconds: 60,
    durationSeconds: 600,
    progressPercent: 10,
  );
}

MovieVideoItem _libraryMovie(String id, {String year = '2026'}) {
  return MovieVideoItem.fromJson(<String, dynamic>{
    'id': id,
    'fileNodeId': 'node-$id',
    'mediaType': 'MOVIE',
    'title': 'Library $id',
    'metadataStatus': 'MATCHED',
    'nfoStatus': 'NONE',
    'releaseDate': '$year-01-01T00:00:00Z',
    'updatedAt': '2026-09-20T00:00:00Z',
    'metadata': <String, dynamic>{'year': year},
  });
}

class _PagedMovieApi implements MovieApi {
  _PagedMovieApi(this.full);

  final List<MovieContinueWatching> full;
  int continueWatchingCalls = 0;

  @override
  Future<List<MovieContinueWatching>> continueWatching() async {
    continueWatchingCalls += 1;
    return full;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MergedVideoApi implements MovieApi {
  _MergedVideoApi({required this.watching, required this.recentMovies});

  final List<MovieContinueWatching> watching;
  final List<MovieVideoItem> recentMovies;
  int continueCalls = 0;
  int recentCalls = 0;

  @override
  Future<List<MovieContinueWatching>> continueWatching() async {
    continueCalls += 1;
    return watching;
  }

  @override
  Future<List<MovieVideoItem>> recent({int days = 30}) async {
    recentCalls += 1;
    return recentMovies;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PagedReaderApi implements ReaderApi {
  _PagedReaderApi(this.full);

  final List<ReaderItem> full;
  int itemCalls = 0;

  @override
  Future<List<ReaderItem>> items({String? itemType, String? query}) async {
    itemCalls += 1;
    return full;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('影视卡客户端分窗：首屏 10 条，追加到耗尽即止', () async {
    final full = List<MovieContinueWatching>.generate(23, (i) => _movie('$i'));
    final api = _PagedMovieApi(full);
    final container = ProviderContainer(
      overrides: [movieApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      portalContinueWatchingProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    var state = await container.read(portalContinueWatchingProvider.future);
    expect(state.items, hasLength(10));
    expect(state.hasMore, isTrue);

    await container.read(portalContinueWatchingProvider.notifier).loadMore();
    state = await container.read(portalContinueWatchingProvider.future);
    expect(state.items, hasLength(20));
    // 完整列表只取一次，分窗不重复请求。
    expect(api.continueWatchingCalls, 1);

    await container.read(portalContinueWatchingProvider.notifier).loadMore();
    state = await container.read(portalContinueWatchingProvider.future);
    expect(state.items, hasLength(23));
    expect(state.hasMore, isFalse);

    // 耗尽后再触发为空操作。
    await container.read(portalContinueWatchingProvider.notifier).loadMore();
    state = await container.read(portalContinueWatchingProvider.future);
    expect(state.items, hasLength(23));
  });

  test('refresh 按已加载量对齐重拉第一页', () async {
    final full = List<MovieContinueWatching>.generate(30, (i) => _movie('$i'));
    final api = _PagedMovieApi(full);
    final container = ProviderContainer(
      overrides: [movieApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      portalContinueWatchingProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(portalContinueWatchingProvider.future);
    await container.read(portalContinueWatchingProvider.notifier).loadMore();

    // 数据变化后刷新：一次请求即可拿到对齐量的新数据。
    full[0] = _movie('replaced');
    await container.read(portalContinueWatchingProvider.notifier).refresh();
    final state = await container.read(portalContinueWatchingProvider.future);
    expect(state.items, hasLength(20));
    expect(state.items.first.id, 'replaced');
    expect(api.continueWatchingCalls, 2);
  });

  testWidgets('卡片内滚动接近底部触发无感追加', (tester) async {
    final full = List<MovieContinueWatching>.generate(45, (i) => _movie('$i'));
    final api = _PagedMovieApi(full);
    final container = ProviderContainer(
      overrides: [movieApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 420,
                child: PortalPagedListCard<MovieContinueWatching>(
                  provider: portalContinueWatchingProvider,
                  headerIcon: Icons.movie_outlined,
                  headerTitle: '继续观看',
                  openRoute: '/video',
                  emptyMessage: '暂无内容',
                  rowBuilder:
                      (item) => SizedBox(height: 64, child: Text(item.title)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Movie 0'), findsOneWidget);

    // 滚到接近底部触发追加加载。
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pumpAndSettle();

    final state = await container.read(portalContinueWatchingProvider.future);
    expect(state.items.length, greaterThan(10));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('书架浏览客户端分窗且 refresh 重取列表', () async {
    final full = List<ReaderItem>.generate(
      24,
      (i) => ReaderItem(
        id: 'book-$i',
        title: 'Book $i',
        itemType: 'EPUB',
        updatedAt: DateTime.utc(2026, 9, 20),
      ),
    );
    final api = _PagedReaderApi(full);
    final container = ProviderContainer(
      overrides: [readerApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      portalReaderShelfProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    var state = await container.read(portalReaderShelfProvider.future);
    expect(state.items, hasLength(10));
    expect(state.hasMore, isTrue);
    expect(api.itemCalls, 1);

    await container.read(portalReaderShelfProvider.notifier).loadMore();
    state = await container.read(portalReaderShelfProvider.future);
    expect(state.items, hasLength(20));

    await container.read(portalReaderShelfProvider.notifier).loadMore();
    state = await container.read(portalReaderShelfProvider.future);
    expect(state.items, hasLength(24));
    expect(state.hasMore, isFalse);
    expect(api.itemCalls, 1);

    // refresh 清缓存重取：跨端新导入的书立即可见。
    full.insert(
      0,
      ReaderItem(
        id: 'book-new',
        title: 'Newly Imported',
        itemType: 'EPUB',
        updatedAt: DateTime.utc(2026, 9, 20),
      ),
    );
    await container.read(portalReaderShelfProvider.notifier).refresh();
    state = await container.read(portalReaderShelfProvider.future);
    expect(state.items.first.id, 'book-new');
    // 已加载 24 条 → 对齐刷新按 30 取整，返回现有全部 25 条，不回跳。
    expect(state.items, hasLength(25));
    expect(api.itemCalls, 2);
  });

  test('影视预览合并继续观看与最近添加：续播在前、去重', () async {
    final api = _MergedVideoApi(
      watching: <MovieContinueWatching>[_movie('watch-1'), _movie('shared')],
      recentMovies: <MovieVideoItem>[
        _libraryMovie('shared'),
        _libraryMovie('new-1'),
        _libraryMovie('new-2'),
      ],
    );
    final container = ProviderContainer(
      overrides: [movieApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      portalVideoPreviewProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final state = await container.read(portalVideoPreviewProvider.future);

    // 2 条续播 + 2 条最近添加（shared 去重），续播在前。
    expect(state.items.map((item) => item.id), [
      'watch-1',
      'shared',
      'new-1',
      'new-2',
    ]);
    expect(state.totalElements, 4);
    expect(state.items[0].isContinueWatching, isTrue);
    expect(state.items[1].progressPercent, isNotNull);
    expect(state.items[2].isContinueWatching, isFalse);
    expect(state.items[2].route, '/video/new-1');
    expect(state.items[2].secondaryText, '2026');
    expect(api.continueCalls, 1);
    expect(api.recentCalls, 1);
  });

  test('影视预览 refresh 清缓存重取两个来源', () async {
    final api = _MergedVideoApi(
      watching: <MovieContinueWatching>[_movie('watch-1')],
      recentMovies: <MovieVideoItem>[_libraryMovie('new-1')],
    );
    final container = ProviderContainer(
      overrides: [movieApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      portalVideoPreviewProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(portalVideoPreviewProvider.future);
    await container.read(portalVideoPreviewProvider.notifier).refresh();

    expect(api.continueCalls, 2);
    expect(api.recentCalls, 2);
  });
}
