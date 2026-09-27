import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/application/movie_playback_service.dart';
import 'package:omninest/features/video/application/movie_progress_sync_service.dart';
import 'package:omninest/features/video/domain/movie_playback_models.dart';
import 'package:omninest/features/video/domain/movie_playback_repository.dart';

class _FailingPlaybackRepository implements MoviePlaybackRepository {
  int updateCalls = 0;

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
    updateCalls++;
    throw Exception('network down');
  }

  @override
  Future<String> loadSubtitle(String url) async => '';
}

class _OkPlaybackRepository implements MoviePlaybackRepository {
  int updateCalls = 0;

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
    updateCalls++;
  }

  @override
  Future<String> loadSubtitle(String url) async => '';
}

void main() {
  test('同步失败时回调 onSyncFailed 且不抛出', () async {
    final repository = _FailingPlaybackRepository();
    final service = MovieProgressSyncService(MoviePlaybackService(repository));
    var failed = 0;
    service.start(
      videoItemId: 'v1',
      interval: const Duration(milliseconds: 20),
      readPositionSeconds: () => 10,
      readDurationSeconds: () => 100,
      computeCompleted: (_, __) => false,
      onSyncFailed: () => failed++,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    service.stop();
    expect(repository.updateCalls, greaterThan(0));
    expect(failed, greaterThan(0));
  });

  test('同步成功不触发 onSyncFailed', () async {
    final repository = _OkPlaybackRepository();
    final service = MovieProgressSyncService(MoviePlaybackService(repository));
    var failed = 0;
    service.start(
      videoItemId: 'v1',
      interval: const Duration(milliseconds: 20),
      readPositionSeconds: () => 10,
      readDurationSeconds: () => 100,
      computeCompleted: (_, __) => false,
      onSyncFailed: () => failed++,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    service.stop();
    expect(repository.updateCalls, greaterThan(0));
    expect(failed, 0);
  });
}
