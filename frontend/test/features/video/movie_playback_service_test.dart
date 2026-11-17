import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/auth/auth_session_store.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/video/application/movie_playback_service.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/data/movie_playback_repository_impl.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/domain/movie_playback_repository.dart';

void main() {
  const plan = PlaybackPlan(
    videoItemId: 'video-1',
    mode: 'TRANSCODE',
    url: 'https://storage.test/original.mp4',
    positionSeconds: 0,
    durationSeconds: 600,
    subtitles: <PlaybackSubtitle>[],
    streamUrl: '/video/items/video-1/stream',
  );

  test('没有专用媒体令牌时不将登录令牌写入 Web 转码地址', () async {
    final sessionStore = MemoryAuthSessionStore();
    await sessionStore.saveAccessToken('access token');
    final repository = MoviePlaybackRepositoryImpl(
      MovieApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          sessionStore: sessionStore,
        ),
      ),
    );

    final resolved = repository.resolvePlaybackUrl(
      plan,
      useWebStream: true,
      audioMode: 'cached',
      startSeconds: 42,
    );
    expect(resolved, plan.url);
    expect(resolved, isNot(contains('access%20token')));
  });

  test('缺少会话令牌时回退原始播放地址', () {
    final repository = MoviePlaybackRepositoryImpl(
      MovieApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          sessionStore: MemoryAuthSessionStore(),
        ),
      ),
    );

    final resolved = repository.resolvePlaybackUrl(
      plan,
      useWebStream: true,
      audioMode: 'original',
      startSeconds: 0,
    );

    expect(resolved, plan.url);
  });

  test('共享媒体流保留专用令牌且不写入登录令牌', () async {
    final sessionStore = MemoryAuthSessionStore();
    await sessionStore.saveAccessToken('login-jwt');
    final repository = MoviePlaybackRepositoryImpl(
      MovieApi(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
          sessionStore: sessionStore,
        ),
      ),
    );
    const sharedPlan = PlaybackPlan(
      videoItemId: 'video-1',
      mode: 'TRANSCODE_REQUIRED',
      url: '/api/v1/public/video/items/video-1/content?token=media-token',
      positionSeconds: 0,
      durationSeconds: 600,
      subtitles: <PlaybackSubtitle>[],
      streamUrl: '/api/v1/public/video/items/video-1/stream?token=media-token',
    );

    final resolved = repository.resolvePlaybackUrl(
      sharedPlan,
      useWebStream: true,
      audioMode: 'cached',
      startSeconds: 0,
    );
    final uri = Uri.parse(resolved);

    expect(uri.path, '/api/v1/public/video/items/video-1/stream');
    expect(uri.queryParameters['token'], 'media-token');
    expect(resolved, isNot(contains('login-jwt')));
  });

  test('播放应用服务转发进度和字幕命令', () async {
    final repository = _FakeMoviePlaybackRepository();
    final service = MoviePlaybackService(repository);

    await service.updateProgress(
      videoItemId: 'video-1',
      positionSeconds: 120,
      durationSeconds: 600,
      completed: false,
    );
    final subtitle = await service.loadSubtitle('https://storage.test/a.vtt');

    expect(repository.positionSeconds, 120);
    expect(repository.durationSeconds, 600);
    expect(repository.completed, isFalse);
    expect(subtitle, 'WEBVTT');
  });
}

class _FakeMoviePlaybackRepository implements MoviePlaybackRepository {
  int? positionSeconds;
  int? durationSeconds;
  bool? completed;

  @override
  String resolvePlaybackUrl(
    PlaybackPlan plan, {
    required bool useWebStream,
    required String audioMode,
    required int startSeconds,
  }) {
    return plan.url;
  }

  @override
  Future<void> updateProgress({
    required String videoItemId,
    required int positionSeconds,
    required int durationSeconds,
    required bool completed,
  }) async {
    this.positionSeconds = positionSeconds;
    this.durationSeconds = durationSeconds;
    this.completed = completed;
  }

  @override
  Future<String> loadSubtitle(String url) async => 'WEBVTT';
}
