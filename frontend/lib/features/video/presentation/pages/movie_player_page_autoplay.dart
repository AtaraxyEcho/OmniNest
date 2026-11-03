part of 'movie_player_page.dart';

/// 片尾自动连播：本集播完后倒计时切到同季下一集。
///
/// 只在剧集上生效；电影与本季最后一集停在片尾，与手动控制的观感一致。
extension _MoviePlayerPageAutoplay on _MoviePlayerPageState {
  /// 订阅播放器完成事件。播放计划每次打开后重挂一次，取消由 dispose 负责。
  void _attachEpisodeAutoplay() {
    // 换集后本扩展仍是同一个 State 之外的新页面；同一页面重开流时，
    // 用户已经做出的取消决定不应被新的一次 completed 事件抹掉。
    _autoplayDismissed = false;
    _completedSub?.cancel();
    _completedSub = _player.stream.completed.listen((completed) {
      if (!mounted || !completed) {
        return;
      }
      _onEpisodeFinished();
    });
  }

  void _onEpisodeFinished() {
    if (_autoplayDismissed || _autoplayNextEpisode != null) {
      return;
    }
    final item =
        ref.read(movieDetailProvider(widget.videoItemId)).asData?.value;
    final next = _episodeNavigation(item, watch: false).next;
    if (next == null) {
      return;
    }
    _startEpisodeAutoplay(next);
  }

  void _startEpisodeAutoplay(MovieVideoItem next) {
    _autoplayTimer?.cancel();
    _updateState(() {
      _autoplayNextEpisode = next;
      _autoplaySecondsLeft = MoviePlayerAutoplayNotice.countdown.inSeconds;
    });
    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_autoplaySecondsLeft <= 1) {
        timer.cancel();
        _autoplayTimer = null;
        final pending = _autoplayNextEpisode;
        _cancelEpisodeAutoplay();
        if (pending != null) {
          unawaited(_playEpisode(pending));
        }
        return;
      }
      _updateState(() => _autoplaySecondsLeft -= 1);
    });
  }

  /// 用户点“取消”或主动改播放位置：本集不再自动换集。
  ///
  /// 只在确有倒计时待决时记“本集已取消”：开流时的续播 seek 也走这条路径，
  /// 把它算成取消会让这一集永远不再连播。
  void _cancelEpisodeAutoplay() {
    final hadPending = _autoplayTimer != null || _autoplayNextEpisode != null;
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    if (!hadPending) {
      return;
    }
    _autoplayDismissed = true;
    if (!mounted || _autoplayNextEpisode == null) {
      return;
    }
    _updateState(() {
      _autoplayNextEpisode = null;
      _autoplaySecondsLeft = 0;
    });
  }

  /// “立即播放”：不等倒计时，直接换到已确定的下一集。
  void _playNextEpisodeNow() {
    final next = _autoplayNextEpisode;
    if (next == null) {
      return;
    }
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    unawaited(_playEpisode(next));
  }
}
