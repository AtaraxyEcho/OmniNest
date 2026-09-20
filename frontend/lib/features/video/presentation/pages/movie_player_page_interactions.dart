part of 'movie_player_page.dart';

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
    try {
      if (_player.state.playing) {
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
    // 标准播放器手势：点击画面切换播放/暂停（有无控制栏均生效）。
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
  ) {
    final seriesId = item?.seriesId;
    final seasonNumber = item?.seasonNumber;
    if (seriesId == null || seasonNumber == null) {
      return (previous: null, next: null);
    }
    final season =
        ref
            .watch(
              movieSeasonDetailProvider(
                SeasonKey(seriesId: seriesId, seasonNumber: seasonNumber),
              ),
            )
            .asData
            ?.value;
    if (season == null || season.episodes.isEmpty) {
      return (previous: null, next: null);
    }
    final episodes = [...season.episodes]..sort(
      (left, right) =>
          (left.episodeNumber ?? 0).compareTo(right.episodeNumber ?? 0),
    );
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
      context.go('/video/${episode.id}/play');
    }
  }

  void _onMouseActivity() {
    if (_controlPanelOpen) {
      return;
    }
    _showControlsAndRestartTimer();
  }

  void _startHideTimer() {
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
