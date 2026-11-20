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

  void _onDragStart(DragStartDetails details) {
    if (ReaderInteractionGate.blocksInput(_blockReason)) return;
    _isDragging = true;
    _totalDeltaX = 0;
    _dragStartX = details.localPosition.dx;
    final w = context.size?.width ?? 1;
    final h = context.size?.height ?? 1;
    _isForward = details.localPosition.dx >= w * 0.5;
    final fy = (details.localPosition.dy / math.max(1.0, h)).clamp(0.08, 0.92);
    _activeCurlConfig = CurlGrabConfig.fromPointerFy(fy);
    _prepareCurlCapture(_isForward ? CurlDirection.next : CurlDirection.prev);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || ReaderInteractionGate.blocksInput(_blockReason)) {
      return;
    }
    final w = context.size?.width ?? 1;
    final h = context.size?.height ?? 1;
    // 直接基于起点绝对位移计算进度，消除死区滞后并真正跟手。
    _totalDeltaX = details.localPosition.dx - _dragStartX;

    if (_totalDeltaX < 0) {
      if (widget.state.isLastPage &&
          !widget.state.hasMore &&
          !widget.state.hasNextChapter) {
        _flipProgress = 0;
        return;
      }
      _isForward = true;
      _flipProgress = (-_totalDeltaX / (w * 0.52)).clamp(0.0, 1.0);
    } else if (_totalDeltaX > 0) {
      if (widget.state.isFirstPage && !widget.state.hasPreviousChapter) {
        _flipProgress = 0;
        return;
      }
      _isForward = false;
      _flipProgress = (_totalDeltaX / (w * 0.52)).clamp(0.0, 1.0);
    }

    // 实时平滑跟随鼠标 Y 坐标微调折角斜率，纸角真正粘在指针上。
    final fy = (details.localPosition.dy / math.max(1.0, h)).clamp(0.08, 0.92);
    final targetCfg = CurlGrabConfig.fromPointerFy(fy);
    _activeCurlConfig = CurlGrabConfig(
      bottomCorner: _activeCurlConfig.bottomCorner,
      slant:
          _activeCurlConfig.slant +
          (targetCfg.slant - _activeCurlConfig.slant) * 0.25,
    );

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
    if (widget.turnMode == PageTurnMode.fade &&
        _flipProgress > 0.05 &&
        _targetPageWidget == null) {
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
    final ms = ((commit ? 360 : 240) + 180 * (to - from).abs()).round().clamp(
      160,
      540,
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
        // Book 模式绝不退化为 2D 平推：复位在途标志并直接提交翻页，防止闸门锁死。
        _transitionInFlight = false;
        _isAnimating = false;
        _commitFlip();
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
    ctrl.animateTo(
      1,
      duration: ctrl.duration,
      curve: const Cubic(0.22, 1.0, 0.36, 1.0),
    );
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

    if (widget.turnMode == PageTurnMode.cover) {
      // 保持卷页终帧直到 didUpdateWidget 收到新 pageIndex 再复位，消除 1 帧闪烁；
      // 同步挂 120ms 安全定时器，防止父级未更新 pageIndex 时状态锁死。
      _animController?.removeListener(_syncCurlFrameFromAnim);
      _isAnimating = false;
      _commitResetFallbackTimer?.cancel();
      _commitResetFallbackTimer = Timer(const Duration(milliseconds: 120), () {
        if (mounted &&
            (_curlFrameNotifier.value.active || _transitionInFlight)) {
          _resetFlip();
        }
      });
      widget.callbacks.onPageChanged(newPage);
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
    _commitResetFallbackTimer?.cancel();
    _commitResetFallbackTimer = null;
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
