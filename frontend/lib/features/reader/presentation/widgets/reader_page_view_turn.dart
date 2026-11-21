part of 'reader_page_view.dart';

/// 翻页命令、输入闸门与待执行翻页意图（v8：平滑连点加速收尾排队 + 清零 _pendingTurnAttachRetry）。
extension _ReaderPageViewTurn on _ReaderPageViewState {
  /// 桌面滚轮翻页（样例 `onWheel`）：位移超过 24px、距上次 320ms 才认，
  /// 触控板一次轻扫不会连翻好几页。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    if (!widget.dragEnabled) {
      return;
    }
    if (event.scrollDelta.dy.abs() < 24) {
      return;
    }
    final now = DateTime.now();
    final last = _lastWheelAt;
    if (last != null &&
        now.difference(last) < _ReaderPageViewState._wheelThrottle) {
      return;
    }
    _lastWheelAt = now;
    if (widget.selectionActive) widget.onClearSelection?.call();
    if (event.scrollDelta.dy > 0) {
      _goNextPage(tapTurn: true);
    } else {
      _goPreviousPage(tapTurn: true);
    }
  }

  void _onExternalPageCommand() {
    if (widget.selectionActive) widget.onClearSelection?.call();
    final direction = widget.controller?.direction ?? 0;
    if (direction == 0) return;

    // Book 模式连点快翻：取消 0.62 硬切断，改为加速收尾当前动画（120ms）并排队衔接下一页。
    if (widget.turnMode == PageTurnMode.cover && _isAnimating && !_isDragging) {
      _pendingTurnDirection = direction > 0 ? 1 : -1;
      _pendingTurnAttachRetry = false;
      _accelerateActiveFlip();
      return;
    }

    if (ReaderInteractionGate.blocksTapTurn(_blockReason)) return;
    if (direction > 0) {
      _goNextPage(tapTurn: true);
    } else {
      _goPreviousPage(tapTurn: true);
    }
  }

  /// 统一复位翻页状态机（模式切换/初始化/重置时清零所有残留标记含 `_pendingTurnAttachRetry`）。
  void resetTurnState() {
    _isAnimating = false;
    _pendingTurnDirection = null;
    _pendingTurnAttachRetry = false;
    _pendingTurnFrames = 0;
    _probingNext = false;
    _slideScrolling = false;
    _transitionInFlight = false;
    _boundaryRequestInFlight = false;
    _pendingSlideBoundaryDirection = 0;
  }

  void _initForMode() {
    // 控制器重建后旧翻页意图的目标已失效，显式丢弃；在途动画的
    // status listener 随旧控制器销毁不再回调，动画标志必须一并复位，
    // 否则 pageAnimationActive 恒真锁死翻页闸门。
    resetTurnState();
    _localPageCount = widget.state.pageCount;
    if (widget.turnMode == PageTurnMode.slide) {
      _pageController = PageController(initialPage: widget.state.pageIndex);
    } else {
      _animController = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _ReaderPageViewState._flipDurationMs),
      );
    }
    _cacheCurrentPage();
  }

  void _disposeControllers() {
    _pageController?.dispose();
    _pageController = null;
    _animController?.removeStatusListener(_onAutoFlipStatus);
    _animController?.dispose();
    _animController = null;
  }

  void _syncPageView() {
    final ctrl = _pageController;
    if (ctrl == null || !ctrl.hasClients) return;
    final target = widget.state.pageIndex;
    if ((ctrl.page ?? target).round() == target) {
      return;
    }
    // LayoutBuilder 重建期间 didUpdateWidget 可能发生在 layout 回调内；
    // 同步 jumpToPage 会立刻派发 ScrollNotification / onPageChanged，
    // 上游若在回调里 setState 会触发 build 期标记脏树。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _pageController;
      if (controller == null || !controller.hasClients) return;
      if ((controller.page ?? target).round() != target) {
        controller.jumpToPage(target);
      }
    });
  }

  /// 空闲期把物理页对齐到状态页。
  void _reconcilePagePositionIfIdle() {
    if (widget.turnMode != PageTurnMode.slide) {
      return;
    }
    if (_slideScrolling || _probingNext) {
      return;
    }
    if (_blockReason != ReaderInteractionBlockReason.none) {
      return;
    }
    _syncPageView();
  }

  void _cacheCurrentPage() {
    _currentPageWidget = pageAt(widget.state.pageIndex);
  }
  // ══════════════════════════════════════════
  // 统一翻页命令
  // ══════════════════════════════════════════

  /// 当前输入闸门原因：加载 > 边界 > 动画 > 过渡 > 放行。
  ReaderInteractionBlockReason get _blockReason =>
      ReaderInteractionGate.resolve(
        isPaginating: widget.state.isPaginating,
        boundaryRequestInFlight: _boundaryRequestInFlight,
        pageAnimationActive: _isAnimating,
        pageTransitionInFlight: _transitionInFlight,
      );

  /// 翻页链路诊断快照（D0 观测）。
  String get _pageTurnDebugState =>
      'chapter=${widget.state.chapterId} '
      'pageIndex=${widget.state.pageIndex} '
      'pageCount=${widget.state.pageCount} localPageCount=$_localPageCount '
      'probingNext=$_probingNext hasMore=${widget.state.hasMore} '
      'isPaginating=${widget.state.isPaginating} '
      'slideScrolling=$_slideScrolling animating=$_isAnimating '
      'transition=$_transitionInFlight boundary=$_boundaryRequestInFlight '
      'gate=${_blockReason.name}';

  void _debugPageTurn(String event, {String? detail}) {
    readerDebugLog(
      'ReaderPageTurn: $event'
      '${detail == null ? '' : ' [$detail]'} | $_pageTurnDebugState',
    );
  }

  /// 统一：下一页。
  void _goNextPage({bool tapTurn = false}) {
    // Book 模式点击连翻：若正在播卷页动画，不吞点击，加速收尾并排队下一页。
    if (tapTurn &&
        widget.turnMode == PageTurnMode.cover &&
        _isAnimating &&
        !_isDragging &&
        !_boundaryRequestInFlight &&
        !widget.state.isPaginating) {
      _pendingTurnDirection = 1;
      _pendingTurnAttachRetry = false;
      _debugPageTurn('nextQueuedDuringCurl');
      _accelerateActiveFlip();
      return;
    }

    final reason = _blockReason;
    if (tapTurn
        ? ReaderInteractionGate.blocksTapTurn(reason)
        : ReaderInteractionGate.blocksInput(reason)) {
      _debugPageTurn(
        'nextBlocked',
        detail: 'source=${tapTurn ? 'tap' : 'command'}',
      );
      return;
    }

    // 动画进行中：不重复算目标，只保留最后一次方向意图（方案 §43-44），
    // 提交释放后执行一次，防重入但不丢用户意图。
    if (_transitionInFlight &&
        !_slideScrolling &&
        !_boundaryRequestInFlight &&
        _pageController != null) {
      _pendingTurnDirection = 1;
      _pendingTurnAttachRetry = false;
      _debugPageTurn('nextDeferredDuringAnimation');
      return;
    }

    // 目标基于控制器实际物理页：state 与物理页脱节时按物理页前进，点击不再空转。
    final ctrl = _pageController;
    final basePage =
        ctrl != null && ctrl.hasClients
            ? (ctrl.page?.round() ?? widget.state.pageIndex)
            : widget.state.pageIndex;
    final nextIndex = basePage + pageStep;
    final atBoundary = nextIndex >= _localPageCount && !widget.state.hasMore;

    if (atBoundary) {
      _debugPageTurn(
        'nextBoundaryRequest',
        detail:
            'nextIndex=$nextIndex hasNextChapter=${widget.state.hasNextChapter}',
      );
      _dispatchBoundaryRequest(
        widget.callbacks.onNextChapter,
        hasNeighbor: widget.state.hasNextChapter,
      );
      return;
    }

    if (widget.turnMode == PageTurnMode.slide) {
      if (ctrl != null && ctrl.hasClients) {
        _debugPageTurn('nextStart', detail: 'target=$nextIndex base=$basePage');
        _transitionInFlight = true;
        unawaited(_animateSlideTo(ctrl, nextIndex));
      } else {
        // 控制器尚未挂载：保留意图按帧重试（上限 4 帧），避免点击右侧/底栏无响应。
        _debugPageTurn('nextRetryScheduled', detail: 'controller not attached');
        _enqueuePendingTurn(1);
      }
    } else {
      _debugPageTurn('nextStart', detail: 'target=$nextIndex mode=flip');
      _transitionInFlight = true;
      _isForward = true;
      // 点击翻页固定采用优雅下角斜卷预设 CurlGrabConfig.defaultNext（slant: -0.26）。
      _activeCurlConfig = CurlGrabConfig.defaultNext;
      _flipProgress = widget.turnMode == PageTurnMode.cover ? 0.0 : 0.01;
      unawaited(_startAutoFlip());
    }
  }

  void _enqueuePendingTurn(int direction) {
    if (_pendingTurnDirection != null) {
      return;
    }
    _pendingTurnDirection = direction;
    _pendingTurnAttachRetry = true;
    _pendingTurnFrames = 0;
    _pumpPendingTurn();
  }

  void _pumpPendingTurn() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _pendingTurnDirection = null;
        _pendingTurnAttachRetry = false;
        _pendingTurnFrames = 0;
        return;
      }
      final direction = _pendingTurnDirection;
      if (direction == null) {
        _pendingTurnAttachRetry = false;
        return;
      }
      final ctrl = _pageController;
      if (ctrl != null && ctrl.hasClients) {
        _pendingTurnDirection = null;
        _pendingTurnAttachRetry = false;
        _pendingTurnFrames = 0;
        _debugPageTurn('pendingTurnExecute');
        if (direction > 0) {
          _goNextPage(tapTurn: true);
        } else {
          _goPreviousPage(tapTurn: true);
        }
        return;
      }
      _pendingTurnFrames++;
      if (_pendingTurnFrames > _ReaderPageViewState._maxPendingTurnFrames) {
        _pendingTurnDirection = null;
        _pendingTurnAttachRetry = false;
        _pendingTurnFrames = 0;
        _debugPageTurn(
          'pendingTurnDropped',
          detail: 'controller never attached',
        );
        return;
      }
      _pumpPendingTurn();
    });
  }

  /// 统一：上一页。
  void _goPreviousPage({bool tapTurn = false}) {
    if (tapTurn &&
        widget.turnMode == PageTurnMode.cover &&
        _isAnimating &&
        !_isDragging &&
        !_boundaryRequestInFlight &&
        !widget.state.isPaginating) {
      _pendingTurnDirection = -1;
      _pendingTurnAttachRetry = false;
      _debugPageTurn('previousQueuedDuringCurl');
      _accelerateActiveFlip();
      return;
    }

    final reason = _blockReason;
    if (tapTurn
        ? ReaderInteractionGate.blocksTapTurn(reason)
        : ReaderInteractionGate.blocksInput(reason)) {
      _debugPageTurn(
        'previousBlocked',
        detail: 'source=${tapTurn ? 'tap' : 'command'}',
      );
      return;
    }

    if (_transitionInFlight &&
        !_slideScrolling &&
        !_boundaryRequestInFlight &&
        _pageController != null) {
      _pendingTurnDirection = -1;
      _pendingTurnAttachRetry = false;
      _debugPageTurn('previousDeferredDuringAnimation');
      return;
    }

    final ctrl = _pageController;
    final basePage =
        ctrl != null && ctrl.hasClients
            ? (ctrl.page?.round() ?? widget.state.pageIndex)
            : widget.state.pageIndex;
    final atBoundary = basePage <= 0;

    if (atBoundary) {
      _debugPageTurn('previousBoundaryRequest');
      _dispatchBoundaryRequest(
        widget.callbacks.onPreviousChapter,
        hasNeighbor: widget.state.hasPreviousChapter,
      );
      return;
    }

    if (widget.turnMode == PageTurnMode.slide) {
      final prevIndex = math.max(0, basePage - pageStep);
      if (ctrl != null && ctrl.hasClients) {
        _debugPageTurn('previousStart', detail: 'target=$prevIndex');
        _transitionInFlight = true;
        unawaited(_animateSlideTo(ctrl, prevIndex));
      } else {
        _debugPageTurn(
          'previousRetryScheduled',
          detail: 'controller not attached',
        );
        _enqueuePendingTurn(-1);
      }
    } else {
      _debugPageTurn('previousStart', detail: 'mode=flip');
      _transitionInFlight = true;
      _isForward = false;
      // 点击翻页固定采用优雅下角斜卷预设 CurlGrabConfig.defaultNext（slant: -0.26）。
      _activeCurlConfig = CurlGrabConfig.defaultNext;
      _flipProgress = widget.turnMode == PageTurnMode.cover ? 0.0 : 0.01;
      unawaited(_startAutoFlip());
    }
  }

  Future<void> _animateSlideTo(PageController controller, int pageIndex) async {
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.jumpToPage(pageIndex);
      } else {
        await controller.animateToPage(
          pageIndex,
          duration: _ReaderPageViewState._slideTurnDuration,
          curve: _ReaderPageViewState._turnCurve,
        );
      }
    } finally {
      // 动画/jump 结束后必须解锁输入：父级 pageIndex 更新有帧延迟，
      // 不能只在目标页未到达时清理，否则 _transitionInFlight 会卡死翻页。
      if (mounted) {
        _scheduleTransitionRelease();
      }
    }
  }

  void _scheduleTransitionRelease() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _slideScrolling ||
          _boundaryRequestInFlight ||
          _probingNext ||
          _isAnimating) {
        return;
      }
      if (_transitionInFlight) {
        _updateState(() => _transitionInFlight = false);
      }
      // 动画期间保留的方向意图在提交释放后执行一次（方案 §44）。
      final direction = _pendingTurnDirection;
      if (direction != null && !_pendingTurnAttachRetry) {
        _pendingTurnDirection = null;
        _debugPageTurn('pendingTurnConsumed', detail: 'direction=$direction');
        if (direction > 0) {
          _goNextPage(tapTurn: true);
        } else {
          _goPreviousPage(tapTurn: true);
        }
      }
    });
  }

  void _dispatchBoundaryRequest(
    VoidCallback callback, {
    required bool hasNeighbor,
  }) {
    _boundaryResetTimer?.cancel();
    _boundaryRequestInFlight = true;
    _transitionInFlight = true;
    callback();
    // 无论是否有邻章，都设置超时复位：切章失败/被吞时防止输入永久锁死。
    final delay =
        hasNeighbor
            ? const Duration(milliseconds: 1200)
            : const Duration(milliseconds: 250);
    _boundaryResetTimer = Timer(delay, () {
      if (!mounted) return;
      if (!_boundaryRequestInFlight && !_transitionInFlight) {
        return;
      }
      // 超时复位是失败恢复主路径：切章失败/被吞时强制释放闸门。
      _debugPageTurn(
        'boundaryTimeoutReset',
        detail: 'hasNeighbor=$hasNeighbor delayMs=${delay.inMilliseconds}',
      );
      _updateState(() {
        _boundaryRequestInFlight = false;
        _transitionInFlight = false;
      });
    });
  }
}
