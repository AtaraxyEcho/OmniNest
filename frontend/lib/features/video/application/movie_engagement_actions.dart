import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/video/application/movie_providers.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

final movieEngagementActionsProvider = Provider<MovieEngagementActions>((ref) {
  return MovieEngagementActions(ref.watch(movieApiProvider));
});

/// 影视清单与观看状态的跨设备写入入口。
class MovieEngagementActions {
  const MovieEngagementActions(this._api);

  final MovieApi _api;

  Future<List<MovieVideoItem>> watchlistItems() => _api.watchlistItems();

  Future<void> setWatchlist(
    String videoItemId, {
    required bool watchlisted,
  }) async {
    await _api.setWatchlist(videoItemId: videoItemId, watchlisted: watchlisted);
  }

  Future<void> setWatched({
    required String videoItemId,
    required bool watched,
    required int durationSeconds,
  }) async {
    await _api.updateProgress(
      videoItemId: videoItemId,
      positionSeconds: watched ? durationSeconds : 0,
      durationSeconds: durationSeconds,
      completed: watched,
      requireWritePermission: true,
    );
  }
}
