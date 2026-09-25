part of 'reader_page_view.dart';

/// 页面占位与翻页动画内容渲染。
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

  Widget _buildAnimationContent() {
    final current =
        _currentPageWidget ?? widget.pageBuilder(widget.state.pageIndex);

    if (_flipProgress <= 0 && !_isAnimating) {
      return _constrainPage(current);
    }

    final target = _targetPageWidget;
    if (target == null) {
      return _constrainPage(current);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
        return SizedBox.expand(
          child: AnimatedBuilder(
            animation: _animController!,
            builder: (context, _) {
              final t = _animController!.value;
              return switch (widget.turnMode) {
                PageTurnMode.cover => _buildCover(current, target, t, width),
                PageTurnMode.fade => _buildFade(current, target, t),
                PageTurnMode.slide => const SizedBox.shrink(),
              };
            },
          ),
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
