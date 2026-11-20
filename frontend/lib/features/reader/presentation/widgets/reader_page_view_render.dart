part of 'reader_page_view.dart';

/// 页面占位、静止态 RepaintBoundary 挂载与 0-Rebuild 卷页渲染。
extension _ReaderPageViewRender on _ReaderPageViewState {
  Widget _buildPageOrEmpty(int index) {
    final page = widget.pageBuilder(index);
    if (page == null) {
      return SizedBox.expand(child: ColoredBox(color: widget.surfaceColor));
    }
    return SizedBox.expand(
      child: ColoredBox(color: widget.surfaceColor, child: page),
    );
  }

  Widget _buildRestingPage() {
    final idx = widget.state.pageIndex;
    if (widget.spread) {
      final left = widget.pageBuilder(idx) ?? const SizedBox.expand();
      final last = widget.state.pageCount <= 1 ? 1 : widget.state.pageCount - 1;
      return ReaderPageSpread(
        left: left,
        right: widget.pageBuilder(idx + 1),
        surfaceColor: widget.surfaceColor,
        paperEdgeColor: widget.paperEdgeColor,
        leftBoundaryKey: _liveLeftKey,
        rightBoundaryKey: _liveRightKey,
        progress: (idx / last).clamp(0.0, 1.0),
      );
    }
    final current = _currentPageWidget ?? pageAt(idx);
    return RepaintBoundary(key: _liveSingleKey, child: _constrainPage(current));
  }

  Widget _buildAnimationContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
        final height =
            constraints.hasBoundedHeight
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height;
        final leafWidth = widget.spread ? width / 2.0 : width;

        final frame = _curlFrameNotifier.value;
        final isCurlActive =
            widget.turnMode == PageTurnMode.cover && frame.active;

        Widget mainContent;
        if (!isCurlActive && _flipProgress <= 0 && !_isAnimating) {
          mainContent = _buildRestingPage();
        } else if (isCurlActive && _hasReadyCurlPair(frame.direction)) {
          // 卷页激活期间由 CustomPainter(repaint: _curlFrameNotifier) 独立重绘，
          // 无需在每帧触发外层 AnimatedBuilder 重建整棵子树。
          mainContent = _buildCurlTurn(width, height) ?? _buildRestingPage();
        } else {
          final current = _currentPageWidget ?? pageAt(widget.state.pageIndex);
          final target = _targetPageWidget;
          if (target == null) {
            mainContent = _buildRestingPage();
          } else {
            mainContent = AnimatedBuilder(
              animation: Listenable.merge([
                _animController!,
                _flipProgressNotifier,
              ]),
              builder: (context, _) {
                final t = _isAnimating ? _animController!.value : _flipProgress;
                return switch (widget.turnMode) {
                  PageTurnMode.cover => _buildCover(current, target, t, width),
                  PageTurnMode.fade => _buildFade(current, target, t),
                  PageTurnMode.slide => const SizedBox.shrink(),
                };
              },
            );
          }
        }

        if (_pendingBackCaptureWidget == null) {
          return mainContent;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            mainContent,
            _buildSingleBackCaptureSlot(leafWidth, height),
          ],
        );
      },
    );
  }

  Widget _constrainPage(Widget? page) {
    return SizedBox.expand(
      child: ColoredBox(color: widget.surfaceColor, child: page),
    );
  }

  Widget _buildCover(Widget? current, Widget? target, double t, double width) {
    final targetOffset = _isForward ? (1 - t) * width : (t - 1) * width;

    return Stack(
      children: [
        _constrainPage(current),
        Transform.translate(
          offset: Offset(targetOffset, 0),
          child: _constrainPage(target),
        ),
      ],
    );
  }

  Widget _buildFade(Widget? current, Widget? target, double t) {
    return Stack(
      children: [
        Opacity(opacity: 1 - t, child: _constrainPage(current)),
        Opacity(opacity: t, child: _constrainPage(target)),
      ],
    );
  }
}
