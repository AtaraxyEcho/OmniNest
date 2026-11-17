part of 'movie_player_page.dart';

/// 播放进度上报：退出前补一次同步，播放期间由同步服务定时上报。
extension _MoviePlayerPageProgress on _MoviePlayerPageState {
  Future<void> _syncCurrentProgress() async {
    if (_loadedUrl == null || _isSeeking) return;
    final position = _player.state.position.inSeconds;
    final playerDur = _player.state.duration.inSeconds;
    // fMP4 流的 duration 不可靠，优先使用播放计划的时长
    final duration =
        _currentDurationSeconds > 0 ? _currentDurationSeconds : playerDur;
    if (position <= 0 && duration <= 0) return;
    try {
      await _playbackService.updateProgress(
        videoItemId: widget.videoItemId,
        positionSeconds: position,
        durationSeconds: duration,
        completed: isMoviePlaybackCompleted(position, duration),
      );
    } catch (_) {
      devLog('播放进度同步失败');
      _notifyProgressSyncDeferred();
    }
  }

  /// 进度未能同步时非阻断提示一次（同一播放会话限流），播放不中断。
  void _notifyProgressSyncDeferred() {
    if (!mounted || _progressSyncWarned) {
      return;
    }
    _progressSyncWarned = true;
    showMovieFeedback(
      context,
      AppLocalizations.of(context).videoProgressSyncDeferred,
      isError: true,
    );
  }

  void _clearProgressSyncWarning() {
    _progressSyncWarned = false;
  }

  void _startProgressSync(PlaybackPlan plan) {
    _progressSyncService.start(
      videoItemId: widget.videoItemId,
      interval: const Duration(seconds: 20),
      readPositionSeconds: () => _player.state.position.inSeconds,
      readDurationSeconds: () {
        final playerDuration = _player.state.duration.inSeconds;
        return playerDuration > 0 ? playerDuration : plan.durationSeconds;
      },
      computeCompleted:
          (position, duration) => isMoviePlaybackCompleted(position, duration),
      shouldSkip: () => _isSeeking,
      onSyncFailed: _notifyProgressSyncDeferred,
      onSyncSucceeded: _clearProgressSyncWarning,
    );
  }
}
