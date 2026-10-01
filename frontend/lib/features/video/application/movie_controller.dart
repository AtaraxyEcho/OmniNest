import 'dart:typed_data';
import 'package:omninest/app/session/session_epoch.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/application/movie_playback_service.dart';
import 'package:omninest/features/video/application/movie_progress_sync_service.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/data/movie_playback_repository_impl.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/domain/movie_playback_repository.dart';
import 'package:omninest/features/video/domain/series_play_target.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

export 'package:omninest/features/video/application/movie_center_state.dart';

part 'movie_center_commands.dart';

final movieApiProvider = Provider<MovieApi>((ref) {
  return MovieApi(ref.watch(apiClientProvider));
});

/// 播放会话仓储依赖注入入口。
final moviePlaybackRepositoryProvider = Provider<MoviePlaybackRepository>((
  ref,
) {
  return MoviePlaybackRepositoryImpl(ref.watch(movieApiProvider));
});

/// 播放页面应用服务依赖注入入口。
final moviePlaybackServiceProvider = Provider<MoviePlaybackService>((ref) {
  return MoviePlaybackService(ref.watch(moviePlaybackRepositoryProvider));
});

/// 播放进度周期同步服务：定时器由服务持有，Provider dispose 时取消。
final movieProgressSyncServiceProvider =
    Provider.autoDispose<MovieProgressSyncService>((ref) {
      final service = MovieProgressSyncService(
        ref.watch(moviePlaybackServiceProvider),
      );
      ref.onDispose(service.stop);
      return service;
    });

/// 提供影视模块的首页摘要只读视图。
final movieDashboardProvider = FutureProvider<MovieDashboard>((ref) {
  ref.watch(sessionEpochProvider);
  return ref.watch(movieApiProvider).dashboard();
});

// autoDispose：Admin 存储管理添加挂载位置后回到本模块时强制重新拉取，
// 避免 Keep-alive 缓存让「新建库源」按钮按旧的空列表持续置灰。
final videoStorageLocationsProvider =
    FutureProvider.autoDispose<List<VideoStorageLocation>>((ref) {
      return ref.watch(movieApiProvider).accessibleStorageLocations();
    });

final videoLibrarySourcesProvider =
    FutureProvider.autoDispose<List<VideoLibrarySource>>((ref) {
      return ref.watch(movieApiProvider).librarySources();
    });

final mediaLibraryAccessProvider = FutureProvider.autoDispose
    .family<MediaLibraryAccessSettings, String>((ref, sourceId) {
      return ref.watch(movieApiProvider).libraryAccess(sourceId);
    });

typedef MediaLibraryUsersKey = ({String query, int page});

final mediaLibraryAccessUsersProvider = FutureProvider.autoDispose
    .family<MediaPage<MediaLibraryUserCandidate>, MediaLibraryUsersKey>((
      ref,
      key,
    ) {
      return ref
          .watch(movieApiProvider)
          .libraryAccessUsers(query: key.query, page: key.page);
    });

typedef VideoDirectoryKey = ({String locationId, String? parent});

final videoStorageDirectoriesProvider = FutureProvider.autoDispose
    .family<MediaPage<VideoStorageDirectory>, VideoDirectoryKey>((ref, key) {
      return ref
          .watch(movieApiProvider)
          .storageDirectories(locationId: key.locationId, parent: key.parent);
    });

/// 部署可信挂载列表；仅在用户同时持有媒体库管理与系统配置读/管权限时消费。
final videoTrustedMountsProvider =
    FutureProvider.autoDispose<List<VideoTrustedMount>>((ref) {
      return ref.watch(movieApiProvider).trustedMounts();
    });

typedef VideoMountDirectoryKey = ({String mountKey, String? parent});

final videoMountDirectoriesProvider = FutureProvider.autoDispose
    .family<MediaPage<VideoStorageDirectory>, VideoMountDirectoryKey>((
      ref,
      key,
    ) {
      return ref
          .watch(movieApiProvider)
          .trustedMountDirectories(mountKey: key.mountKey, parent: key.parent);
    });

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

/// 已触发过中心数据刷新的完成态扫描 run ID，用于跨面板重挂载去重。
final handledCompletedScanRunIdsProvider = Provider<Set<String>>(
  (ref) => <String>{},
);

typedef MediaTreeKey = ({String runId, String? parentNodeId, int page});

final mediaScanTreeProvider = FutureProvider.autoDispose
    .family<MediaPage<MediaScanTreeNode>, MediaTreeKey>((ref, key) {
      return ref
          .watch(movieApiProvider)
          .mediaScanTree(
            runId: key.runId,
            parentNodeId: key.parentNodeId,
            page: key.page,
          );
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

/// 影视中心当前分区。独立于 [MovieCenterController] 持久保存，
/// 避免实时刷新（invalidate 重建）时把当前分区重置回电影页。
final movieCenterSectionProvider =
    NotifierProvider<MovieCenterSectionNotifier, MovieSection>(
      MovieCenterSectionNotifier.new,
    );

class MovieCenterSectionNotifier extends Notifier<MovieSection> {
  @override
  MovieSection build() => MovieSection.movies;

  void select(MovieSection section) {
    state = section;
  }
}

/// 新版详情抽屉当前展示的条目；为空时抽屉关闭。
/// 抽屉是页内覆盖层，不承载路由跳转；外部 deep-link 仍走 /video/:id 详情页。
final movieRedesignDetailProvider =
    NotifierProvider<MovieRedesignDetailNotifier, MovieVideoItem?>(
      MovieRedesignDetailNotifier.new,
    );

class MovieRedesignDetailNotifier extends Notifier<MovieVideoItem?> {
  @override
  MovieVideoItem? build() => null;

  void open(MovieVideoItem item) {
    state = item;
  }

  void close() {
    state = null;
  }
}

final movieDetailProvider = FutureProvider.autoDispose
    .family<MovieVideoItem, String>((ref, videoItemId) {
      return ref.watch(movieApiProvider).detail(videoItemId);
    });

final movieVersionsProvider = FutureProvider.autoDispose
    .family<List<MovieVideoItem>, String>((ref, videoItemId) {
      return ref.watch(movieApiProvider).versions(videoItemId);
    });

final moviePlaybackPlanProvider = FutureProvider.autoDispose
    .family<PlaybackPlan, String>((ref, videoItemId) {
      return ref.watch(movieApiProvider).playbackPlan(videoItemId);
    });

final movieSubtitlesProvider = FutureProvider.autoDispose
    .family<List<SubtitleTrack>, String>((ref, videoItemId) {
      return ref.watch(movieApiProvider).listSubtitles(videoItemId);
    });

final movieNfoPreviewProvider = FutureProvider.autoDispose
    .family<NfoExport, String>((ref, videoItemId) {
      return ref.watch(movieApiProvider).nfoPreview(videoItemId);
    });

final movieSeriesEpisodesProvider = FutureProvider.autoDispose
    .family<List<MovieVideoItem>, String>((ref, seriesId) {
      return ref.watch(movieApiProvider).seriesEpisodes(seriesId);
    });

final movieFavoriteProvider = FutureProvider.autoDispose
    .family<MovieFavoriteState, String>((ref, videoItemId) {
      return ref.watch(movieApiProvider).favoriteStatus(videoItemId);
    });

final movieSeriesDetailProvider = FutureProvider.autoDispose
    .family<MovieSeriesDetail, String>((ref, seriesId) {
      return ref.watch(movieApiProvider).seriesDetail(seriesId);
    });

/// 系列 PLAY 意图（续播 / 下一集 / 首集），供详情页按钮文案与跳转使用。
///
/// continue 与 history 任一失败时按空列表降级，回落为首集行为。
final seriesPlayIntentProvider = FutureProvider.autoDispose
    .family<SeriesPlayIntent, String>((ref, seriesId) async {
      final api = ref.watch(movieApiProvider);
      List<MovieContinueWatching> continues;
      List<MovieWatchHistory> history;
      try {
        continues = await api.continueWatching();
      } on Exception {
        continues = const [];
      }
      try {
        history = await api.history();
      } on Exception {
        history = const [];
      }
      return resolveSeriesPlayIntent(
        seriesId: seriesId,
        continueWatching: continues,
        history: history,
      );
    });

final activeMovieSeasonKeysProvider = Provider<Set<SeasonKey>>(
  (ref) => <SeasonKey>{},
);

final movieSeasonDetailProvider = FutureProvider.autoDispose
    .family<MovieSeasonDetail, SeasonKey>((ref, key) {
      final activeKeys = ref.read(activeMovieSeasonKeysProvider);
      activeKeys.add(key);
      ref.onDispose(() => activeKeys.remove(key));
      return ref
          .watch(movieApiProvider)
          .seasonDetail(key.seriesId, key.seasonNumber);
    });

final movieItemAssetsProvider = FutureProvider.autoDispose
    .family<List<MovieContentAsset>, String>((ref, itemId) {
      return ref.watch(movieApiProvider).itemAssets(itemId);
    });

final collectionItemsProvider = FutureProvider.autoDispose
    .family<List<MovieVideoItem>, String>((ref, collectionId) {
      return ref.watch(movieApiProvider).collectionItems(collectionId);
    });

final movieItemHistoryProvider = FutureProvider.autoDispose
    .family<MovieWatchHistory?, String>((ref, videoItemId) async {
      final history = await ref.watch(movieApiProvider).history();
      return history.where((h) => h.videoItemId == videoItemId).firstOrNull;
    });

final videoFavoriteStatusProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, videoItemId) {
      return ref
          .watch(movieApiProvider)
          .favoriteStatus(videoItemId)
          .then((state) => state.favorite);
    });

final seriesFavoriteProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  seriesId,
) {
  return ref.watch(movieApiProvider).seriesFavoriteStatus(seriesId);
});

class MovieCenterController extends AsyncNotifier<MovieCenterState> {
  /// `state` 与 `ref` 是受保护成员，拆到 part 的命令段经这两处出口读写。
  AsyncValue<MovieCenterState> get centerState => state;
  set centerState(AsyncValue<MovieCenterState> value) => state = value;

  Ref get centerRef => ref;

  int _refreshGeneration = 0;
  int _moviePageGeneration = 0;
  int _episodePageGeneration = 0;
  final Map<MovieSection, int> _sectionLoadGenerations = {};
  Timer? _searchDebounce;

  /// controller 重建期间（实时刷新触发 invalidate）被点击但未生效的分区。
  MovieSection? _pendingSection;

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
    await _loadSection(current?.section ?? MovieSection.movies, force: true);
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
    state = AsyncData(
      (current ??
              MovieCenterState(
                dashboard: MovieDashboard.empty(),
                movies: const [],
                recentItems: const [],
                continueWatching: const [],
                favoriteItems: const [],
                watchHistory: const [],
                collections: const [],
                tasks: const [],
              ))
          .copyWith(
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
      _safe(() => _api.libraryPage(mediaType: 'MOVIE'), emptyPage),
      // 分集一并拉取：影片管理需要电影+剧集/动漫全集；电影分区仍按 mediaType 过滤。
      _safe(() => _api.libraryPage(mediaType: 'EPISODE'), emptyPage),
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

  /// 通用续页：拉取 page+1 追加去重；门闩经 [onPaging] 回写状态，
  /// 失败回滚等待下次触底。
  Future<void> _appendPage<T>({
    required List<T> currentItems,
    required ListPaging paging,
    required String Function(T item) keyOf,
    required Future<MediaPage<T>> Function(int page) fetch,
    required void Function(ListPaging paging) onPaging,
    required void Function(List<T> items, ListPaging paging) apply,
  }) async {
    if (!paging.hasMore || paging.isLoadingMore) {
      return;
    }
    onPaging(paging.copyWith(isLoadingMore: true));
    try {
      final next = await fetch(paging.page + 1);
      final seen = currentItems.map(keyOf).toSet();
      apply(<T>[
        ...currentItems,
        ...next.items.where((item) => !seen.contains(keyOf(item))),
      ], _pagingOf(next));
    } on Exception {
      onPaging(paging);
    }
  }

  /// 观看历史续页。
  Future<void> loadMoreHistory() async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    await _appendPage(
      currentItems: current.watchHistory,
      paging: current.historyPaging,
      keyOf: (item) => item.id,
      fetch: (page) => _api.historyPage(page: page),
      onPaging: (paging) => _setHistoryPaging(paging),
      apply: (items, paging) {
        final latest = state.asData?.value;
        if (latest != null) {
          state = AsyncData(
            latest.copyWith(watchHistory: items, historyPaging: paging),
          );
        }
      },
    );
  }

  /// 收藏视频续页。
  Future<void> loadMoreFavorites() async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    await _appendPage(
      currentItems: current.favoriteItems,
      paging: current.favoritesPaging,
      keyOf: (item) => item.id,
      fetch: (page) => _api.favoritesPage(page: page),
      onPaging: (paging) => _setFavoritesPaging(paging),
      apply: (items, paging) {
        final latest = state.asData?.value;
        if (latest != null) {
          state = AsyncData(
            latest.copyWith(favoriteItems: items, favoritesPaging: paging),
          );
        }
      },
    );
  }

  /// 收藏系列续页。
  Future<void> loadMoreFavoriteSeries() async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    await _appendPage(
      currentItems: current.favoriteSeries,
      paging: current.favoriteSeriesPaging,
      keyOf: (item) => item.id,
      fetch: (page) => _api.favoriteSeriesPage(page: page),
      onPaging: (paging) => _setFavoriteSeriesPaging(paging),
      apply: (items, paging) {
        final latest = state.asData?.value;
        if (latest != null) {
          state = AsyncData(
            latest.copyWith(
              favoriteSeries: items,
              favoriteSeriesPaging: paging,
            ),
          );
        }
      },
    );
  }

  /// 剧集/动漫系列网格续页。
  Future<void> loadMoreSeries({required bool anime}) async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    await _appendPage(
      currentItems: anime ? current.animeSeries : current.tvSeries,
      paging: anime ? current.animeSeriesPaging : current.tvSeriesPaging,
      keyOf: (item) => item.id,
      fetch:
          (page) => _api.seriesByTypePage(
            seriesType: anime ? 'ANIME' : 'TV',
            page: page,
          ),
      onPaging: (paging) => _setSeriesPaging(anime: anime, paging: paging),
      apply: (items, paging) {
        final latest = state.asData?.value;
        if (latest != null) {
          state = AsyncData(
            anime
                ? latest.copyWith(animeSeries: items, animeSeriesPaging: paging)
                : latest.copyWith(tvSeries: items, tvSeriesPaging: paging),
          );
        }
      },
    );
  }

  void _setHistoryPaging(ListPaging paging) {
    final latest = state.asData?.value;
    if (latest != null) {
      state = AsyncData(latest.copyWith(historyPaging: paging));
    }
  }

  void _setFavoritesPaging(ListPaging paging) {
    final latest = state.asData?.value;
    if (latest != null) {
      state = AsyncData(latest.copyWith(favoritesPaging: paging));
    }
  }

  void _setFavoriteSeriesPaging(ListPaging paging) {
    final latest = state.asData?.value;
    if (latest != null) {
      state = AsyncData(latest.copyWith(favoriteSeriesPaging: paging));
    }
  }

  void _setSeriesPaging({required bool anime, required ListPaging paging}) {
    final latest = state.asData?.value;
    if (latest != null) {
      state = AsyncData(
        anime
            ? latest.copyWith(animeSeriesPaging: paging)
            : latest.copyWith(tvSeriesPaging: paging),
      );
    }
  }
}

/// 分页页对象到滚动加载状态的映射。
ListPaging _pagingOf<T>(MediaPage<T> page) =>
    ListPaging(page: page.page, hasMore: page.page + 1 < page.totalPages);
