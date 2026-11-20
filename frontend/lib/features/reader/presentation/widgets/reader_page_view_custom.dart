part of 'reader_page_view.dart';

/// Cover/Fade 模式手势拖动与翻页动画。
extension _ReaderPageViewCustom on _ReaderPageViewState {
  // ══════════════════════════════════════════
  // Cover / Fade 模式：自定义手势 + 动画
  // ══════════════════════════════════════════

  Widget _buildCustomMode() {
    return MouseRegion(
      cursor:
          _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.basic,
      onHover: _onCurlHover,
      onExit: (_) => _clearCurlPeek(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        onPointerSignal: _onPointerSignal,
        child: _buildAnimationContent(),
      ),
    );
  }

  /// 桌面悬停边角微翘（对齐样例 ReaderView.tsx:190-194：fy > 0.82 && fx > 0.9 / < 0.1）。
  void _onCurlHover(PointerEvent event) {
    if (widget.turnMode != PageTurnMode.cover || _isDragging || _isAnimating) {
      return;
    }
    final size = context.size;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    final fx = event.localPosition.dx / size.width;
    final fy = event.localPosition.dy / size.height;
    CurlDirection? dir;
    if (fy > 0.82 &&
        fx > 0.90 &&
        (!widget.state.isLastPage || widget.state.hasNextChapter)) {
      dir = CurlDirection.next;
    } else if (fy > 0.82 &&
        fx < 0.10 &&
        (!widget.state.isFirstPage || widget.state.hasPreviousChapter)) {
      dir = CurlDirection.prev;
    }
    if (dir == null) {
      _clearCurlPeek();
      return;
    }
    if (!_hasReadyCurlPair(dir)) {
      unawaited(_ensureCurlPairReady(dir));
      return;
    }
    final current = _curlFrameNotifier.value;
    if (!current.active || current.isPeek) {
      final wasActive = current.active;
      _activeCurlConfig = CurlGrabConfig.hoverPeek;
      _curlFrameNotifier.value = CurlFrame(
        progress: 0.045,
        direction: dir,
        config: CurlGrabConfig.hoverPeek,
        isPeek: true,
      );
      if (!wasActive && mounted) _updateState(() {});
    }
  }

  void _clearCurlPeek() {
    if (_curlFrameNotifier.value.isPeek) {
      _curlFrameNotifier.value = CurlFrame.idle;
      if (mounted) _updateState(() {});
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (ReaderInteractionGate.blocksInput(_blockReason)) return;
    _isDragging = true;
    _totalDeltaX = 0;
    _isForward = true;
    final h = context.size?.height ?? 1;
    final fy = (details.localPosition.dy / math.max(1.0, h)).clamp(0.0, 1.0);
    _activeCurlConfig = CurlGrabConfig.fromPointerFy(fy);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || ReaderInteractionGate.blocksInput(_blockReason)) {
      return;
    }
    _totalDeltaX += details.delta.dx;

    final w = context.size?.width ?? 1;

    if (_totalDeltaX < 0) {
      // 向前拖动：检查是否已在最后一页
      if (widget.state.isLastPage &&
          !widget.state.hasMore &&
          !widget.state.hasNextChapter) {
        _flipProgress = 0;
        return;
      }
      _isForward = true;
      _flipProgress = (-_totalDeltaX / (w * 0.68)).clamp(0.0, 1.0);
    } else if (_totalDeltaX > 0) {
      // 向后拖动：检查是否已在第一页
      if (widget.state.isFirstPage && !widget.state.hasPreviousChapter) {
        _flipProgress = 0;
        return;
      }
      _isForward = false;
      _flipProgress = (_totalDeltaX / (w * 0.68)).clamp(0.0, 1.0);
    }

    if (widget.turnMode == PageTurnMode.cover && _flipProgress > 0.005) {
      final dir = _isForward ? CurlDirection.next : CurlDirection.prev;
      if (!_hasReadyCurlPair(dir)) {
        _prepareCurlCapture();
      } else {
        final wasActive = _curlFrameNotifier.value.active;
        _curlFrameNotifier.value = CurlFrame(
          progress: _flipProgress,
          direction: dir,
          config: _activeCurlConfig,
        );
        // 仅从静止切换到卷页首帧触发一次 build，后续全程 0-Rebuild。
        if (!wasActive && mounted) _updateState(() {});
      }
    }
    if (_flipProgress > 0.05 && _targetPageWidget == null) {
      final targetIndex =
          _isForward
              ? widget.state.pageIndex + pageStep
              : widget.state.pageIndex - pageStep;
      if (targetIndex >= 0) {
        _targetPageWidget = pageAt(targetIndex);
        if (mounted) _updateState(() {});
      }
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging || ReaderInteractionGate.blocksInput(_blockReason)) {
      return;
    }
    _isDragging = false;

    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldFlip =
        _flipProgress > _ReaderPageViewState._commitThreshold ||
        velocity.abs() > 300;

    if (shouldFlip) {
      _startAutoFlip();
    } else {
      _cancelFlip();
    }
  }
  // ── 自定义动画 ──

  void _syncCurlFrameFromAnim() {
    if (widget.turnMode != PageTurnMode.cover) return;
    final ctrl = _animController;
    if (ctrl == null) return;
    final dir = _isForward ? CurlDirection.next : CurlDirection.prev;
    if (_hasReadyCurlPair(dir)) {
      _curlFrameNotifier.value = CurlFrame(
        progress: ctrl.value,
        direction: dir,
        config: _activeCurlConfig,
      );
    }
  }

  Duration _curlDuration({
    required double from,
    required double to,
    required bool commit,
  }) {
    final ms = ((commit ? 420 : 300) + 380 * (to - from).abs()).round().clamp(
      140,
      820,
    );
    return Duration(milliseconds: ms);
  }

  Future<void> _startAutoFlip() async {
    if (_awaitingCurlStart) return;
    final dir = _isForward ? CurlDirection.next : CurlDirection.prev;

    if (widget.turnMode == PageTurnMode.cover && !_hasReadyCurlPair(dir)) {
      _awaitingCurlStart = true;
      final ready = await _ensureCurlPairReady(dir);
      _awaitingCurlStart = false;
      if (!mounted) return;
      if (!ready) {
        // 极端跨域无法抓图时兜底
        _runAutoFlipAnimation(useCurl: false);
        return;
      }
    }
    _runAutoFlipAnimation(useCurl: widget.turnMode == PageTurnMode.cover);
  }

  void _runAutoFlipAnimation({required bool useCurl}) {
    _transitionInFlight = true;
    if (!useCurl && _targetPageWidget == null) {
      final targetIndex =
          _isForward
              ? widget.state.pageIndex + pageStep
              : widget.state.pageIndex - pageStep;
      if (targetIndex >= 0) {
        _targetPageWidget = pageAt(targetIndex);
      }
    }

    _isAnimating = true;
    final ctrl = _animController!;
    final startValue =
        _curlFrameNotifier.value.isPeek
            ? _curlFrameNotifier.value.progress
            : math.max(0.02, _flipProgress);
    ctrl.duration = _curlDuration(from: startValue, to: 1.0, commit: true);
    ctrl.removeListener(_syncCurlFrameFromAnim);
    ctrl.addListener(_syncCurlFrameFromAnim);
    ctrl.value = startValue;
    if (useCurl) {
      final dir = _isForward ? CurlDirection.next : CurlDirection.prev;
      _curlFrameNotifier.value = CurlFrame(
        progress: startValue,
        direction: dir,
        config: _activeCurlConfig,
      );
    }
    if (mounted) _updateState(() {});
    ctrl.removeStatusListener(_onAutoFlipStatus);
    ctrl.addStatusListener(_onAutoFlipStatus);
    ctrl.animateTo(1, duration: ctrl.duration, curve: Curves.easeInOutQuad);
  }

  void _onAutoFlipStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _animController?.removeStatusListener(_onAutoFlipStatus);
      _commitFlip();
    }
  }

  void _commitFlip() {
    final newPage =
        _isForward
            ? widget.state.pageIndex + pageStep
            : widget.state.pageIndex - pageStep;

    if (newPage < 0) {
      _resetFlip();
      _dispatchBoundaryRequest(
        widget.callbacks.onPreviousChapter,
        hasNeighbor: widget.state.hasPreviousChapter,
      );
      return;
    }
    if (newPage >= _localPageCount && !widget.state.hasMore) {
      _resetFlip();
      _dispatchBoundaryRequest(
        widget.callbacks.onNextChapter,
        hasNeighbor: widget.state.hasNextChapter,
      );
      return;
    }

    _resetFlip();
    widget.callbacks.onPageChanged(newPage);
  }

  void _cancelFlip() {
    _isAnimating = true;
    final ctrl = _animController!;
    ctrl.removeListener(_syncCurlFrameFromAnim);
    ctrl.addListener(_syncCurlFrameFromAnim);
    ctrl.reverse(from: _flipProgress).then((_) {
      ctrl.removeListener(_syncCurlFrameFromAnim);
      _curlFrameNotifier.value = CurlFrame.idle;
      if (mounted) {
        _updateState(() {
          _flipProgress = 0;
          _isAnimating = false;
          _transitionInFlight = false;
        });
      }
      _scheduleIdleNextCurlWarmup();
    });
  }

  void _resetFlip() {
    _animController?.removeListener(_syncCurlFrameFromAnim);
    _curlFrameNotifier.value = CurlFrame.idle;
    _flipProgress = 0;
    _isAnimating = false;
    _transitionInFlight = false;
    _targetPageWidget = null;
    _clearCurlImages();
    if (mounted) _updateState(() {});
    _scheduleIdleNextCurlWarmup();
  }
}
