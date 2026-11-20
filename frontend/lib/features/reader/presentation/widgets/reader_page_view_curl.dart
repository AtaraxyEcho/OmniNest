part of 'reader_page_view.dart';

/// 双向卷页单槽空闲预抓图与装配：
/// 1. 正面直接从当前可见页面的 RepaintBoundary 抓取，零额外子树、零选区冲突。
/// 2. 背面仅在需要时挂载单个 ExcludeFocus + selectionDisabled 隔离槽，抓完立刻卸载。
/// 3. 翻页落定 120ms 后自动预热正向翻页快照，正向翻页与边角悬停微翘 0ms 起手。
extension _ReaderPageViewCurl on _ReaderPageViewState {
  void _scheduleIdleNextCurlWarmup() {
    _curlWarmupTimer?.cancel();
    if (widget.turnMode != PageTurnMode.cover) return;
    _curlWarmupTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _curlFrameNotifier.value.active) return;
      unawaited(_ensureCurlPairReady(CurlDirection.next));
    });
  }

  bool _hasReadyCurlPair(CurlDirection dir) {
    return _cachedCurlDir == dir &&
        _cachedCurlPageIndex == widget.state.pageIndex &&
        _cachedCurlChapterId == widget.state.chapterId &&
        _curlFront != null &&
        _curlBack != null;
  }

  void _prepareCurlCapture() {
    if (widget.turnMode != PageTurnMode.cover) return;
    final dir = _isForward ? CurlDirection.next : CurlDirection.prev;
    if (_hasReadyCurlPair(dir) || _curlCapturing) return;
    unawaited(_ensureCurlPairReady(dir));
  }

  Future<bool> _ensureCurlPairReady(CurlDirection dir) async {
    if (widget.turnMode != PageTurnMode.cover || !mounted) return false;
    if (_hasReadyCurlPair(dir)) return true;

    _curlCapturing = true;
    final token = ++_curlToken;
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.5);

    final liveKey =
        widget.spread
            ? (dir == CurlDirection.next ? _liveRightKey : _liveLeftKey)
            : _liveSingleKey;
    final frontImg = await _captureBoundarySafe(liveKey, dpr);
    if (!mounted || token != _curlToken || frontImg == null) {
      frontImg?.dispose();
      if (mounted && token == _curlToken) {
        _curlCapturing = false;
      }
      return false;
    }

    final backWidget = _resolveCurlBackWidget(dir);
    if (backWidget == null) {
      frontImg.dispose();
      if (mounted && token == _curlToken) {
        _curlCapturing = false;
      }
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
      if (mounted && token == _curlToken) {
        _curlCapturing = false;
      }
      return false;
    }

    _replaceCurlCache(
      dir: dir,
      chapterId: widget.state.chapterId,
      pageIndex: widget.state.pageIndex,
      front: frontImg,
      back: backImg,
    );
    return true;
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
      // Web 端跨域无 CORS 图片导致 Canvas tainted 时安全返回 null，由上层退回平滑翻页。
      return null;
    }
  }

  void _replaceCurlCache({
    required CurlDirection dir,
    required String chapterId,
    required int pageIndex,
    required ui.Image front,
    required ui.Image back,
  }) {
    final oldFront = _curlFront;
    final oldBack = _curlBack;
    _curlFront = front;
    _curlBack = back;
    _cachedCurlDir = dir;
    _cachedCurlChapterId = chapterId;
    _cachedCurlPageIndex = pageIndex;
    _curlCapturing = false;
    if (mounted) {
      _updateState(() {});
    }
    if (oldFront != null || oldBack != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldFront?.dispose();
        oldBack?.dispose();
      });
    }
  }

  void _clearCurlImages() {
    _curlWarmupTimer?.cancel();
    final front = _curlFront;
    final back = _curlBack;
    _curlFront = null;
    _curlBack = null;
    _cachedCurlDir = null;
    _cachedCurlPageIndex = null;
    _cachedCurlChapterId = null;
    _curlCapturing = false;
    _pendingBackCaptureWidget = null;
    _curlToken++;
    if (front == null && back == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      front?.dispose();
      back?.dispose();
    });
  }

  void _disposeCurlImages() {
    _curlWarmupTimer?.cancel();
    _curlToken++;
    _curlCapturing = false;
    _pendingBackCaptureWidget = null;
    _curlFront?.dispose();
    _curlBack?.dispose();
    _curlFront = null;
    _curlBack = null;
  }

  /// 构建卷页态整幅画面（覆盖整个双页或单页画框）；快照未就绪或跨域降级时返回 null。
  Widget? _buildCurlTurn(double width, double height) {
    final frame = _curlFrameNotifier.value;
    if (!frame.active) return null;
    if (!_hasReadyCurlPair(frame.direction)) return null;
    final front = _curlFront;
    final back = _curlBack;
    if (front == null || back == null) return null;

    final curlLayer = ReaderPageCurl(
      frameListenable: _curlFrameNotifier,
      front: front,
      back: back,
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
    // 对齐 ReaderView.tsx:390-391；底层 underlay 严禁传 leftBoundaryKey/rightBoundaryKey。
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
