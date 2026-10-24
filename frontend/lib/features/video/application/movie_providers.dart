import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/application/movie_playback_service.dart';
import 'package:omninest/features/video/application/movie_progress_sync_service.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/data/movie_playback_repository_impl.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/domain/movie_playback_repository.dart';
import 'package:omninest/features/video/domain/series_play_target.dart';

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
        history = await api.seriesHistory(seriesId);
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
      return ref.watch(movieApiProvider).itemHistory(videoItemId);
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
