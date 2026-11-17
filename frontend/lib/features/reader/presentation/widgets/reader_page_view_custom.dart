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
      onPointerCancel: _onPointerCancel,
      onPointerSignal: _onPointerSignal,
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
    if (_flipProgress > 0.05 && _isForward) {
      _prepareCurlCapture();
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

  void _startAutoFlip() {
    _prepareCurlCapture();
    _transitionInFlight = true;
    // 确保目标页已构建
    if (_targetPageWidget == null) {
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
      curve: _ReaderPageViewState._flipCurve,
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
    _animController!.reverse(from: _flipProgress).then((_) {
      if (mounted) {
        _updateState(() {
          _flipProgress = 0;
          _isAnimating = false;
        });
      }
      // 取消翻页同样要释放卷页快照：回退动画结束后这两张 ui.Image 若留在
      // State 上，会一直挂到下次成功翻页或页面销毁，反复「拖起又松手」
      // 会让 _prepareCurlCapture 的 guard 复用旧图并持续钉住位图。
      _clearCurlImages();
    });
  }

  void _resetFlip() {
    _flipProgress = 0;
    _isAnimating = false;
    _targetPageWidget = null;
    _clearCurlImages();
    if (mounted) _updateState(() {});
  }
}
