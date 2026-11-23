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

  void _seekRelative(int seconds) {
    final current = _player.state.position;
    final target = current + Duration(seconds: seconds);
    _seekToPosition(target);
  }

  /// Seek 策略：
  /// - 非 Web 端（Desktop/Android）：libmpv 原生 seek，直接调用
  /// - Web 端 fMP4 流：尝试原生 seek，若失败则重新打开流从目标位置开始
  Future<void> _seekToPosition(Duration target) async {
    // 用户主动改播放位置说明还想留在这集：片尾倒计时不能被自动换集盖掉这个意图。
    _cancelEpisodeAutoplay();
    final generation = ++_seekGeneration;
    if (!mounted || generation != _seekGeneration) return;
    if (!isWebPlatform) {
      await _player.seek(target);
      if (!mounted || generation != _seekGeneration) return;
      _updateState(() => _isSeeking = false);
      return;
    }
    final asyncValue = _readPlaybackPlan();
    PlaybackPlan? plan;
    if (asyncValue is AsyncData<PlaybackPlan>) {
      plan = asyncValue.value;
    }
    if (plan?.streamUrl == null || plan!.streamUrl!.isEmpty) {
      await _player.seek(target);
      if (!mounted || generation != _seekGeneration) return;
      _updateState(() => _isSeeking = false);
      return;
    }
    // Web 端 fMP4 流模式：尝试原生 seek，失败则重新打开流
    final targetSeconds = clampMovieSeekSeconds(target, plan.durationSeconds);
    final positionBeforeSeek = _player.state.position;
    await _player.seek(Duration(seconds: targetSeconds));
    // 用「首个位置事件」代替固定 800ms 盲等：拖条的迟滞几乎全花在这段死等上，
    // 流恢复推进通常在几十毫秒内；探测上限仍是 800ms，判定口径不变。
    await _awaitSeekProgress(positionBeforeSeek);
    if (!mounted || generation != _seekGeneration) return;
    final posAfter = _player.state.position;
    final driftMs = (posAfter.inMilliseconds - targetSeconds * 1000).abs();
    if (driftMs < 5000) {
      _polledPosition.value = posAfter;
      _updateState(() {
        _isSeeking = false;
      });
      return;
    }
    // 原生 seek 未生效，重新打开流从目标位置开始
    devLog(
      '[_seekToPosition] 原生 seek 未生效，回退到流重开: targetSeconds=$targetSeconds',
    );
    _polledPosition.value = Duration(seconds: targetSeconds);
    _updateState(() {
      _seekStart = targetSeconds;
      _loadedUrl = null;
    });
    final currentPlan = _readPlaybackPlan();
    if (currentPlan is AsyncData<PlaybackPlan>) {
      _openIfNeeded(currentPlan.value);
    } else {
      _updateState(() => _isSeeking = false);
    }
  }
}
