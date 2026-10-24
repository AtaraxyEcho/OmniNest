import 'dart:typed_data';
import 'package:omninest/app/session/session_epoch.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

export 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/application/movie_providers.dart';

export 'package:omninest/features/video/application/movie_providers.dart';

part 'movie_center_commands.dart';
part 'movie_center_paging.dart';

final latestMediaScanRunProvider = StreamProvider.autoDispose
    .family<MediaScanRun?, String>((ref, sourceId) async* {
      final api = ref.watch(movieApiProvider);
      // 连续网络/服务错误次数，达到阈值后抛出，避免无限重试掩盖真实故障。
      var consecutiveErrors = 0;
      while (true) {
        MediaScanRun? run;
        try {
          run = await api.latestMediaScanRun(sourceId);
          consecutiveErrors = 0;
        } catch (_) {
          // 网络抖动或服务临时不可用：短暂退避后重试，避免轮询流直接终止。
          if (++consecutiveErrors >= 3) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(seconds: 3));
          continue;
        }
        yield run;
        if (run == null || !run.active) {
          if (run != null) {
            ref.invalidate(videoLibrarySourcesProvider);
            if (run.status == 'COMPLETED' || run.status == 'PARTIAL') {
              // 面板重新挂载会重启轮询流；同一完成 run 只触发一次中心数据
              // 重载，否则管理页每次进入都会全量刷新并在历史缺陷下反复跳回
              // 电影分区。
              final handled = ref.read(handledCompletedScanRunIdsProvider);
              if (handled.add(run.id)) {
                if (handled.length > 128) {
                  handled.clear();
                  handled.add(run.id);
                }
                ref.invalidate(movieCenterControllerProvider);
              }
            }
          }
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    });

final videoLibrarySourceActionsProvider = Provider<VideoLibrarySourceActions>((
  ref,
) {
  return VideoLibrarySourceActions(ref);
});

/// 批量扫描结果：成功/失败计数与最后一条错误摘要。
class ScanAllResult {
  const ScanAllResult({
    required this.success,
    required this.failed,
    this.lastError,
  });

  final int success;
  final int failed;
  final String? lastError;
}

class VideoLibrarySourceActions {
  const VideoLibrarySourceActions(this.ref);

  final Ref ref;

  MovieApi get _api => ref.read(movieApiProvider);

  Future<void> create({
    required String name,
    String? storageLocationId,
    String? mountKey,
    required String relativeRoot,
    required VideoLibraryType libraryType,
  }) async {
    await _api.createLibrarySource(
      name: name,
      storageLocationId: storageLocationId,
      mountKey: mountKey,
      relativeRoot: relativeRoot,
      libraryType: libraryType,
    );
    ref.invalidate(videoLibrarySourcesProvider);
    // 挂载直达会在服务端新建存储位置，位置下拉需要同步刷新。
    ref.invalidate(videoStorageLocationsProvider);
  }

  /// 按约定目录开通/更新挂载媒体库（Movie/TV/Anime 三库源）。
  Future<void> provisionMountLibrary({
    required String mountKey,
    required bool enabled,
    required bool autoImport,
  }) async {
    await _api.provisionMountLibrary(
      mountKey: mountKey,
      enabled: enabled,
      autoImport: autoImport,
    );
    ref.invalidate(videoLibrarySourcesProvider);
    ref.invalidate(videoStorageLocationsProvider);
  }

  Future<void> update({
    required VideoLibrarySource source,
    required String name,
    required String relativeRoot,
    required VideoLibraryType libraryType,
    required bool enabled,
  }) async {
    await _api.updateLibrarySource(
      sourceId: source.id,
      name: name,
      relativeRoot: relativeRoot,
      libraryType: libraryType,
      enabled: enabled,
    );
    ref.invalidate(videoLibrarySourcesProvider);
  }

  Future<void> delete(String sourceId) async {
    await _api.deleteLibrarySource(sourceId);
    ref.invalidate(videoLibrarySourcesProvider);
  }

  Future<MediaLibraryAccessSettings> updateAccess({
    required String sourceId,
    required MediaLibraryVisibility visibility,
    required Set<String> userIds,
    required int expectedVersion,
  }) async {
    final settings = await _api.updateLibraryAccess(
      sourceId: sourceId,
      visibility: visibility,
      userIds: userIds,
      expectedVersion: expectedVersion,
    );
    ref.invalidate(mediaLibraryAccessProvider(sourceId));
    ref.invalidate(videoLibrarySourcesProvider);
    return settings;
  }

  Future<ScrapeTask> scan(String sourceId) async {
    final task = await _api.discoverLibrarySource(sourceId);
    ref.invalidate(videoLibrarySourcesProvider);
    ref.invalidate(latestMediaScanRunProvider(sourceId));
    return task;
  }

  /// 批量扫描多个库源；返回成功/失败计数与最后一条错误摘要。
  Future<ScanAllResult> scanAll(List<String> sourceIds) async {
    var success = 0;
    var failed = 0;
    String? lastError;
    for (final sourceId in sourceIds) {
      try {
        await scan(sourceId);
        success++;
      } on Exception catch (error) {
        failed++;
        lastError = error.toString();
      }
    }
    return ScanAllResult(
      success: success,
      failed: failed,
      lastError: lastError,
    );
  }

  Future<MediaSelectionSummary> updateSelection({
    required MediaScanRun run,
    required String nodeId,
    required bool selected,
    int? expectedRevision,
  }) async {
    final summary = await _api.updateMediaSelection(
      runId: run.id,
      nodeId: nodeId,
      selected: selected,
      expectedRevision: expectedRevision ?? run.selectionRevision,
    );
    ref.invalidate(latestMediaScanRunProvider(run.librarySourceId));
    ref.invalidate(mediaScanTreeProvider);
    return summary;
  }

  Future<ScrapeTask> apply(MediaScanRun run, {int? expectedRevision}) async {
    final task = await _api.applyMediaSelection(
      runId: run.id,
      expectedRevision: expectedRevision ?? run.selectionRevision,
    );
    ref.invalidate(latestMediaScanRunProvider(run.librarySourceId));
    return task;
  }

  Future<void> pause(MediaScanRun run) async {
    await _api.pauseMediaScanRun(run.id);
    ref.invalidate(latestMediaScanRunProvider(run.librarySourceId));
  }

  Future<void> cancel(MediaScanRun run) async {
    await _api.cancelMediaScanRun(run.id);
    ref.invalidate(latestMediaScanRunProvider(run.librarySourceId));
    ref.invalidate(videoLibrarySourcesProvider);
  }
}

final movieCenterControllerProvider =
    AsyncNotifierProvider<MovieCenterController, MovieCenterState>(
      MovieCenterController.new,
    );

class MovieCenterController extends AsyncNotifier<MovieCenterState> {
  /// `state` 与 `ref` 是受保护成员，拆到 part 的命令段经这两处出口读写。
  AsyncValue<MovieCenterState> get centerState => state;
  set centerState(AsyncValue<MovieCenterState> value) => state = value;

  Ref get centerRef => ref;

  /// 取数或远端动作完成后的回写基准。
  ///
  /// 完成回调不得拿 `await` 之前抓的快照整份发布：那段窗口里发生的写入（分区、视图模式、
  /// 筛选、分页窗口、加载标记）会被旧快照无声覆盖。优先取发布时刻的实况；实况尚未就绪
  /// （错误态、首帧取数）时退回快照，快照缺失由调用点按原有方式兜底。
  MovieCenterState _liveOr(MovieCenterState captured) =>
      state.asData?.value ?? captured;

  int _refreshGeneration = 0;
  int _moviePageGeneration = 0;
  int _episodePageGeneration = 0;
  final Map<MovieSection, int> _sectionLoadGenerations = {};
  Timer? _searchDebounce;

  /// controller 重建期间（实时刷新触发 invalidate）被点击但未生效的分区。
  MovieSection? _pendingSection;

  /// 已提交到数据侧的检索关键词：库内搜索覆盖全库，翻页与刷新都必须带同一
  /// 关键词，否则翻页会带回未过滤条目。
  String _searchKeyword = '';

  MovieApi get _api => ref.read(movieApiProvider);

  @override
  Future<MovieCenterState> build() async {
    // 换号时以依赖变化语义重建，避免渲染上一账号的旧值。
    ref.watch(sessionEpochProvider);
    final loaded = await _loadState();
    final section = _pendingSection ?? ref.read(movieCenterSectionProvider);
    _pendingSection = null;
    _searchDebounce?.cancel();
    final restored =
        section == loaded.section ? loaded : loaded.copyWith(section: section);
    // 恢复非电影分区时主动重载分区数据，避免管理页只显示空任务列表。
    if (restored.section != MovieSection.movies) {
      Future<void>.microtask(() => _loadSection(restored.section));
    }
    return restored;
  }

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    _moviePageGeneration++;
    _episodePageGeneration++;
    final current = state.asData?.value;
    final next = await _loadState();
    if (!ref.mounted || generation != _refreshGeneration) {
      return;
    }
    _applyRefreshedState(current, next);
    // 分区以刷新完成时的实况为准（进入页同步切栏/挂起待恢复分区都
    // 可能已改变）：用启动时快照回写会让模块落地旧分区（电影）。
    final liveSection =
        state.asData?.value.section ??
        _pendingSection ??
        current?.section ??
        MovieSection.movies;
    await _loadSection(liveSection, force: true);
  }

  /// 严格刷新实时事件涉及的影视数据并保留当前视图状态。
  Future<void> refreshForRealtime() async {
    final generation = ++_refreshGeneration;
    _moviePageGeneration++;
    _episodePageGeneration++;
    final current = state.asData?.value;
    final next = await _loadState();
    if (!ref.mounted || generation != _refreshGeneration) {
      return;
    }
    if (next.errorMessage != null) {
      throw StateError(next.errorMessage!);
    }
    _applyRefreshedState(current, next);
    await _loadSection(current?.section ?? MovieSection.movies, force: true);
  }

  void _applyRefreshedState(MovieCenterState? current, MovieCenterState next) {
    // 分区以回写时刻的实况为准：冷启动时页面在同一帧内先切栏再刷新，
    // 此处 current 是 build 完成前的空快照，沿用会把刚选定的深链分区
    // （或托管首栏 For you）静默退回电影。
    final liveSection =
        state.asData?.value.section ?? current?.section ?? next.section;
    // 回写基准同样以发布时刻的实况为准：`_loadState` 期间页面可能已切视图模式、
    // 改筛选或续页，整份发布 current 会把这些写入打回。
    state = AsyncData(
      _liveOr(
        current ??
            MovieCenterState(
              dashboard: MovieDashboard.empty(),
              movies: const [],
              recentItems: const [],
              continueWatching: const [],
              favoriteItems: const [],
              watchHistory: const [],
              collections: const [],
              tasks: const [],
            ),
      ).copyWith(
        section: liveSection,
        dashboard: next.dashboard,
        movies: next.movies,
        // 实时刷新时 seriesByType 失败会得到空列表；已有数据时保留旧值，
        // 避免刮削后网络/序列化异常把剧集/动漫分区清空。
        tvSeries:
            next.tvSeries.isNotEmpty
                ? next.tvSeries
                : current?.tvSeries ?? next.tvSeries,
        animeSeries:
            next.animeSeries.isNotEmpty
                ? next.animeSeries
                : current?.animeSeries ?? next.animeSeries,
        recentItems: next.recentItems,
        continueWatching: next.continueWatching,
        // 懒加载分区列表（收藏/历史/合集/任务）保留刷新前旧值：
        // loadedSections 仍重置，重进分区时重新拉取；避免 realtime
        // 高频刷新把未在展示的分区清成空列表。
        moviePage: next.moviePage,
        movieHasMore: next.movieHasMore,
        movieLoadingMore: false,
        episodePage: next.episodePage,
        episodeHasMore: next.episodeHasMore,
        episodeLoadingMore: false,
        loadedSections: next.loadedSections,
        loadingSections: const {},
      ),
    );
  }

  Future<void> scanLibrary({bool incremental = true}) async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    try {
      final task = await _api.scanLibrary(incremental: incremental);
      await refresh();
      final refreshed = state.asData?.value ?? current;
      state = AsyncData(refreshed.copyWith(lastTask: task));
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  Future<void> loadNextLibraryPage() async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    if (current.section == MovieSection.movies) {
      await _loadPage(movies: true);
      return;
    }
    if (current.section == MovieSection.tvShows ||
        current.section == MovieSection.anime ||
        current.section == MovieSection.management) {
      await _loadPage(movies: false);
    }
  }

  /// 按类型加载媒体库下一页；[movies] 为 true 加载电影分页，否则加载分集分页。
  /// [firstPage] 为 true 时忽略 hasMore 并从第 0 页开始（分集首次加载）。
  Future<bool> _loadPage({required bool movies, bool firstPage = false}) async {
    final current = state.asData?.value;
    if (current == null) {
      return false;
    }
    if (movies) {
      if (current.movieLoadingMore || (!firstPage && !current.movieHasMore)) {
        return false;
      }
    } else {
      if (current.episodeLoadingMore ||
          (!firstPage && !current.episodeHasMore)) {
        return true;
      }
    }
    final generation =
        movies ? ++_moviePageGeneration : ++_episodePageGeneration;
    final currentPage = movies ? current.moviePage : current.episodePage;
    final nextPage = firstPage || currentPage < 0 ? 0 : currentPage + 1;
    state = AsyncData(
      current.copyWith(
        movieLoadingMore: movies ? true : null,
        episodeLoadingMore: movies ? null : true,
      ),
    );
    try {
      final result = await _api.libraryPage(
        page: nextPage,
        mediaType: movies ? 'MOVIE' : 'EPISODE',
        keyword: _searchKeyword,
      );
      if (!ref.mounted ||
          generation !=
              (movies ? _moviePageGeneration : _episodePageGeneration)) {
        return false;
      }
      final latest = state.asData?.value;
      if (latest == null) {
        return false;
      }
      // 分集首次加载时丢弃旧分集，仅保留电影；其余场景全量合并去重。
      final baseItems =
          (!movies && firstPage)
              ? latest.movies.where((item) => item.mediaType == 'MOVIE')
              : latest.movies;
      final itemsById = {
        for (final item in baseItems) item.id: item,
        for (final item in result.items) item.id: item,
      };
      final hasMore = result.page + 1 < result.totalPages;
      state = AsyncData(
        latest.copyWith(
          movies: itemsById.values.toList(growable: false),
          moviePage: movies ? result.page : null,
          movieHasMore: movies ? hasMore : null,
          movieLoadingMore: movies ? false : null,
          episodePage: movies ? null : result.page,
          episodeHasMore: movies ? null : hasMore,
          episodeLoadingMore: movies ? null : false,
          clearError: true,
        ),
      );
      return true;
    } on Exception catch (error) {
      if (!ref.mounted ||
          generation !=
              (movies ? _moviePageGeneration : _episodePageGeneration)) {
        return false;
      }
      final latest = state.asData?.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            movieLoadingMore: movies ? false : null,
            episodeLoadingMore: movies ? null : false,
            errorMessage: describeUserFacingError(error).message,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _loadSection(MovieSection section, {bool force = false}) async {
    var current = state.asData?.value;
    if (current == null || current.loadingSections.contains(section)) {
      return;
    }
    if (!force && current.loadedSections.contains(section)) {
      return;
    }
    if (section == MovieSection.movies) {
      return;
    }
    if (section == MovieSection.tvShows || section == MovieSection.anime) {
      await _loadSeriesSection(section, force: force);
      return;
    }

    final generation = (_sectionLoadGenerations[section] ?? 0) + 1;
    _sectionLoadGenerations[section] = generation;
    // 首次加载展示骨架；已加载分区的强制刷新静默进行（实时事件高频触发，
    // 不能让影片管理等分区反复整块打回骨架）。
    final firstLoad = !current.loadedSections.contains(section);
    if (firstLoad) {
      final loading = Set<MovieSection>.from(current.loadingSections)
        ..add(section);
      state = AsyncData(current.copyWith(loadingSections: loading));
    }
    try {
      final result = await switch (section) {
        MovieSection.recent => _api.recent(),
        MovieSection.continueWatching => _api.continueWatching(),
        MovieSection.favorites => _loadFavoriteLists(),
        MovieSection.history => _api.historyPage(),
        MovieSection.collections => _api.collections(),
        MovieSection.management => _api.tasks(),
        _ => Future<Object?>.value(null),
      };
      if (!ref.mounted || _sectionLoadGenerations[section] != generation) {
        return;
      }
      final latest = state.asData?.value;
      if (latest == null) {
        return;
      }
      final loaded = Set<MovieSection>.from(latest.loadedSections)
        ..add(section);
      final stillLoading = Set<MovieSection>.from(latest.loadingSections)
        ..remove(section);
      state = AsyncData(switch (section) {
        MovieSection.recent => latest.copyWith(
          recentItems: result as List<MovieVideoItem>,
          loadedSections: loaded,
          loadingSections: stillLoading,
        ),
        MovieSection.continueWatching => latest.copyWith(
          continueWatching: result as List<MovieContinueWatching>,
          loadedSections: loaded,
          loadingSections: stillLoading,
        ),
        MovieSection.favorites => latest.copyWith(
          favoriteItems:
              ((result as List<Object>)[0] as MediaPage<MovieVideoItem>).items,
          favoriteSeries: (result[1] as MediaPage<MovieSeries>).items,
          favoritesPaging: _pagingOf(result[0] as MediaPage<MovieVideoItem>),
          favoriteSeriesPaging: _pagingOf(result[1] as MediaPage<MovieSeries>),
          loadedSections: loaded,
          loadingSections: stillLoading,
        ),
        MovieSection.history => () {
          final historyResult = result as MediaPage<MovieWatchHistory>;
          return latest.copyWith(
            watchHistory: historyResult.items,
            historyPaging: _pagingOf(historyResult),
            loadedSections: loaded,
            loadingSections: stillLoading,
          );
        }(),
        MovieSection.collections => latest.copyWith(
          collections: result as List<MovieCollection>,
          loadedSections: loaded,
          loadingSections: stillLoading,
        ),
        MovieSection.management => latest.copyWith(
          tasks: result as List<MovieTask>,
          loadedSections: loaded,
          loadingSections: stillLoading,
        ),
        _ => latest.copyWith(
          loadedSections: loaded,
          loadingSections: stillLoading,
        ),
      });
    } on Exception catch (error) {
      if (!ref.mounted || _sectionLoadGenerations[section] != generation) {
        return;
      }
      final latest = state.asData?.value;
      if (latest != null) {
        final stillLoading = Set<MovieSection>.from(latest.loadingSections)
          ..remove(section);
        state = AsyncData(
          latest.copyWith(
            loadingSections: stillLoading,
            errorMessage: describeUserFacingError(error).message,
          ),
        );
      }
    }
  }

  Future<void> _loadSeriesSection(
    MovieSection section, {
    required bool force,
  }) async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final generation = (_sectionLoadGenerations[section] ?? 0) + 1;
    _sectionLoadGenerations[section] = generation;
    // 同上：首次加载才展示骨架，强制刷新静默合并。
    if (!current.loadedSections.contains(section)) {
      final loading = Set<MovieSection>.from(current.loadingSections)
        ..add(section);
      state = AsyncData(current.copyWith(loadingSections: loading));
    }
    try {
      final seriesPage = await _api.seriesByTypePage(
        seriesType: section == MovieSection.anime ? 'ANIME' : 'TV',
      );
      if (!ref.mounted || _sectionLoadGenerations[section] != generation) {
        return;
      }
      final beforeEpisodes = state.asData?.value;
      var episodesLoaded = true;
      if (beforeEpisodes != null && (force || beforeEpisodes.episodePage < 0)) {
        episodesLoaded = await _loadPage(movies: false, firstPage: true);
      }
      if (!ref.mounted || _sectionLoadGenerations[section] != generation) {
        return;
      }
      final latest = state.asData?.value;
      if (latest == null) {
        return;
      }
      final loaded = Set<MovieSection>.from(latest.loadedSections)
        ..add(section);
      final stillLoading = Set<MovieSection>.from(latest.loadingSections)
        ..remove(section);
      // 剧集/动漫各写独立系列字段，互不覆盖；侧边栏计数与分区网格同源。
      final updated =
          section == MovieSection.tvShows
              ? latest.copyWith(
                tvSeries: seriesPage.items,
                tvSeriesPaging: _pagingOf(seriesPage),
              )
              : latest.copyWith(
                animeSeries: seriesPage.items,
                animeSeriesPaging: _pagingOf(seriesPage),
              );
      state = AsyncData(
        updated.copyWith(
          loadedSections: loaded,
          loadingSections: stillLoading,
          clearError: episodesLoaded,
        ),
      );
    } on Exception catch (error) {
      if (!ref.mounted || _sectionLoadGenerations[section] != generation) {
        return;
      }
      final latest = state.asData?.value;
      if (latest != null) {
        final stillLoading = Set<MovieSection>.from(latest.loadingSections)
          ..remove(section);
        state = AsyncData(
          latest.copyWith(
            loadingSections: stillLoading,
            errorMessage: describeUserFacingError(error).message,
          ),
        );
      }
    }
  }

  final List<String> _partialErrors = [];

  Future<MovieCenterState> _loadState() async {
    _partialErrors.clear();
    final emptyPage = const MediaPage<MovieVideoItem>(
      items: [],
      page: 0,
      size: 36,
      totalElements: 0,
      totalPages: 0,
    );
    final results = await Future.wait([
      _safe(_api.dashboard, MovieDashboard.empty()),
      _safe(
        () => _api.libraryPage(mediaType: 'MOVIE', keyword: _searchKeyword),
        emptyPage,
      ),
      // 分集一并拉取：影片管理需要电影+剧集/动漫全集；电影分区仍按 mediaType 过滤。
      _safe(
        () => _api.libraryPage(mediaType: 'EPISODE', keyword: _searchKeyword),
        emptyPage,
      ),
      // 预取两类系列列表：侧边栏计数与剧集/动漫分区首屏即有稳定数据
      // （后端 dashboard 的 series 字段恒为空，不能作为计数来源）。
      _safe(
        () => _api.seriesByTypePage(seriesType: 'TV'),
        MediaPage<MovieSeries>(
          items: const <MovieSeries>[],
          page: 0,
          size: 50,
          totalElements: 0,
          totalPages: 0,
        ),
      ),
      _safe(
        () => _api.seriesByTypePage(seriesType: 'ANIME'),
        MediaPage<MovieSeries>(
          items: const <MovieSeries>[],
          page: 0,
          size: 50,
          totalElements: 0,
          totalPages: 0,
        ),
      ),
    ]);
    final dashboard = results[0] as MovieDashboard;
    final moviePage = results[1] as MediaPage<MovieVideoItem>;
    final episodePage = results[2] as MediaPage<MovieVideoItem>;
    final tvSeriesPage = results[3] as MediaPage<MovieSeries>;
    final animePage = results[4] as MediaPage<MovieSeries>;
    final mergedItems = <String, MovieVideoItem>{
      for (final item in moviePage.items) item.id: item,
      for (final item in episodePage.items) item.id: item,
    }.values.toList(growable: false);
    return MovieCenterState(
      dashboard: dashboard,
      movies: mergedItems,
      recentItems: dashboard.recentlyAdded,
      continueWatching: dashboard.continueWatching,
      favoriteItems: const [],
      watchHistory: const [],
      collections: const [],
      tasks: const [],
      tvSeries: tvSeriesPage.items,
      animeSeries: animePage.items,
      tvSeriesPaging: _pagingOf(tvSeriesPage),
      animeSeriesPaging: _pagingOf(animePage),
      moviePage: moviePage.page,
      movieHasMore: moviePage.page + 1 < moviePage.totalPages,
      episodePage: episodePage.page,
      episodeHasMore: episodePage.page + 1 < episodePage.totalPages,
      loadedSections: const {MovieSection.movies},
      errorMessage: _partialErrors.isEmpty ? null : _partialErrors.join('；'),
    );
  }

  Future<T> _safe<T>(Future<T> Function() call, T fallback) async {
    try {
      return await call();
    } on Exception catch (e) {
      _partialErrors.add(describeUserFacingError(e).message);
      return fallback;
    }
  }

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
}
