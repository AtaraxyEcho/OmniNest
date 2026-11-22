part of 'reader_page_view.dart';

/// Slide 模式 PageView、点击热区与探测页（支持 RTL、鼠标拖拽开关、全表面拖拽与缩放态拖拽锁）。
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

    final edgeColor =
        ThemeData.estimateBrightnessForColor(widget.surfaceColor) ==
                Brightness.dark
            ? Colors.white.withValues(alpha: 0.40)
            : Colors.black.withValues(alpha: 0.40);
    final dragDevices =
        widget.allowMouseDrag
            ? const {
              PointerDeviceKind.touch,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
              PointerDeviceKind.mouse,
            }
            : const {
              PointerDeviceKind.touch,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            };
    return MouseRegion(
      onEnter: (_) => _updateState(() => _slideStageHovered = true),
      onExit: (_) => _updateState(() => _slideStageHovered = false),
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onSlideScrollNotification,
            child: ScrollConfiguration(
              // 文本正文默认排除 mouse 拖拽翻页把拖动留给选字；漫画等可经由 allowMouseDrag 开启。
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(dragDevices: dragDevices),
              child: PageView.builder(
                controller: _pageController,
                reverse: widget.reverse,
                itemCount: effectiveCount,
                physics:
                    (!widget.dragEnabled ||
                            ReaderInteractionGate.locksScroll(_blockReason))
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                onPageChanged: _onSlidePageChanged,
                itemBuilder: (context, index) => _buildPageOrEmpty(index),
              ),
            ),
          ),
          // 样例 `.sw-stage .edge`：鼠标悬停时左右 56px 淡入边缘翻页提示箭头。
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 56,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _slideStageHovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Center(
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 24,
                    color: edgeColor,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 56,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _slideStageHovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Center(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 24,
                    color: edgeColor,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              onPointerSignal: _onPointerSignal,
            ),
          ),
        ],
      ),
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
    _velocityTracker = null;
    if (!_primaryPointerDown) return;
    _pointerKind = event.kind;
    _pointerDownPosition = event.localPosition;
    _pointerMoved = false;
    final tracker = VelocityTracker.withKind(event.kind);
    // 起始点也入队：样本数不足两点时 VelocityTracker 只能给出零速度，
    // 短促甩动往往只有一个 move 事件。
    tracker.addPosition(event.timeStamp, event.localPosition);
    _velocityTracker = tracker;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerDownPosition == null) return;
    _velocityTracker?.addPosition(event.timeStamp, event.localPosition);
    final delta = event.localPosition - _pointerDownPosition!;
    if (delta.distance > _ReaderPageViewState._tapMoveThreshold) {
      _pointerMoved = true;
    }
    if (!widget.dragEnabled) return;
    // 放宽斜向掀角判定（支持从右下角往左上角 65° 以内自然拖拽掀页，不再偶发失效）
    if (widget.turnMode != PageTurnMode.slide &&
        !widget.selectionActive &&
        delta.dx.abs() > 4.0 &&
        delta.dx.abs() > delta.dy.abs() * 0.45) {
      // Book 模式的拖拽从页边开始，正文中段仍然留给文字选择；
      // 当 fullSurfaceDrag 开启（漫画等无选字场景）时解除边缘限制，允许中段自然拖拽掀页。
      final width = context.size?.width ?? 1;
      final startX = _pointerDownPosition!.dx;
      final edgeRatio = _pointerKind == PointerDeviceKind.mouse ? 0.22 : 0.30;
      final edgeStart =
          widget.fullSurfaceDrag ||
          width <= 1 ||
          startX < width * edgeRatio ||
          startX > width * (1.0 - edgeRatio);
      if (!edgeStart) return;
      if (!_isDragging) {
        _onDragStart(DragStartDetails(localPosition: _pointerDownPosition!));
      }
      // 关键修复：传入 primaryDelta 时 delta 另一轴必须严格为 0.0，
      // 彻底根除 DragUpdateDetails 断言异常吞帧导致的拖不动与翻页卡死！
      _onDragUpdate(
        DragUpdateDetails(
          delta: Offset(event.delta.dx, 0),
          primaryDelta: event.delta.dx,
          globalPosition: event.position,
          localPosition: event.localPosition,
        ),
      );
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final velocity = _velocityTracker?.getVelocity() ?? Velocity.zero;
    _velocityTracker = null;
    if (!_primaryPointerDown || _pointerDownPosition == null) return;
    _primaryPointerDown = false;
    final startPos = _pointerDownPosition!;
    _pointerDownPosition = null;
    _pointerKind = null;

    if (_isDragging) {
      // 翻页只关心水平分量；DragEndDetails 断言 primaryVelocity 与 velocity
      // 的某一轴相等且另一轴为零，斜向甩动的 dy 必须归零后再传入。
      final flingVelocity = Velocity(
        pixelsPerSecond: Offset(velocity.pixelsPerSecond.dx, 0),
      );
      _onDragEnd(
        DragEndDetails(
          velocity: flingVelocity,
          primaryVelocity: flingVelocity.pixelsPerSecond.dx,
        ),
      );
      return;
    }

    // 拖动过长则不算点击，交给 PageView 处理
    if (_pointerMoved) {
      if (!widget.dragEnabled) return;
      final deltaX = event.localPosition.dx - startPos.dx;
      if (deltaX.abs() >= 48) {
        final swipeForward = widget.reverse ? deltaX > 0 : deltaX < 0;
        if (swipeForward &&
            widget.state.isLastPage &&
            !widget.state.hasMore &&
            widget.state.hasNextChapter) {
          _pendingSlideBoundaryDirection = 1;
        } else if (!swipeForward &&
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

    final w = context.size?.width ?? 1;
    final x = startPos.dx;
    final leftBound = w * _ReaderPageViewState._leftZoneRatio;
    final rightBound = w * (1 - _ReaderPageViewState._rightZoneRatio);

    if (widget.selectionActive) {
      widget.onClearSelection?.call();
      if (x >= leftBound && x <= rightBound) return;
    }

    // 点击翻页固定采用优雅下角斜卷预设 CurlGrabConfig.defaultNext（slant: -0.26），
    // 不再传 tapFy，杜绝点击页面中部出现僵硬竖直折痕；RTL 自动翻转左右热区。
    if (x < leftBound) {
      _debugPageTurn('leftTapReceived');
      if (widget.reverse) {
        _goNextPage(tapTurn: true);
      } else {
        _goPreviousPage(tapTurn: true);
      }
    } else if (x > rightBound) {
      _debugPageTurn('rightTapReceived');
      if (widget.reverse) {
        _goPreviousPage(tapTurn: true);
      } else {
        _goNextPage(tapTurn: true);
      }
    } else {
      widget.callbacks.onToggleControls();
    }
  }

  /// 指针被系统取消：手势被抢占、窗口失焦或触摸中断。
  ///
  /// 取消不会再补发 PointerUpEvent，必须在此复位指针状态；拖动中的半开
  /// 翻页要平滑收回，否则页面停在中间且 [_isDragging] 残留会吞掉后续手势。
  void _onPointerCancel(PointerCancelEvent event) {
    _velocityTracker = null;
    _primaryPointerDown = false;
    _pointerDownPosition = null;
    _pointerMoved = false;
    _pointerKind = null;
    if (!_isDragging) return;
    _isDragging = false;
    if (_animController == null) {
      _flipProgress = 0;
      if (mounted) {
        _updateState(() {});
      }
      return;
    }
    _cancelFlip();
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
