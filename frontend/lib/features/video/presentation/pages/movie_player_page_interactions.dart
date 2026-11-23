part of 'movie_player_page.dart';

/// Web fMP4 流 seek 后的探测上限：与旧的固定盲等同值，
/// 只是不再无条件等满。
const Duration _seekSettleTimeout = Duration(milliseconds: 800);

/// 集中处理播放器键盘、手势、面板和剧集导航交互。
extension _MoviePlayerPageInteractions on _MoviePlayerPageState {
  KeyEventResult _handleKey(
    KeyEvent event,
    PlaybackPlan plan, {
    required bool isFullscreen,
    MovieVideoItem? previousEpisode,
    MovieVideoItem? nextEpisode,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_controlPanelOpen || _isTextInputFocused()) {
      return KeyEventResult.ignored;
    }
    final action = resolveMoviePlayerKeyboardAction(
      event.logicalKey,
      shiftPressed: HardwareKeyboard.instance.isShiftPressed,
      isWeb: isWebPlatform,
    );
    if (action == null) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent && !isRepeatableMoviePlayerAction(action)) {
      return KeyEventResult.handled;
    }
    switch (action) {
      case MoviePlayerKeyboardAction.playPause:
        unawaited(_requestPlayPause());
        break;
      case MoviePlayerKeyboardAction.seekBackward5:
        _seekWithFeedback(-5);
        break;
      case MoviePlayerKeyboardAction.seekForward5:
        _seekWithFeedback(5);
        break;
      case MoviePlayerKeyboardAction.seekBackward10:
        _seekWithFeedback(-10);
        break;
      case MoviePlayerKeyboardAction.seekForward10:
        _seekWithFeedback(10);
        break;
      case MoviePlayerKeyboardAction.volumeUp:
        _changeVolume(5);
        break;
      case MoviePlayerKeyboardAction.volumeDown:
        _changeVolume(-5);
        break;
      case MoviePlayerKeyboardAction.toggleMute:
        _toggleMute();
        break;
      case MoviePlayerKeyboardAction.toggleSubtitle:
        _toggleSubtitle(plan);
        break;
      case MoviePlayerKeyboardAction.toggleFullscreen:
        // 键盘只走 F；F11 由 app.dart 全局 handler 处理，避免双重切换。
        _toggleFullscreen();
        break;
      case MoviePlayerKeyboardAction.speedDown:
        _changePlaybackSpeed(-0.25);
        break;
      case MoviePlayerKeyboardAction.speedUp:
        _changePlaybackSpeed(0.25);
        break;
      case MoviePlayerKeyboardAction.cycleAspectRatio:
        _cycleAspectRatio();
        break;
      case MoviePlayerKeyboardAction.previousEpisode:
        if (previousEpisode != null) {
          unawaited(_playEpisode(previousEpisode));
        }
        break;
      case MoviePlayerKeyboardAction.nextEpisode:
        if (nextEpisode != null) {
          unawaited(_playEpisode(nextEpisode));
        }
        break;
      case MoviePlayerKeyboardAction.escape:
        if (isFullscreen) {
          _toggleFullscreen();
        } else {
          unawaited(_exitPlayer());
        }
        break;
    }
    _showControlsAndRestartTimer();
    return KeyEventResult.handled;
  }

  bool _isTextInputFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Future<void> _requestPlayPause() async {
    if (_playPausePending || _isBuffering) {
      return;
    }
    if (!_playPauseGate.accept(DateTime.now())) {
      return;
    }
    _playPausePending = true;
    final wasPlaying = _player.state.playing;
    // 样例 `Movies.tsx:144` 的 `doFlash(p ? "pause" : "play")`：切换瞬间
    // 画面正中闪一枚动作图标，和 `.v-flash` 的 .7s 淡出同步。
    _showCenterFlash(
      wasPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
    );
    try {
      if (wasPlaying) {
        await _player.pause();
      } else {
        await _player.play();
      }
      _wasPlayingBeforeBuffering = false;
      _showControlsAndRestartTimer();
    } finally {
      _playPausePending = false;
    }
  }

  void _handleSurfaceTap() {
    if (_controlPanelOpen) {
      return;
    }
    if (isMobilePlatform) {
      _toggleControlsVisibility();
      return;
    }
    // 桌面与 Web 的既有习惯：点击画面切换播放/暂停（有无控制栏均生效）。
    unawaited(_requestPlayPause());
    _showControlsAndRestartTimer();
  }

  void _handleSurfaceDoubleTap(TapDownDetails details, double width) {
    if (!isMobilePlatform) {
      _toggleFullscreen();
      return;
    }
    _seekWithFeedback(details.localPosition.dx < width / 2 ? -10 : 10);
  }

  void _seekWithFeedback(int seconds) {
    _seekRelative(seconds);
    final l10n = AppLocalizations.of(context);
    _showActionFeedback(
      icon: seconds < 0 ? Icons.replay_10_rounded : Icons.forward_10_rounded,
      label:
          seconds < 0
              ? l10n.videoSeekBackwardSeconds(seconds.abs())
              : l10n.videoSeekForwardSeconds(seconds),
      placement:
          seconds < 0
              ? MoviePlayerFeedbackPlacement.left
              : MoviePlayerFeedbackPlacement.right,
    );
  }

  /// 等待播放器报出与 seek 前不同的位置；到上限仍没报出就带着当前状态去判定。
  ///
  /// `orElse` 是必需的：`_player.dispose()` 后这条流会关闭，firstWhere 在没有
  /// 匹配元素时默认抛 StateError，而退场路径正会撞上它。
  Future<void> _awaitSeekProgress(Duration positionBeforeSeek) async {
    await _player.stream.position
        .firstWhere(
          (position) => position != positionBeforeSeek,
          orElse: () => positionBeforeSeek,
        )
        .timeout(_seekSettleTimeout, onTimeout: () => _player.state.position);
  }

  void _showActionFeedback({
    required IconData icon,
    required String label,
    required MoviePlayerFeedbackPlacement placement,
  }) {
    _feedbackTimer?.cancel();
    final sequence = (_feedback?.sequence ?? 0) + 1;
    _updateState(() {
      _feedback = _PlayerFeedback(
        icon: icon,
        label: label,
        placement: placement,
        sequence: sequence,
      );
    });
    _feedbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        _updateState(() => _feedback = null);
      }
    });
  }

  /// 画面上的短时反馈层：中央动作闪现 + 快进/快退文字条。
  /// 构建逻辑放 part 里，避免继续给已登记行数基线的主文件加行。
  List<Widget> _actionOverlays() {
    final feedback = _feedback;
    final flash = _flash;
    return <Widget>[
      if (feedback != null)
        MoviePlayerActionFeedback(
          key: ValueKey(feedback.sequence),
          icon: feedback.icon,
          label: feedback.label,
          placement: feedback.placement,
        ),
      if (flash != null)
        MoviePlayerCenterFlash(
          key: ValueKey('player-flash-${flash.sequence}'),
          icon: flash.icon,
        ),
    ];
  }

  void _showCenterFlash(IconData icon) {
    _flashTimer?.cancel();
    final sequence = (_flash?.sequence ?? 0) + 1;
    _updateState(() {
      _flash = _FlashCue(icon: icon, sequence: sequence);
    });
    // 与动画同长：动画跑完就把整层摘掉，空闲时不留 Overlay 成本。
    _flashTimer = Timer(MotionToken.playerFlash, () {
      if (mounted) {
        _updateState(() => _flash = null);
      }
    });
  }

  void _changeVolume(double delta) {
    _updateState(() {
      _volume = (_volume + delta).clamp(0.0, 100.0);
      _isMuted = _volume <= 0;
    });
    unawaited(_player.setVolume(_volume));
  }

  void _changePlaybackSpeed(double delta) {
    final speed = ((_playbackSpeed + delta).clamp(0.5, 2.0) * 4).round() / 4;
    if (speed == _playbackSpeed) {
      return;
    }
    _updateState(() => _playbackSpeed = speed);
    unawaited(_player.setRate(speed));
  }

  void _showAudioPanel(PlaybackPlan plan) {
    _onPanelOpening();
    showAudioSheet(
      context: context,
      audioMode: _audioMode,
      audioCodec: plan.audioCodec,
      showStreamModes: isWebPlatform && plan.hasAudioCache,
      audioTracks: _availableAudioTracks,
      activeAudioTrackId: _activeAudioTrackId,
      onSwitch: _switchAudioMode,
      onSelectTrack: _selectAudioTrack,
      onClosed: _onPanelClosed,
    );
  }

  void _showSubtitlePanel(PlaybackPlan plan) {
    _onPanelOpening();
    showSubtitleSheet(
      context: context,
      plan: plan,
      activeSubtitleId: _activeSubtitleId,
      embeddedSubtitles: _embeddedSubtitlesFor(plan),
      importedSubtitle: _importedSubtitle,
      onSelect: _selectSubtitle,
      onSelectEmbedded: _selectEmbeddedSubtitle,
      onImport: _importSubtitle,
      onDisable: _disableSubtitle,
      onClosed: _onPanelClosed,
      subtitleScale: _subtitleScale,
      onSubtitleScaleChanged:
          (scale) => _updateState(() => _subtitleScale = scale),
    );
  }

  void _showSpeedPanel() {
    _onPanelOpening();
    showSpeedSheet(
      context: context,
      currentSpeed: _playbackSpeed,
      speedOptions: _MoviePlayerPageState._speedOptions,
      onSelect: (speed) {
        _updateState(() => _playbackSpeed = speed);
        unawaited(_player.setRate(speed));
      },
      onClosed: _onPanelClosed,
    );
  }

  void _showAspectRatioPanel() {
    _onPanelOpening();
    showAspectRatioSheet(
      context: context,
      currentRatio: _aspectRatio,
      isFill: _isFill,
      onSelect: (option) {
        _updateState(() {
          _aspectRatio = option.ratio;
          _isFill = option.isFill;
        });
      },
      onClosed: _onPanelClosed,
    );
  }

  void _showSettingsPanel(PlaybackPlan plan) {
    _onPanelOpening();
    showSettingsSheet(
      context: context,
      plan: plan,
      playbackSpeed: _playbackSpeed,
      currentRatioLabel: _currentRatioLabel,
      audioMode: _audioMode,
      activeSubtitleId: _activeSubtitleId,
      onSpeedTap: _showSpeedPanel,
      onAspectRatioTap: _showAspectRatioPanel,
      onAudioTap: _hasAudioControls(plan) ? () => _showAudioPanel(plan) : null,
      onSubtitleTap: () => _showSubtitlePanel(plan),
      onInfoTap: () => _showInfoPanel(plan),
      onClosed: _onPanelClosed,
    );
  }

  void _showInfoPanel(PlaybackPlan plan) {
    _onPanelOpening();
    showPlaybackInfo(
      context: context,
      plan: plan,
      audioMode: _audioMode,
      currentRatioLabel: _currentRatioLabel,
      volume: _volume,
      isMuted: _isMuted,
      onClosed: _onPanelClosed,
    );
  }

  void _onPanelOpening() {
    _hideTimer?.cancel();
    _controlPanelOpen = true;
    if (!_showControls) {
      _updateState(() => _showControls = true);
    }
  }

  void _onPanelClosed() {
    _controlPanelOpen = false;
    _showControlsAndRestartTimer();
  }

  ({MovieVideoItem? previous, MovieVideoItem? next}) _watchEpisodeNavigation(
    MovieVideoItem? item,
  ) => _episodeNavigation(item, watch: true);

  /// 求同季相邻剧集。
  ///
  /// [watch] 为 true 时供 build 使用（剧集数据变化会重算）；片尾连播只需要
  /// 事件发生那一刻的快照，用 [watch] 为 false 走 read，避免在监听里 watch 触发重建。
  ({MovieVideoItem? previous, MovieVideoItem? next}) _episodeNavigation(
    MovieVideoItem? item, {
    required bool watch,
  }) {
    final seriesId = item?.seriesId;
    final seasonNumber = item?.seasonNumber;
    if (seriesId == null || seasonNumber == null) {
      return (previous: null, next: null);
    }
    final seasonProvider = movieSeasonDetailProvider(
      SeasonKey(seriesId: seriesId, seasonNumber: seasonNumber),
    );
    final season =
        (watch ? ref.watch(seasonProvider) : ref.read(seasonProvider))
            .asData
            ?.value;
    if (season == null || season.episodes.isEmpty) {
      return (previous: null, next: null);
    }
    final episodes = season.episodes;
    final currentIndex = episodes.indexWhere(
      (episode) => episode.id == widget.videoItemId,
    );
    if (currentIndex < 0) {
      return (previous: null, next: null);
    }
    return (
      previous: currentIndex > 0 ? episodes[currentIndex - 1] : null,
      next:
          currentIndex < episodes.length - 1
              ? episodes[currentIndex + 1]
              : null,
    );
  }

  String? _episodeContext(MovieVideoItem? item) {
    final seasonNumber = item?.seasonNumber;
    final episodeNumber = item?.episodeNumber;
    if (seasonNumber == null || episodeNumber == null) {
      return null;
    }
    return AppLocalizations.of(
      context,
    ).videoSeasonEpisodeLabel(seasonNumber, episodeNumber);
  }

  Future<void> _playEpisode(MovieVideoItem episode) async {
    await _syncAndRefreshHistory();
    if (mounted) {
      // 只换掉播放器这一层：go 会连带换掉整条栈，看完一集后系统返回
      // 落在栈底直接退出应用；pushReplacement 保住进入播放页之前的来路。
      context.pushReplacement('/video/${episode.id}/play');
    }
  }

  void _onMouseActivity() {
    if (_controlPanelOpen) {
      return;
    }
    _showControlsAndRestartTimer();
  }

  void _startHideTimer() {
    // 面板关闭回调在 pop 之后才触发，此时本页可能已销毁：
    // 再建定时器就落在 _hideTimer 字段上，dispose 已跑过，没人再取消它。
    if (!mounted) {
      return;
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(_MoviePlayerPageState._hideDelay, () {
      if (mounted && _player.state.playing && !_controlPanelOpen) {
        _updateState(() => _showControls = false);
      }
    });
  }

  void _showControlsAndRestartTimer() {
    _hideTimer?.cancel();
    if (!_showControls && mounted) {
      _updateState(() => _showControls = true);
    }
    _startHideTimer();
  }

  /// 触屏手势档：单击画面只负责显隐控制栏，播放/暂停交给控制栏中央按钮，
  /// 双击仍是左右半屏 ±10 秒。桌面/Web 保留"点画面切播放"的既有习惯。
  void _toggleControlsVisibility() {
    if (_showControls) {
      _hideTimer?.cancel();
      _updateState(() => _showControls = false);
      return;
    }
    _showControlsAndRestartTimer();
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

class _PlayerFeedback {
  const _PlayerFeedback({
    required this.icon,
    required this.label,
    required this.placement,
    required this.sequence,
  });

  final IconData icon;
  final String label;
  final MoviePlayerFeedbackPlacement placement;
  final int sequence;
}

/// 中央动作闪现的一次性提示；[sequence] 换 Key 才能重播入场动画。
class _FlashCue {
  const _FlashCue({required this.icon, required this.sequence});

  final IconData icon;
  final int sequence;
}
