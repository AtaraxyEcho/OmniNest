part of 'reader_page_view.dart';

/// 页面占位、静止态 RepaintBoundary 挂载与 0-Rebuild 卷页渲染（v4 终审定稿）。
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
        bookmarked: widget.bookmarked,
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
        if (widget.turnMode == PageTurnMode.cover) {
          // Book 仿真模式严禁回退 2D _buildCover 左右平推：
          // 卷页激活且快照就绪时渲染真 3D 卷页层，其余时刻稳定保持静止书页。
          if (isCurlActive && _hasReadyCurlPair(frame.direction)) {
            mainContent = _buildCurlTurn(width, height) ?? _buildRestingPage();
          } else {
            mainContent = _buildRestingPage();
          }
        } else if (!_isAnimating && _flipProgress <= 0) {
          mainContent = _buildRestingPage();
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
                  PageTurnMode.fade => _buildFade(current, target, t),
                  PageTurnMode.cover ||
                  PageTurnMode.slide => const SizedBox.shrink(),
                };
              },
            );
          }
        }

        // 关键修复：永久保持 Stack([底层抓图槽, 顶层 mainContent]) 结构不变，
        // 绝不因 _pendingBackCaptureWidget 变化而销毁重建整棵书页子树。
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            _buildSingleBackCaptureSlot(leafWidth, height),
            Positioned.fill(child: mainContent),
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

  Widget _buildFade(Widget? current, Widget? target, double t) {
    return Stack(
      children: [
        Opacity(opacity: 1 - t, child: _constrainPage(current)),
        Opacity(opacity: t, child: _constrainPage(target)),
      ],
    );
  }
}
