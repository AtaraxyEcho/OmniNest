import 'package:omninest/features/video/domain/movie_models.dart';

/// 影视播放会话数据访问契约。
abstract interface class MoviePlaybackRepository {
  String resolvePlaybackUrl(
    PlaybackPlan plan, {
    required bool useWebStream,
    required String audioMode,
    required int startSeconds,
  });

  Future<void> updateProgress({
    required String videoItemId,
    required int positionSeconds,
    required int durationSeconds,
    required bool completed,
  });

  Future<String> loadSubtitle(String url);
}
