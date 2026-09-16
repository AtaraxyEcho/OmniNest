import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_scope_handler.dart';
import 'package:omninest/features/video/application/movie_controller.dart';

/// 影视作用域实时失效刷新处理器。
class VideoSyncHandler implements RealtimeScopeHandler {
  VideoSyncHandler(this.ref);

  final Ref ref;
  final RealtimeRevisionTracker _auxiliaryRevisions = RealtimeRevisionTracker();

  @override
  RealtimeScope get scope => RealtimeScope.video;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) => true;

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) async {
    final auxiliary = _auxiliaryRevisions.pending(invalidations);
    final refreshes = <Future<Object?>>[];
    if (auxiliary.isNotEmpty && ref.exists(movieDashboardProvider)) {
      refreshes.add(ref.refresh(movieDashboardProvider.future));
    }
    if (auxiliary.isNotEmpty) {
      for (final key in ref.read(activeMovieSeasonKeysProvider)) {
        final season = movieSeasonDetailProvider(key);
        if (ref.exists(season)) {
          refreshes.add(ref.refresh(season.future));
        }
      }
    }
    for (final invalidation in auxiliary) {
      final resourceId = invalidation.resourceId;
      if (resourceId == null) continue;
      _refreshMountedDetails(resourceId, refreshes);
    }
    await Future.wait(refreshes);
    _auxiliaryRevisions.markCompleted(auxiliary);
    // 影视中心从未激活时无状态可刷，首次打开自取最新数据。
    if (!ref.exists(movieCenterControllerProvider)) return true;
    await ref.read(movieCenterControllerProvider.future);
    await ref.read(movieCenterControllerProvider.notifier).refreshForRealtime();
    _auxiliaryRevisions.clear(invalidations);
    return true;
  }

  void _refreshMountedDetails(
    String resourceId,
    List<Future<Object?>> refreshes,
  ) {
    final detail = movieDetailProvider(resourceId);
    if (ref.exists(detail)) {
      refreshes.add(ref.refresh(detail.future));
    }
    final versions = movieVersionsProvider(resourceId);
    if (ref.exists(versions)) {
      refreshes.add(ref.refresh(versions.future));
    }
    final subtitles = movieSubtitlesProvider(resourceId);
    if (ref.exists(subtitles)) {
      refreshes.add(ref.refresh(subtitles.future));
    }
    final favorite = movieFavoriteProvider(resourceId);
    if (ref.exists(favorite)) {
      refreshes.add(ref.refresh(favorite.future));
    }
    final assets = movieItemAssetsProvider(resourceId);
    if (ref.exists(assets)) {
      refreshes.add(ref.refresh(assets.future));
    }
    final history = movieItemHistoryProvider(resourceId);
    if (ref.exists(history)) {
      refreshes.add(ref.refresh(history.future));
    }
    final series = movieSeriesDetailProvider(resourceId);
    if (ref.exists(series)) {
      refreshes.add(ref.refresh(series.future));
    }
  }
}

/// 影视任务实时失效刷新处理器。
class VideoTaskSyncHandler implements RealtimeScopeHandler {
  VideoTaskSyncHandler(this.ref);

  final Ref ref;

  @override
  RealtimeScope get scope => RealtimeScope.tasks;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) {
    return invalidation.resourceType == '*' ||
        const <String>{
          'TASK_VIDEO_TRANSCODE',
          'TASK_AUDIO_EXTRACT',
          'TASK_WEB_OPTIMIZE',
          'TASK_MEDIA_SCAN',
          'TASK_MEDIA_SCRAPE',
        }.contains(invalidation.resourceType);
  }

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) async {
    // 影视中心从未激活时无状态可刷，首次打开自取最新数据。
    if (!ref.exists(movieCenterControllerProvider)) return true;
    await ref.read(movieCenterControllerProvider.future);
    await ref
        .read(movieCenterControllerProvider.notifier)
        .refreshTasksForRealtime();
    return true;
  }
}
