part of 'reader_page_view.dart';

/// 双向卷页双槽空闲预抓图与装配（v3：同时预热 next + prev，正反翻页 0ms 起手）。
extension _ReaderPageViewCurl on _ReaderPageViewState {
  void _scheduleIdleNextCurlWarmup() {
    _curlWarmupTimer?.cancel();
    if (widget.turnMode != PageTurnMode.cover) return;
    _curlWarmupTimer = Timer(const Duration(milliseconds: 80), () async {
      if (!mounted || _curlFrameNotifier.value.active || _isDragging) return;
      await _ensureCurlPairReady(CurlDirection.next);
      if (!mounted || _curlFrameNotifier.value.active || _isDragging) return;
      await _ensureCurlPairReady(CurlDirection.prev);
    });
  }

  bool _hasReadyCurlPair(CurlDirection dir) {
    final pair = _curlPairs[dir];
    return pair != null &&
        pair.pageIndex == widget.state.pageIndex &&
        pair.chapterId == widget.state.chapterId;
  }

  void _prepareCurlCapture([CurlDirection? explicitDir]) {
    if (widget.turnMode != PageTurnMode.cover) return;
    final dir =
        explicitDir ?? (_isForward ? CurlDirection.next : CurlDirection.prev);
    if (_hasReadyCurlPair(dir) || _capturingDirs.contains(dir)) return;
    unawaited(_ensureCurlPairReady(dir));
  }

  Future<bool> _ensureCurlPairReady(CurlDirection dir) async {
    if (widget.turnMode != PageTurnMode.cover || !mounted) return false;
    if (_hasReadyCurlPair(dir)) return true;

    // 串行化访问共享的 _singleBackCaptureKey，杜绝 next/prev 并发覆写抓图槽。
    while (_backCaptureLock != null) {
      await _backCaptureLock!.future;
      if (!mounted) return false;
      if (_hasReadyCurlPair(dir)) return true;
    }

    final lock = Completer<void>();
    _backCaptureLock = lock;
    _capturingDirs.add(dir);
    final token = _curlToken;
    try {
      if (token != _curlToken) return false;
      final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.35);
      final liveKey =
          widget.spread
              ? (dir == CurlDirection.next ? _liveRightKey : _liveLeftKey)
              : _liveSingleKey;
      final frontImg = await _captureBoundarySafe(liveKey, dpr);
      if (!mounted || token != _curlToken || frontImg == null) {
        frontImg?.dispose();
        return false;
      }

      final backWidget = _resolveCurlBackWidget(dir);
      if (backWidget == null) {
        frontImg.dispose();
        return false;
      }

      _updateState(() => _pendingBackCaptureWidget = backWidget);
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || token != _curlToken) {
        frontImg.dispose();
        return false;
      }

      final backImg = await _captureBoundarySafe(_singleBackCaptureKey, dpr);
      if (mounted) {
        _updateState(() => _pendingBackCaptureWidget = null);
      } else {
        _pendingBackCaptureWidget = null;
      }

      if (!mounted || token != _curlToken || backImg == null) {
        frontImg.dispose();
        backImg?.dispose();
        return false;
      }

      final old = _curlPairs[dir];
      _curlPairs[dir] = (
        front: frontImg,
        back: backImg,
        chapterId: widget.state.chapterId,
        pageIndex: widget.state.pageIndex,
      );
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          old.front.dispose();
          old.back.dispose();
        });
      }
      // 关键修复：若抓图完成时用户仍在同方向拖拽，立刻补发当前进度首帧，杜绝偶发哑火！
      final dragDir = _isForward ? CurlDirection.next : CurlDirection.prev;
      if (mounted && _isDragging && dragDir == dir && _flipProgress > 0.005) {
        final wasActive = _curlFrameNotifier.value.active;
        _curlFrameNotifier.value = CurlFrame(
          progress: _flipProgress,
          direction: dir,
          config: _activeCurlConfig,
        );
        if (!wasActive) _updateState(() {});
      }
      return true;
    } finally {
      _capturingDirs.remove(dir);
      if (mounted && _pendingBackCaptureWidget != null) {
        _updateState(() => _pendingBackCaptureWidget = null);
      }
      if (identical(_backCaptureLock, lock)) {
        _backCaptureLock = null;
      }
      if (!lock.isCompleted) lock.complete();
    }
  }

  Widget? _resolveCurlBackWidget(CurlDirection dir) {
    final idx = widget.state.pageIndex;
    final targetIdx =
        dir == CurlDirection.next
            ? (widget.spread ? idx + 2 : idx + 1)
            : idx - 1;
    final builder = widget.snapshotPageBuilder ?? widget.pageBuilder;
    final inChapter = targetIdx >= 0 ? builder(targetIdx) : null;
    if (inChapter != null) return inChapter;
    return widget.crossChapterSnapshotBuilder?.call(
      dir == CurlDirection.next ? 1 : -1,
    );
  }

  /// 循环等待 RenderRepaintBoundary 完成本帧绘制后再调用 toImage，
  /// 彻底杜绝 '!debugNeedsPaint' 异常导致静默返回 null。
  Future<ui.Image?> _captureBoundarySafe(GlobalKey key, double ratio) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted) return null;
      final ro = key.currentContext?.findRenderObject();
      if (ro is RenderRepaintBoundary &&
          !ro.debugNeedsPaint &&
          ro.hasSize &&
          !ro.size.isEmpty) {
        try {
          return await ro.toImage(pixelRatio: ratio);
        } on Object {
          return null;
        }
      }
      WidgetsBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame;
    }
    return null;
  }

  void _clearCurlImages() {
    _curlWarmupTimer?.cancel();
    _curlToken++;
    _capturingDirs.clear();
    _pendingBackCaptureWidget = null;
    if (_curlPairs.isEmpty) return;
    final oldPairs = _curlPairs.values.toList(growable: false);
    _curlPairs.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final p in oldPairs) {
        p.front.dispose();
        p.back.dispose();
      }
    });
  }

  void _disposeCurlImages() {
    _curlWarmupTimer?.cancel();
    _curlToken++;
    _capturingDirs.clear();
    _pendingBackCaptureWidget = null;
    for (final p in _curlPairs.values) {
      p.front.dispose();
      p.back.dispose();
    }
    _curlPairs.clear();
  }

  Widget? _buildCurlTurn(double width, double height) {
    final frame = _curlFrameNotifier.value;
    if (!frame.active || !_hasReadyCurlPair(frame.direction)) return null;
    final pair = _curlPairs[frame.direction];
    if (pair == null) return null;

    final curlLayer = ReaderPageCurl(
      frameListenable: _curlFrameNotifier,
      front: pair.front,
      back: pair.back,
      paper: widget.surfaceColor,
      spread: widget.spread,
    );

    if (!widget.spread) {
      final targetIndex =
          frame.direction == CurlDirection.next
              ? widget.state.pageIndex + 1
              : widget.state.pageIndex - 1;
      final revealed =
          targetIndex >= 0 ? widget.pageBuilder(targetIndex) : null;
      // 单页窄窗与静止态保持统一无圆角裁切，消除翻页起止瞬间四角闪烁。
      return Stack(
        fit: StackFit.expand,
        children: [_constrainPage(revealed), Positioned.fill(child: curlLayer)],
      );
    }

    final idx = widget.state.pageIndex;
    final last = widget.state.pageCount <= 1 ? 1 : widget.state.pageCount - 1;
    final isNext = frame.direction == CurlDirection.next;
    final underlayLeft =
        (isNext
            ? widget.pageBuilder(idx)
            : (idx - 2 >= 0
                ? widget.pageBuilder(idx - 2)
                : widget.crossChapterSnapshotBuilder?.call(-1))) ??
        const SizedBox.expand();
    final underlayRight =
        isNext
            ? (widget.pageBuilder(idx + 3) ??
                (idx + 2 >= widget.state.pageCount
                    ? widget.crossChapterSnapshotBuilder?.call(1)
                    : null))
            : widget.pageBuilder(idx + 1);

    return ReaderPageSpread(
      left: underlayLeft,
      right: underlayRight,
      surfaceColor: widget.surfaceColor,
      paperEdgeColor: widget.paperEdgeColor,
      bookmarked: widget.bookmarked,
      progress: (idx / last).clamp(0.0, 1.0),
      curlOverlay: curlLayer,
    );
  }

  /// 置于底层全不透明绘制，且与 ReaderPageSpread 共享 6px 圆角防止露角。
  Widget _buildSingleBackCaptureSlot(double leafWidth, double height) {
    final child = _pendingBackCaptureWidget;
    if (child == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      top: 0,
      width: leafWidth,
      height: height,
      child: ExcludeFocus(
        child: IgnorePointer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: RepaintBoundary(
              key: _singleBackCaptureKey,
              child: ColoredBox(color: widget.surfaceColor, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
