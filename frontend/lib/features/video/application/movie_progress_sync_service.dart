import 'dart:async';

import 'package:omninest/features/video/application/movie_playback_service.dart';

/// 播放进度周期同步服务。
///
/// 定时器由本服务持有，调用方通过 [start]/[stop] 控制生命周期；
/// Provider dispose 时通过 [stop] 取消，避免 Widget State 持有轮询。
class MovieProgressSyncService {
  MovieProgressSyncService(this._playbackService);

  final MoviePlaybackService _playbackService;
  Timer? _timer;
  String? _videoItemId;

  /// 启动周期性进度同步。重复调用会先取消旧定时器。
  ///
  /// [shouldSkip] 返回 true 时跳过本周期（如拖动 seek 中）。
  /// [computeCompleted] 由调用方根据位置/时长判定是否播完。
  void start({
    required String videoItemId,
    required Duration interval,
    required int Function() readPositionSeconds,
    required int Function() readDurationSeconds,
    required bool Function(int position, int duration) computeCompleted,
    bool Function()? shouldSkip,
  }) {
    stop();
    _videoItemId = videoItemId;
    _timer = Timer.periodic(interval, (_) async {
      if (shouldSkip?.call() ?? false) {
        return;
      }
      final position = readPositionSeconds();
      final duration = readDurationSeconds();
      if (position <= 0 && duration <= 0) {
        return;
      }
      try {
        await _playbackService.updateProgress(
          videoItemId: videoItemId,
          positionSeconds: position,
          durationSeconds: duration,
          completed: computeCompleted(position, duration),
        );
      } on Exception {
        // 进度同步失败不打断播放，下次周期重试。
      }
    });
  }

  /// 取消周期同步。
  void stop() {
    _timer?.cancel();
    _timer = null;
    _videoItemId = null;
  }

  /// 是否有活跃的同步定时器（供测试断言）。
  bool get isActive => _timer != null;

  /// 当前同步的视频条目 ID（供测试断言）。
  String? get videoItemId => _videoItemId;
}
