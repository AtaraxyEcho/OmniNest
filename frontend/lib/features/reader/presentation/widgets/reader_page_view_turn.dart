part of 'reader_page_view.dart';

/// 翻页命令、输入闸门与待执行翻页意图。
extension _ReaderPageViewTurn on _ReaderPageViewState {
  void _onExternalPageCommand() {
    // 底栏/快捷键是显式翻页意图，不能被上一次手势残留的滚动状态吞掉；
    // 重复触发仍由闸门内的动画与边界请求原因挡住。
    if (ReaderInteractionGate.blocksTapTurn(_blockReason)) return;
    final direction = widget.controller?.direction ?? 0;
    if (direction > 0) {
      _goNextPage(tapTurn: true);
    } else if (direction < 0) {
      _goPreviousPage(tapTurn: true);
    }
  }

  void _initForMode() {
    // 控制器重建后旧翻页意图的目标已失效，显式丢弃；在途动画的
    // status listener 随旧控制器销毁不再回调，动画标志必须一并复位，
    // 否则 pageAnimationActive 恒真锁死翻页闸门。
    _isAnimating = false;
    _pendingTurnDirection = null;
    _pendingTurnFrames = 0;
    _localPageCount = widget.state.pageCount;
    _probingNext = false;
    _slideScrolling = false;
    _transitionInFlight = false;
    _boundaryRequestInFlight = false;
    _pendingSlideBoundaryDirection = 0;
    if (widget.turnMode == PageTurnMode.slide) {
      _pageController = PageController(initialPage: widget.state.pageIndex);
    } else {
      _animController = AnimationController(
        vsync: this,
        duration: const Duration(
          milliseconds: _ReaderPageViewState._flipDurationMs,
        ),
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
  ///
  /// ReaderPageView 挂载早于分页完成时，PageController.initialPage 会因
  /// item 数不足被钳制到 0；若恢复目标恰与挂载时的 state.pageIndex 相同
  /// （模式切换回页模式的典型路径），此后 pageIndex 不再变化，仅靠
  /// didUpdateWidget 的索引差异判定永远触发不了 _syncPageView，物理页
  /// 滞留章首。在无加载、无边界请求、无动画且非拖拽的空闲期补一次对齐；
  /// 恢复静默窗会吞掉对齐产生的 onPageChanged 回声，不污染进度写入。
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
    _currentPageWidget = widget.pageBuilder(widget.state.pageIndex);
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

  /// 翻页链路诊断快照（D0 观测）：rightTapReceived=false 说明 HitTest/
  /// 手势层有问题；tapBlocked=true 说明闸门/残留状态有问题；两者正常而
  /// 画面不动说明 PageFlow/Transition 有问题。
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
      _debugPageTurn('nextDeferredDuringAnimation');
      return;
    }

    // 目标基于控制器实际物理页：state 与物理页脱节时（历史 onPageChanged
    // 被吞等）按物理页前进，点击不再空转（方案 §8 最新状态重算）。
    final ctrl = _pageController;
    final basePage =
        ctrl != null && ctrl.hasClients
            ? (ctrl.page?.round() ?? widget.state.pageIndex)
            : widget.state.pageIndex;
    final nextIndex = basePage + 1;
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
      _flipProgress = 0.01;
      _startAutoFlip();
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
        return;
      }
      final direction = _pendingTurnDirection;
      if (direction == null) {
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
      if (ctrl != null && ctrl.hasClients) {
        _debugPageTurn('previousStart', detail: 'target=${basePage - 1}');
        _transitionInFlight = true;
        unawaited(_animateSlideTo(ctrl, basePage - 1));
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
      _flipProgress = 0.01;
      _startAutoFlip();
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
          _probingNext) {
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
