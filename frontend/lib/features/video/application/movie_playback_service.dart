import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/domain/movie_playback_repository.dart';

/// 播放页面使用的应用服务。
class MoviePlaybackService {
  const MoviePlaybackService(this._repository);

  final MoviePlaybackRepository _repository;

  String resolvePlaybackUrl(
    PlaybackPlan plan, {
    required bool useWebStream,
    required String audioMode,
    required int startSeconds,
  }) {
    return _repository.resolvePlaybackUrl(
      plan,
      useWebStream: useWebStream,
      audioMode: audioMode,
      startSeconds: startSeconds,
    );
  }

  Future<void> updateProgress({
    required String videoItemId,
    required int positionSeconds,
    required int durationSeconds,
    required bool completed,
  }) {
    return _repository.updateProgress(
      videoItemId: videoItemId,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      completed: completed,
    );
  }

  Future<String> loadSubtitle(String url) {
    return _repository.loadSubtitle(url);
  }
}
