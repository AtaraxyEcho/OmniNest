import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/core/network/api_url_resolver.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/domain/movie_playback_repository.dart';

/// 基于影视 API 的播放会话仓储实现。
class MoviePlaybackRepositoryImpl implements MoviePlaybackRepository {
  const MoviePlaybackRepositoryImpl(this._api);

  final MovieApi _api;

  @override
  String resolvePlaybackUrl(
    PlaybackPlan plan, {
    required bool useWebStream,
    required String audioMode,
    required int startSeconds,
  }) {
    final streamUrl = plan.streamUrl;
    if (!useWebStream || streamUrl == null || streamUrl.isEmpty) {
      return _resolveApiRelativeUrl(plan.url);
    }
    final uri = Uri.parse(_resolveStreamUrl(streamUrl));
    final mediaToken = uri.queryParameters['token'];
    if (mediaToken == null || mediaToken.isEmpty) {
      return plan.url;
    }
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'token': mediaToken,
            'audioMode': audioMode,
            if (startSeconds > 0) 'start': '$startSeconds',
          },
        )
        .toString();
  }

  String _resolveApiRelativeUrl(String url) {
    return resolveServerApiUrl(_api.apiClient.dio.options.baseUrl, url);
  }

  String _resolveStreamUrl(String streamUrl) {
    return resolveServerApiUrl(_api.apiClient.dio.options.baseUrl, streamUrl);
  }

  @override
  Future<void> updateProgress({
    required String videoItemId,
    required int positionSeconds,
    required int durationSeconds,
    required bool completed,
  }) async {
    await _api.updateProgress(
      videoItemId: videoItemId,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      completed: completed,
    );
  }

  @override
  Future<String> loadSubtitle(String url) {
    return _api.loadSubtitle(url);
  }
}
