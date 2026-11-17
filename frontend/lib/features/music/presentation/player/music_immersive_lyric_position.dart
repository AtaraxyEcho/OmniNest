part of 'music_immersive_lyrics.dart';

/// 播放位置流绑定、在读行判定与逐字填充同步。
extension _MusicImmersiveLyricPosition on _MusicImmersiveLyricsState {
  void _bindPositionStream() {
    _positionSubscription?.cancel();
    _positionSubscription = widget.player.stream.position.listen(
      _handlePosition,
    );
  }

  void _handlePosition(Duration position) {
    if (!mounted) {
      return;
    }
    _lastKnownPosition = position;
    final nextIndex = _activeLyricIndex(position);
    if (nextIndex != _activeIndex) {
      _updateState(() => _activeIndex = nextIndex);
    }
    _syncFill(position);
  }

  /// 当前行逐字填充动画：填充开关开启、播放中且当前行可估算进度（词级
  /// 数据，或无词级数据时按行时长线性估算）；滚动与居中（多行窗口）形态
  /// 均支持填充。
  Animation<double>? _fillAnimationFor(
    MusicLyricLine line,
    PortalLyricVisualSettings settings,
    Duration? lineDuration,
  ) {
    if (!settings.wordFillEnabled ||
        !widget.player.state.playing ||
        (line.words.isEmpty && lineDuration == null)) {
      return null;
    }
    return _fillController.view;
  }

  /// 指定行的可填充时长：下一行起始与当前行起始之差；末行用音频时长兜底。
  Duration? _lineDurationFor(int index) {
    if (index < 0 || index >= widget.lyrics.length) {
      return null;
    }
    final position = widget.lyrics[index].position;
    if (index + 1 < widget.lyrics.length) {
      final duration = widget.lyrics[index + 1].position - position;
      return duration > Duration.zero ? duration : null;
    }
    final trackDuration = widget.player.state.duration;
    final duration = trackDuration - position;
    return duration > Duration.zero ? duration : null;
  }

  /// 按播放位置重锚逐字填充：优先按词级时间轴推进（已完成词时长 / 总演唱
  /// 时长），无词级数据时按字符数估算的演唱时长推进；两种路径都只将补间
  /// 推进到下一个变化点，唱完后停在满格，不把间奏算进填充。
  void _syncFill(Duration position) {
    if (widget.lyrics.isEmpty) {
      // 位置流在无歌词（未加载曲目 / 纯音乐）时同样到达，此时无填充对象。
      return;
    }
    final activeIndex = _activeIndex.clamp(0, widget.lyrics.length - 1);
    final line = widget.lyrics[activeIndex];
    final settings = widget.lyricSettings ?? PortalLyricVisualSettings.defaults;
    final lineSpan = _lineDurationFor(activeIndex);
    final fillable =
        settings.wordFillEnabled &&
        widget.player.state.playing &&
        (line.words.isNotEmpty || lineSpan != null);
    if (!fillable) {
      if (_fillController.isAnimating) {
        _fillController.stop();
      }
      if (_fillActive) {
        _updateState(() => _fillActive = false);
      }
      return;
    }
    final effective =
        position -
        Duration(
          milliseconds: _effectiveOffsetMs(
            settings,
            trackOffsetMs: widget.trackOffsetMs,
          ),
        );
    final withinLine = effective - line.position;
    final state = line.fillStateAt(withinLine);
    double fraction;
    double target;
    Duration remaining;
    if (state != null) {
      fraction = state.fraction;
      target = state.nextFraction;
      remaining = state.toNextFraction;
    } else {
      // 无词级数据（或整行只有空白词元）：按估算演唱时长推进。
      final vocal = line.estimatedVocalSpan(lineSpan ?? Duration.zero);
      final elapsedMs = withinLine.inMilliseconds;
      final vocalMs = vocal.inMilliseconds;
      fraction =
          elapsedMs <= 0
              ? 0.0
              : vocalMs <= 0
              ? 1.0
              : (elapsedMs / vocalMs).clamp(0.0, 1.0).toDouble();
      target = 1.0;
      // 行首之前不预推进度：补间时长夹到演唱窗口，避免整行提前起算。
      remaining =
          withinLine <= Duration.zero ? Duration.zero : vocal - withinLine;
      if (remaining < Duration.zero) {
        remaining = Duration.zero;
      }
    }
    if (!_fillActive) {
      _updateState(() => _fillActive = true);
    }
    if (_fillController.isAnimating) {
      _fillController.stop();
    }
    _fillController.value = fraction;
    if (remaining > Duration.zero && target > fraction) {
      _fillController.animateTo(
        target,
        duration: remaining,
        curve: Curves.linear,
      );
    }
  }

  /// 生效的歌词延迟（毫秒）：曲目级覆盖优先，其次全局视觉设置。
  int _effectiveOffsetMs(
    PortalLyricVisualSettings settings, {
    required int? trackOffsetMs,
  }) {
    return trackOffsetMs ?? settings.offsetMs;
  }

  /// 当前行下标：先应用歌词延迟校准，再二分定位。
  int _activeLyricIndex(Duration position) {
    if (widget.lyrics.isEmpty) {
      return 0;
    }
    final settings = widget.lyricSettings ?? PortalLyricVisualSettings.defaults;
    final effective =
        position -
        Duration(
          milliseconds: _effectiveOffsetMs(
            settings,
            trackOffsetMs: widget.trackOffsetMs,
          ),
        );
    var low = 0;
    var high = widget.lyrics.length - 1;
    var candidate = 0;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (widget.lyrics[middle].position <= effective) {
        candidate = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return candidate;
  }

  bool _lyricsChanged(
    List<MusicLyricLine> previous,
    List<MusicLyricLine> next,
  ) {
    if (identical(previous, next)) {
      return false;
    }
    if (previous.length != next.length) {
      return true;
    }
    for (var index = 0; index < previous.length; index++) {
      if (previous[index].position != next[index].position ||
          previous[index].text != next[index].text) {
        return true;
      }
    }
    return false;
  }

  void _seekTo(int index) {
    if (index < 0 || index >= widget.lyrics.length) {
      return;
    }
    final settings = widget.lyricSettings ?? PortalLyricVisualSettings.defaults;
    // 行选中与逐字填充都按 `position - offset` 判定，跳转必须加回同一个延迟，
    // 否则校准过延迟后点任意一行都会落到与在读行相差 offset 的时刻：播放后
    // 立刻跳到上一行或下一行，用户读作"延迟没生效"。
    var target =
        widget.lyrics[index].position +
        Duration(
          milliseconds: _effectiveOffsetMs(
            settings,
            trackOffsetMs: widget.trackOffsetMs,
          ),
        );
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (_activeIndex != index) {
      _updateState(() => _activeIndex = index);
    }
    unawaited(widget.onSeek(target));
  }
}
