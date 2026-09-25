part of 'music_immersive_lyrics.dart';

/// 滚动跟随、手动滚动暂停与回到当前行。
extension _MusicImmersiveLyricFollow on _MusicImmersiveLyricsState {
  /// 滚动通知处理：手动滚动暂停跟随；拖动（非滚轮）时预览目标行并在松手后跳转。
  bool _handleScrollNotification(
    ScrollNotification notification, {
    required double slotHeight,
    required double leadPadding,
    required double anchor,
  }) {
    // 用户滚动判定：拖拽、滚轮、滚动条都会派发非 idle 的
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _pauseFollow();
    }
    // 仅真实拖动做预览与松手跳转：滚轮/滚动条只暂停跟随。
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final preview = _indexAtAnchor(
        notification.metrics,
        slotHeight: slotHeight,
        leadPadding: leadPadding,
        anchor: anchor,
      );
      if (preview != _previewIndex) {
        _updateState(() => _previewIndex = preview);
      }
    } else if (notification is ScrollEndNotification) {
      final preview = _previewIndex;
      if (preview != null) {
        _previewIndex = null;
        _followResumeTimer?.cancel();
        _updateState(() => _userScrolling = false);
        _seekTo(preview);
        return false;
      }
      if (_userScrolling) {
        _resumeFollowAfterDelay();
      }
    }
    return false;
  }

  /// 焦点位命中的歌词行下标（拖动预览与松手跳转共用）。
  int _indexAtAnchor(
    ScrollMetrics metrics, {
    required double slotHeight,
    required double leadPadding,
    required double anchor,
  }) {
    if (slotHeight <= 0) {
      return _activeIndex;
    }
    final focusOffset =
        metrics.pixels - leadPadding + metrics.viewportDimension * anchor;
    final index = (focusOffset / slotHeight).floor();
    return index.clamp(0, widget.lyrics.length - 1);
  }

  /// 焦点行的滚动目标偏移。
  double _followTarget(ScrollPosition position) {
    final anchor = _focusAnchor;
    final target =
        _leadPadding +
        _activeIndex * _slotHeight +
        _slotHeight / 2 -
        position.viewportDimension * anchor;
    return target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  /// 跟随当前行：把活动行滚到焦点位（仅列表已挂载且未处于手动滚动期）。
  void _scheduleFollowActive() {
    if (_userScrolling) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _userScrolling) {
        return;
      }
      _followNow(_followTarget(_scrollController.position));
    });
  }

  /// 执行一次跟随滚动；动画进行中只保留最后一个目标（合并快速 seek 的排队）。
  void _followNow(double target, {bool force = false}) {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (!force && (position.pixels - target).abs() < 1) {
      return;
    }
    if (_followAnimating) {
      _pendingFollowTarget = target;
      return;
    }
    _followAnimating = true;
    unawaited(
      _scrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          )
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(() {
            _followAnimating = false;
            final pending = _pendingFollowTarget;
            _pendingFollowTarget = null;
            if (mounted && pending != null) {
              _followNow(pending);
            }
          }),
    );
  }

  /// 生效的文本排列：块锚点非居中时由锚点决定（居左→左对齐、居右→右对齐），
  TextAlign get _effectiveTextAlign {
    if (widget.blockAnchor == Alignment.centerLeft) {
      return TextAlign.left;
    }
    if (widget.blockAnchor == Alignment.centerRight) {
      return TextAlign.right;
    }
    return widget.textAlign;
  }

  void _pauseFollow() {
    _followResumeTimer?.cancel();
    if (!_userScrolling) {
      _updateState(() => _userScrolling = true);
    }
  }

  void _resumeFollowAfterDelay() {
    _followResumeTimer?.cancel();
    _followResumeTimer = Timer(
      _MusicImmersiveLyricsState._followResumeDelay,
      () {
        if (!mounted) {
          return;
        }
        _updateState(() => _userScrolling = false);
      },
    );
  }

  /// 回到当前播放：恢复跟随并把当前行滚回焦点位。
  void _backToCurrent() {
    _followResumeTimer?.cancel();
    _updateState(() {
      _userScrolling = false;
      _previewIndex = null;
    });
    if (_scrollController.hasClients) {
      _followNow(_followTarget(_scrollController.position), force: true);
    }
  }
}
