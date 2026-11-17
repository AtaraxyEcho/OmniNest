part of 'reader_page_view.dart';

/// 卷页的取图与拼装：翻页开始时把「翻起的那一页」和它的背面各抓成一张
/// 位图，之后 28 片圆柱条带只做贴图，不再重建整页子树。
extension _ReaderPageViewCurl on _ReaderPageViewState {
  /// 翻起的那一页（正面）。
  Widget? get _curlFrontPage =>
      widget.spread
          ? widget.pageBuilder(widget.state.pageIndex + 1)
          : pageAt(widget.state.pageIndex);

  /// 卷起后露出的那一面（背面）。
  Widget? get _curlBackPage =>
      widget.spread
          ? widget.pageBuilder(widget.state.pageIndex + 2)
          : pageAt(widget.state.pageIndex + pageStep);

  void _prepareCurlCapture() {
    if (widget.turnMode != PageTurnMode.cover || !_isForward) {
      return;
    }
    if (_curlCapturing || (_curlFront != null && _curlBack != null)) {
      return;
    }
    _curlCapturing = true;
    _curlToken++;
    if (mounted) {
      _updateState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_captureCurlImages());
      }
    });
  }

  Future<void> _captureCurlImages() async {
    if (!mounted || !_curlCapturing) {
      return;
    }
    final token = _curlToken;
    final front = await _captureBoundary(_curlFrontKey);
    final back = await _captureBoundary(_curlBackKey);
    if (!mounted || token != _curlToken) {
      front?.dispose();
      back?.dispose();
      return;
    }
    if (front == null || back == null) {
      front?.dispose();
      back?.dispose();
      _updateState(() => _curlCapturing = false);
      return;
    }
    _updateState(() {
      _curlFront?.dispose();
      _curlBack?.dispose();
      _curlFront = front;
      _curlBack = back;
      _curlCapturing = false;
    });
  }

  Future<ui.Image?> _captureBoundary(GlobalKey key) async {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      return null;
    }
    final ratio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
    try {
      return await boundary.toImage(pixelRatio: ratio);
    } on Object {
      return null;
    }
  }

  /// 翻页提交后清引用：当前帧的画笔可能还持有图片，释放推迟到帧末。
  void _clearCurlImages() {
    final front = _curlFront;
    final back = _curlBack;
    _curlFront = null;
    _curlBack = null;
    _curlCapturing = false;
    _curlToken++;
    if (front == null && back == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      front?.dispose();
      back?.dispose();
    });
  }

  void _disposeCurlImages() {
    _curlToken++;
    _curlCapturing = false;
    _curlFront?.dispose();
    _curlBack?.dispose();
    _curlFront = null;
    _curlBack = null;
  }

  /// 翻页进程里的卷页层；快照未就绪时返回 null，调用方退回 cover。
  Widget? _buildCurlTurn(double t, double width, double height) {
    final front = _curlFront;
    final back = _curlBack;
    if (front == null || back == null || t <= 0) {
      return null;
    }
    final sheet = ReaderPageCurl(
      front: front,
      back: back,
      progress: t,
      paper: widget.surfaceColor,
    );
    if (!widget.spread) {
      final revealed = pageAt(widget.state.pageIndex + pageStep);
      return Stack(
        children: [
          _constrainPage(revealed),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: sheet,
            ),
          ),
        ],
      );
    }
    // 跨页：左页不动，右页换成下一跨页的右页；卷起的是当前右页。
    final half = math.max(0.0, (width - _spreadGutterWidth) / 2);
    final underlay = ReaderPageSpread(
      left:
          widget.pageBuilder(widget.state.pageIndex) ?? const SizedBox.expand(),
      right: widget.pageBuilder(widget.state.pageIndex + 3),
      surfaceColor: widget.surfaceColor,
      progress:
          widget.state.pageCount <= 1
              ? 0
              : (widget.state.pageIndex / (widget.state.pageCount - 1)).clamp(
                0.0,
                1.0,
              ),
    );
    return Stack(
      children: [
        Positioned.fill(child: underlay),
        Positioned(
          left: half + _spreadGutterWidth,
          top: 0,
          width: half,
          height: height,
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(6),
            ),
            child: sheet,
          ),
        ),
      ],
    );
  }

  /// 抓图期间挂两块不可见的页面副本：必须真的绘制过才能 `toImage`，
  /// 放在 1% 不透明度里既参与绘制又不会被看到。
  List<Widget> _curlCaptureSources(double sheetWidth, double height) {
    final front = _curlFrontPage;
    final back = _curlBackPage;
    return [
      if (front != null)
        Positioned(
          left: 0,
          top: 0,
          width: sheetWidth,
          height: height,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.01,
              child: RepaintBoundary(
                key: _curlFrontKey,
                child: _constrainPage(front),
              ),
            ),
          ),
        ),
      if (back != null)
        Positioned(
          left: 0,
          top: 0,
          width: sheetWidth,
          height: height,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.01,
              child: RepaintBoundary(
                key: _curlBackKey,
                child: _constrainPage(back),
              ),
            ),
          ),
        ),
    ];
  }
}
