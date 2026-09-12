import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';

/// 定时关闭剩余时间（null 表示未开启）。
class MusicSleepTimerState {
  const MusicSleepTimerState({
    this.remaining,
    this.stopAfterCurrentTrack = false,
  });

  final Duration? remaining;
  final bool stopAfterCurrentTrack;

  bool get active => remaining != null || stopAfterCurrentTrack;

  MusicSleepTimerState copyWith({
    Duration? remaining,
    bool clearRemaining = false,
    bool? stopAfterCurrentTrack,
  }) {
    return MusicSleepTimerState(
      remaining: clearRemaining ? null : (remaining ?? this.remaining),
      stopAfterCurrentTrack:
          stopAfterCurrentTrack ?? this.stopAfterCurrentTrack,
    );
  }
}

final musicSleepTimerControllerProvider = NotifierProvider.autoDispose<
  MusicSleepTimerController,
  MusicSleepTimerState
>(MusicSleepTimerController.new);

/// 定时关闭控制器：倒计时归零后暂停播放；播放完当前曲立即停止。
class MusicSleepTimerController extends Notifier<MusicSleepTimerState> {
  Timer? _timer;
  DateTime? _deadline;

  bool get _disposed => !ref.mounted;

  @override
  MusicSleepTimerState build() {
    ref.onDispose(_cancelTimer);
    return const MusicSleepTimerState();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 设置倒计时档位（15/30/60/90 分钟）。
  void start(Duration duration) {
    _cancelTimer();
    _deadline = DateTime.now().add(duration);
    state = MusicSleepTimerState(remaining: duration);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick();
    });
  }

  /// 切换"播完当前曲停止"：到点由播放完成回调触发暂停。
  void toggleStopAfterCurrentTrack() {
    if (state.stopAfterCurrentTrack) {
      state = state.copyWith(stopAfterCurrentTrack: false);
      return;
    }
    _cancelTimer();
    _deadline = null;
    state = const MusicSleepTimerState(
      remaining: null,
      stopAfterCurrentTrack: true,
    );
  }

  /// 当前曲目自然播完时调用；不处于"播完当前曲"模式时忽略。
  Future<void> onTrackCompleted() async {
    if (!state.stopAfterCurrentTrack || _disposed) {
      return;
    }
    state = const MusicSleepTimerState();
    try {
      await ref.read(musicPlaybackSessionProvider).player.pause();
      await ref.read(musicCenterControllerProvider.notifier).setPlaying(false);
    } on Object {
      // 定时关闭触发的暂停失败属末端动作，任务已达成（停止播放），忽略。
    }
  }

  void cancel() {
    _cancelTimer();
    _deadline = null;
    state = const MusicSleepTimerState();
  }

  void _tick() {
    if (_disposed) {
      return;
    }
    final deadline = _deadline;
    if (deadline == null) {
      _cancelTimer();
      return;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _pauseNow();
      return;
    }
    state = state.copyWith(remaining: remaining);
  }

  Future<void> _pauseNow() async {
    _cancelTimer();
    _deadline = null;
    state = const MusicSleepTimerState();
    if (_disposed) {
      return;
    }
    try {
      await ref.read(musicPlaybackSessionProvider).player.pause();
      await ref.read(musicCenterControllerProvider.notifier).setPlaying(false);
    } on Object {
      // 定时暂停失败不打断应用，保持计时器已清除状态。
    }
  }
}
