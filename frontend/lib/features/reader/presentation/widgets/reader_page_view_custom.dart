part of 'reader_page_view.dart';

/// Cover/Fade 模式手势拖动与翻页动画（v7：单向方向锁 + 永不锁死代数状态机）。
extension _ReaderPageViewCustom on _ReaderPageViewState {
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
    final w = context.size?.width ?? 1;
    final h = context.size?.height ?? 1;
    final wantForward = details.localPosition.dx >= w * 0.5;

    // 边界预检：在末页按右侧或首页按左侧时直接拒绝启动拖拽，不残留任何状态。
    if (wantForward &&
        widget.state.isLastPage &&
        !widget.state.hasMore &&
        !widget.state.hasNextChapter) {
      return;
    }
    if (!wantForward &&
        widget.state.isFirstPage &&
        !widget.state.hasPreviousChapter) {
      return;
    }

    // 单向锁定整次拖拽方向（1:1 对齐样例 ReaderView.tsx:182），
    // 按右侧只能左拉翻下一页，往右拉回起点绝不反转触发上翻！
    _isDragging = true;
    _isForward = wantForward;
    _dragLockedDir = wantForward ? CurlDirection.next : CurlDirection.prev;
    _totalDeltaX = 0;
    _dragStartX = details.localPosition.dx;
    final fy = (details.localPosition.dy / math.max(1.0, h)).clamp(0.08, 0.92);
    _activeCurlConfig = CurlGrabConfig.fromPointerFy(fy);
    _prepareCurlCapture(_dragLockedDir!);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || ReaderInteractionGate.blocksInput(_blockReason)) {
      return;
    }
    final lockedDir = _dragLockedDir;
    if (lockedDir == null) return;

    final w = context.size?.width ?? 1;
    final h = context.size?.height ?? 1;
    _totalDeltaX = details.localPosition.dx - _dragStartX;

    // 严禁中途修改 _isForward：始终按锁定方向计算单向有效位移。
    final dist = lockedDir == CurlDirection.next ? -_totalDeltaX : _totalDeltaX;
    final leafWidth = widget.spread ? w / 2.0 : w;
    final dragSpan = math.max(120.0, leafWidth * 1.35);

    if (dist <= 0) {
      _flipProgress = 0.0;
      if (widget.turnMode == PageTurnMode.cover &&
          _curlFrameNotifier.value.active) {
        _curlFrameNotifier.value = CurlFrame.idle;
        if (mounted) _updateState(() {});
      }
      return;
    }

    _flipProgress = (dist / dragSpan).clamp(0.0, 1.0);

    // 实时平滑跟随鼠标 Y 坐标微调折角斜率，纸角自然粘在指针上。
    final fy = (details.localPosition.dy / math.max(1.0, h)).clamp(0.08, 0.92);
    final targetCfg = CurlGrabConfig.fromPointerFy(fy);
    _activeCurlConfig = CurlGrabConfig(
      bottomCorner: _activeCurlConfig.bottomCorner,
      slant:
          _activeCurlConfig.slant +
          (targetCfg.slant - _activeCurlConfig.slant) * 0.25,
    );

    if (widget.turnMode == PageTurnMode.cover && _flipProgress > 0.005) {
      if (!_hasReadyCurlPair(lockedDir)) {
        _prepareCurlCapture(lockedDir);
      } else {
        final wasActive = _curlFrameNotifier.value.active;
        _curlFrameNotifier.value = CurlFrame(
          progress: _flipProgress,
          direction: lockedDir,
          config: _activeCurlConfig,
        );
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
      _isDragging = false;
      _dragLockedDir = null;
      return;
    }
    _isDragging = false;
    final lockedDir = _dragLockedDir;
    _dragLockedDir = null;
    if (lockedDir == null) {
      _cancelFlip();
      return;
    }

    final velocity = details.velocity.pixelsPerSecond.dx;
    final directionalFling =
        lockedDir == CurlDirection.next ? velocity < -340 : velocity > 340;
    final shouldFlip =
        _flipProgress > _ReaderPageViewState._commitThreshold ||
        (_flipProgress >= 0.06 && directionalFling);

    if (shouldFlip) {
      _startAutoFlip();
    } else {
      _cancelFlip();
    }
  }

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
    final ms = ((commit ? 400 : 260) + 260 * (to - from).abs()).round().clamp(
      180,
      640,
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
        _transitionInFlight = false;
        _isAnimating = false;
        _commitFlip();
        return;
      }
    }
    _runAutoFlipAnimation(useCurl: widget.turnMode == PageTurnMode.cover);
  }

  void _runAutoFlipAnimation({required bool useCurl}) {
    final ctrl = _animController;
    if (ctrl == null) {
      _commitFlip();
      return;
    }
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

    final startValue =
        _curlFrameNotifier.value.isPeek
            ? _curlFrameNotifier.value.progress
            : math.max(0.02, _flipProgress);

    // 关键修复：若已拖到 1.0，AnimationController.animateTo(1) 不会派发 completed 回调！
    // 直接提交翻页，彻底根除 gate=pageAnimation 永久锁死。
    if (startValue >= 0.995) {
      _isAnimating = false;
      _commitFlip();
      return;
    }

    final gen = ++_animGeneration;
    _isAnimating = true;
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

    ctrl
        .animateTo(
          1.0,
          duration: ctrl.duration,
          curve: const Cubic(0.22, 1.0, 0.36, 1.0),
        )
        .then<void>(
          (_) {
            if (!mounted || gen != _animGeneration) return;
            _commitFlip();
          },
          onError: (_) {
            if (!mounted || gen != _animGeneration) return;
            _resetFlip();
          },
        );
  }

  void _onAutoFlipStatus(AnimationStatus status) {
    // 保留空方法体以兼容 reader_page_view_turn.dart 中的 dispose removeStatusListener 调用。
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
      _animController?.removeListener(_syncCurlFrameFromAnim);
      _isAnimating = false;
      _commitResetFallbackTimer?.cancel();
      _commitResetFallbackTimer = Timer(const Duration(milliseconds: 120), () {
        if (mounted &&
            (_curlFrameNotifier.value.active ||
                _transitionInFlight ||
                _isAnimating)) {
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
    _dragLockedDir = null;
    final ctrl = _animController;
    // 零位移松手直接同步复位，绝不空跑 reverse(from: 0) 导致锁死。
    if (ctrl == null || _flipProgress <= 0.005) {
      _animGeneration++;
      ctrl?.removeListener(_syncCurlFrameFromAnim);
      _curlFrameNotifier.value = CurlFrame.idle;
      _flipProgress = 0;
      _isAnimating = false;
      _transitionInFlight = false;
      if (mounted) _updateState(() {});
      _scheduleIdleNextCurlWarmup();
      return;
    }

    final gen = ++_animGeneration;
    _isAnimating = true;
    ctrl.removeListener(_syncCurlFrameFromAnim);
    ctrl.addListener(_syncCurlFrameFromAnim);
    ctrl.duration = _curlDuration(from: _flipProgress, to: 0.0, commit: false);
    ctrl.reverse(from: _flipProgress).whenComplete(() {
      if (gen != _animGeneration) return;
      ctrl.removeListener(_syncCurlFrameFromAnim);
      _curlFrameNotifier.value = CurlFrame.idle;
      _flipProgress = 0;
      _isAnimating = false;
      _transitionInFlight = false;
      if (mounted) _updateState(() {});
      _scheduleIdleNextCurlWarmup();
    });
  }

  void _resetFlip() {
    _animGeneration++;
    _awaitingCurlStart = false;
    _dragLockedDir = null;
    _isDragging = false;
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
