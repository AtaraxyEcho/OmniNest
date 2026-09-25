part of 'reader_page_view.dart';

/// Cover/Fade 模式手势拖动与翻页动画。
extension _ReaderPageViewCustom on _ReaderPageViewState {
  // ══════════════════════════════════════════
  // Cover / Fade 模式：自定义手势 + 动画
  // ══════════════════════════════════════════

  Widget _buildCustomMode() {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: _buildAnimationContent(),
    );
  }

  void _onDragStart(DragStartDetails details) {
    if (ReaderInteractionGate.blocksInput(_blockReason)) return;
    _isDragging = true;
    _totalDeltaX = 0;
    _isForward = true;
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
      _flipProgress = (-_totalDeltaX / w).clamp(0.0, 1.0);
    } else if (_totalDeltaX > 0) {
      // 向后拖动：检查是否已在第一页
      if (widget.state.isFirstPage && !widget.state.hasPreviousChapter) {
        _flipProgress = 0;
        return;
      }
      _isForward = false;
      _flipProgress = (_totalDeltaX / w).clamp(0.0, 1.0);
    }

    // 拖动超过阈值时预构建目标页（仅首次需要 setState 让 AnimatedBuilder 生效）
    if (_flipProgress > 0.05 && _targetPageWidget == null) {
      final targetIndex =
          _isForward ? widget.state.pageIndex + 1 : widget.state.pageIndex - 1;
      if (targetIndex >= 0) {
        _targetPageWidget = widget.pageBuilder(targetIndex);
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

  void _startAutoFlip() {
    _transitionInFlight = true;
    // 确保目标页已构建
    if (_targetPageWidget == null) {
      final targetIndex =
          _isForward ? widget.state.pageIndex + 1 : widget.state.pageIndex - 1;
      if (targetIndex >= 0) {
        _targetPageWidget = widget.pageBuilder(targetIndex);
      }
    }

    _isAnimating = true;
    final ctrl = _animController!;
    ctrl.duration = Duration(
      milliseconds: (_ReaderPageViewState._flipDurationMs * (1 - _flipProgress))
          .round()
          .clamp(100, _ReaderPageViewState._flipDurationMs),
    );

    ctrl.value = _flipProgress;
    // 动画启动时触发一次 build 进入 AnimatedBuilder 分支；
    // 后续每帧由 AnimatedBuilder 直接驱动，不再经过 setState。
    if (mounted) _updateState(() {});
    ctrl.animateTo(
      1,
      duration: ctrl.duration,
      curve: _ReaderPageViewState._turnCurve,
    );
    ctrl.addStatusListener(_onAutoFlipStatus);
  }

  void _onAutoFlipStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _animController?.removeStatusListener(_onAutoFlipStatus);
      _commitFlip();
    }
  }

  void _commitFlip() {
    final newPage =
        _isForward ? widget.state.pageIndex + 1 : widget.state.pageIndex - 1;

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
    _animController!.reverse(from: _flipProgress).then((_) {
      if (mounted) {
        _updateState(() {
          _flipProgress = 0;
          _isAnimating = false;
        });
      }
    });
  }

  void _resetFlip() {
    _flipProgress = 0;
    _isAnimating = false;
    _targetPageWidget = null;
    if (mounted) _updateState(() {});
  }
}
