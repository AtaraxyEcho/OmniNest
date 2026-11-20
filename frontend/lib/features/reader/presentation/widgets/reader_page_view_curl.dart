part of 'reader_page_view.dart';

/// 双向卷页双槽空闲预抓图与装配（v3：同时预热 next + prev，正反翻页 0ms 起手）。
extension _ReaderPageViewCurl on _ReaderPageViewState {
  void _scheduleIdleNextCurlWarmup() {
    _curlWarmupTimer?.cancel();
    if (widget.turnMode != PageTurnMode.cover) return;
    _curlWarmupTimer = Timer(const Duration(milliseconds: 80), () async {
      if (!mounted || _curlFrameNotifier.value.active) return;
      await _ensureCurlPairReady(CurlDirection.next);
      if (!mounted || _curlFrameNotifier.value.active) return;
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
    if (_capturingDirs.contains(dir)) {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (!mounted) return false;
        if (_hasReadyCurlPair(dir)) return true;
        if (!_capturingDirs.contains(dir)) break;
      }
      return _hasReadyCurlPair(dir);
    }

    _capturingDirs.add(dir);
    final token = _curlToken;
    try {
      final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.5);
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

      final frameDone = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) => frameDone.complete());
      await frameDone.future;
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
      return true;
    } finally {
      _capturingDirs.remove(dir);
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

  Future<ui.Image?> _captureBoundarySafe(GlobalKey key, double ratio) async {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    try {
      return await boundary.toImage(pixelRatio: ratio);
    } on Object {
      return null;
    }
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
      return Stack(
        fit: StackFit.expand,
        children: [
          _constrainPage(revealed),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: curlLayer,
            ),
          ),
        ],
      );
    }

    final idx = widget.state.pageIndex;
    final last = widget.state.pageCount <= 1 ? 1 : widget.state.pageCount - 1;
    final isNext = frame.direction == CurlDirection.next;
    final underlayLeft =
        (isNext
            ? widget.pageBuilder(idx)
            : (idx - 2 >= 0 ? widget.pageBuilder(idx - 2) : null)) ??
        const SizedBox.expand();
    final underlayRight =
        isNext ? widget.pageBuilder(idx + 3) : widget.pageBuilder(idx + 1);

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
          child: Opacity(
            opacity: 0.001,
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
