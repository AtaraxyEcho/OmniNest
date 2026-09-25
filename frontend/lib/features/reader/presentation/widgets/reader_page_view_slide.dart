part of 'reader_page_view.dart';

/// Slide 模式 PageView、点击热区与探测页。
extension _ReaderPageViewSlide on _ReaderPageViewState {
  // ══════════════════════════════════════════
  // Slide 模式：PageView + 交互层
  // ══════════════════════════════════════════

  Widget _buildSlideMode() {
    final state = widget.state;
    final effectiveCount =
        _localPageCount > 0
            ? (state.hasMore ? _localPageCount + 1 : _localPageCount)
            : 1;

    return Stack(
      children: [
        // 底层：PageView 处理横向拖动翻页
        NotificationListener<ScrollNotification>(
          onNotification: _onSlideScrollNotification,
          child: PageView.builder(
            controller: _pageController,
            itemCount: effectiveCount,
            physics:
                ReaderInteractionGate.locksScroll(_blockReason)
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
            onPageChanged: _onSlidePageChanged,
            itemBuilder: (context, index) => _buildPageOrEmpty(index),
          ),
        ),
        // 顶层：透明交互层处理点击热区
        // 用 Listener 而非 GestureDetector，避免与 PageView 的拖动手势竞争
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
          ),
        ),
      ],
    );
  }

  bool _onSlideScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _slideScrolling = true;
      _transitionInFlight = true;
    } else if (notification is ScrollEndNotification) {
      _slideScrolling = false;
      final boundaryDirection = _pendingSlideBoundaryDirection;
      _pendingSlideBoundaryDirection = 0;
      if (!_boundaryRequestInFlight && !_probingNext) {
        _transitionInFlight = false;
      }
      if (boundaryDirection != 0) {
        scheduleMicrotask(() => _dispatchSlideBoundary(boundaryDirection));
      }
    }
    return false;
  }

  void _onSlidePageChanged(int index) {
    _transitionInFlight = true;

    if (index >= _localPageCount && widget.state.hasMore) {
      _debugPageTurn('probePageReached', detail: 'index=$index');
      _handleProbePage(index);
      return;
    }

    // 页索引提交不因闸门阻塞（实机实证）：物理页变化必须让父级知情，
    // 否则 state 与物理页脱节后 animateToPage 空转（右击失效根因）。
    // 加载期的进度写入由 _commitPageIndex 内部守卫负责。
    _debugPageTurn('pageCommitted', detail: 'index=$index');
    widget.callbacks.onPageChanged(index);
    // 翻页可能由 jumpToPage 触发（无 ScrollEnd 复位机会），统一补一次解锁。
    _scheduleTransitionRelease();
  }
  // ── 交互层：点击热区 ──

  void _onPointerDown(PointerDownEvent event) {
    _primaryPointerDown = event.buttons == kPrimaryButton;
    if (!_primaryPointerDown) return;
    _pointerKind = event.kind;
    _pointerDownPosition = event.localPosition;
    _pointerMoved = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerDownPosition == null) return;
    final delta = event.localPosition - _pointerDownPosition!;
    if (delta.distance > _ReaderPageViewState._tapMoveThreshold) {
      _pointerMoved = true;
    }
    if (widget.turnMode != PageTurnMode.slide &&
        _pointerKind == PointerDeviceKind.touch &&
        !widget.selectionActive &&
        delta.dx.abs() > _ReaderPageViewState._tapMoveThreshold &&
        delta.dx.abs() > delta.dy.abs()) {
      if (!_isDragging) {
        _onDragStart(DragStartDetails(localPosition: event.localPosition));
      }
      _onDragUpdate(
        DragUpdateDetails(
          delta: event.delta,
          primaryDelta: event.delta.dx,
          globalPosition: event.position,
          localPosition: event.localPosition,
        ),
      );
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_primaryPointerDown || _pointerDownPosition == null) return;
    _primaryPointerDown = false;
    final startPos = _pointerDownPosition!;
    _pointerDownPosition = null;
    _pointerKind = null;

    if (_isDragging) {
      _onDragEnd(DragEndDetails(velocity: Velocity.zero));
      return;
    }

    // 拖动过长则不算点击，交给 PageView 处理
    if (_pointerMoved) {
      final deltaX = event.localPosition.dx - startPos.dx;
      if (deltaX.abs() >= 48) {
        if (deltaX < 0 &&
            widget.state.isLastPage &&
            !widget.state.hasMore &&
            widget.state.hasNextChapter) {
          _pendingSlideBoundaryDirection = 1;
        } else if (deltaX > 0 &&
            widget.state.isFirstPage &&
            widget.state.hasPreviousChapter) {
          _pendingSlideBoundaryDirection = -1;
        }
        if (_pendingSlideBoundaryDirection != 0 && !_slideScrolling) {
          final direction = _pendingSlideBoundaryDirection;
          _pendingSlideBoundaryDirection = 0;
          scheduleMicrotask(() => _dispatchSlideBoundary(direction));
        }
      }
      return;
    }

    if (widget.selectionActive) return;

    final w = context.size?.width ?? 1;
    final x = startPos.dx;
    final leftBound = w * _ReaderPageViewState._leftZoneRatio;
    final rightBound = w * (1 - _ReaderPageViewState._rightZoneRatio);

    if (x < leftBound) {
      _debugPageTurn('leftTapReceived');
      _goPreviousPage(tapTurn: true);
    } else if (x > rightBound) {
      _debugPageTurn('rightTapReceived');
      _goNextPage(tapTurn: true);
    } else {
      widget.callbacks.onToggleControls();
    }
  }

  void _dispatchSlideBoundary(int direction) {
    if (!mounted || _boundaryRequestInFlight) {
      return;
    }
    if (direction > 0) {
      _dispatchBoundaryRequest(
        widget.callbacks.onNextChapter,
        hasNeighbor: widget.state.hasNextChapter,
      );
    } else {
      _dispatchBoundaryRequest(
        widget.callbacks.onPreviousChapter,
        hasNeighbor: widget.state.hasPreviousChapter,
      );
    }
  }

  // ── 探测页 ──

  void _handleProbePage(int probeIndex) {
    if (_probingNext) return;
    _probingNext = true;

    final probeContent = widget.pageBuilder(probeIndex);
    // pageBuilder 返回 null 表示页面不存在
    final hasContent = probeContent != null;

    if (hasContent && mounted) {
      _updateState(() {
        _localPageCount = probeIndex + 1;
        _probingNext = false;
      });
      widget.callbacks.onPageChanged(probeIndex);
      // 探测页由 jumpToPage 到达时没有 ScrollEnd 复位输入锁，补一次解锁。
      _scheduleTransitionRelease();
    } else {
      _probingNext = false;
      // 探测页无内容：物理页不得停留在未确认页上。弹回最后确认页，
      // 避免扩窗后物理位置与状态页索引脱节，后续翻页 animateToPage
      // 空转造成边界处点击无响应（failure cleanup，方案 §33/§41）。
      final ctrl = _pageController;
      final lastConfirmed = _localPageCount - 1;
      if (ctrl != null &&
          ctrl.hasClients &&
          lastConfirmed >= 0 &&
          (ctrl.page ?? probeIndex).round() == probeIndex) {
        _debugPageTurn(
          'probePageSnapBack',
          detail: 'from=$probeIndex to=$lastConfirmed',
        );
        ctrl.jumpToPage(lastConfirmed);
      }
      _dispatchBoundaryRequest(
        widget.callbacks.onNextChapter,
        hasNeighbor: widget.state.hasNextChapter,
      );
    }
  }
}
