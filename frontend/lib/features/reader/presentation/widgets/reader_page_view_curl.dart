part of 'reader_page_view.dart';

/// 双向卷页双槽空闲预抓图与装配（v13：同步透传 seamlessSpine 并兼容单页精装书壳透明底）。
extension _ReaderPageViewCurl on _ReaderPageViewState {
  void _scheduleIdleNextCurlWarmup() {
    _curlWarmupTimer?.cancel();
    if (widget.turnMode != PageTurnMode.cover) return;
    _curlWarmupTimer = Timer(const Duration(milliseconds: 80), () async {
      if (!mounted || _curlFrameNotifier.value.active || _isDragging) return;
      await _ensureCurlPairReady(_curlDirectionFor(true));
      if (!mounted || _curlFrameNotifier.value.active || _isDragging) return;
      await _ensureCurlPairReady(_curlDirectionFor(false));
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
    final dir = explicitDir ?? _curlDirectionFor(_isForward);
    if (_hasReadyCurlPair(dir) || _capturingDirs.contains(dir)) return;
    unawaited(_ensureCurlPairReady(dir));
  }

  Future<bool> _ensureCurlPairReady(CurlDirection dir) async {
    if (widget.turnMode != PageTurnMode.cover || !mounted) return false;
    if (_hasReadyCurlPair(dir)) return true;

    // 串行化访问共享的 _singleBackCaptureKey，杜绝 next/prev 并发覆写抓图槽。
    while (_backCaptureLock != null) {
      await _backCaptureLock!.future;
      if (!mounted) return false;
      if (_hasReadyCurlPair(dir)) return true;
    }

    final lock = Completer<void>();
    _backCaptureLock = lock;
    _capturingDirs.add(dir);
    final token = _curlToken;
    try {
      if (token != _curlToken) return false;
      final idx = widget.state.pageIndex;
      final forward = _isLogicalForward(dir);
      final frontPageIdx = widget.spread ? (forward ? idx + 1 : idx) : idx;
      final backPageIdx =
          forward ? (widget.spread ? idx + 2 : idx + 1) : idx - 1;

      final prepare = widget.prepareSnapshotPage;
      if (prepare != null) {
        if (frontPageIdx >= 0 && frontPageIdx < widget.state.pageCount) {
          final frontReady = await prepare(frontPageIdx);
          if (!mounted || token != _curlToken || !frontReady) return false;
        }
        if (backPageIdx >= 0 && backPageIdx < widget.state.pageCount) {
          final backReady = await prepare(backPageIdx);
          if (!mounted || token != _curlToken || !backReady) return false;
        }
        // 等待一帧让刚就绪的正面图片完成首帧绘制，避免正面抓到占位或 Loading。
        await SchedulerBinding.instance.endOfFrame;
        if (!mounted || token != _curlToken) return false;
      }

      // 高分屏截图 dpr 上限提升至 2.0，消除点击翻页瞬间文字变糊跳变。
      final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
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

      // 背面落位侧：向右翻（右页翻到左侧）背面为左页；向左翻（左页翻到右侧）背面为右页。
      final backSide =
          dir == CurlDirection.next ? _SpreadSide.left : _SpreadSide.right;
      final frameReady = Completer<void>();
      _backFrameReadyCompleter = frameReady;
      _updateState(() {
        _pendingBackCaptureSide = backSide;
        _pendingBackCaptureWidget = backWidget;
      });
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || token != _curlToken) {
        frontImg.dispose();
        return false;
      }
      if (prepare != null) {
        // 优先等待背面子页首帧绘制就绪（由 ComicPageImage.onFirstFramePainted 派发），
        // 配合统一 ResizeImage 缓存键预热，400ms 超时兜底防止异常图阻塞。
        if (!frameReady.isCompleted) {
          await frameReady.future.timeout(
            const Duration(milliseconds: 400),
            onTimeout: () {},
          );
          if (!mounted || token != _curlToken) {
            frontImg.dispose();
            return false;
          }
        }
        await SchedulerBinding.instance.endOfFrame;
        if (!mounted || token != _curlToken) {
          frontImg.dispose();
          return false;
        }
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
      // 关键修复：若抓图完成时用户仍在同方向拖拽，立刻补发当前进度首帧，杜绝偶发哑火！
      final dragDir = _curlDirectionFor(_isForward);
      if (mounted && _isDragging && dragDir == dir && _flipProgress > 0.005) {
        final wasActive = _curlFrameNotifier.value.active;
        _curlFrameNotifier.value = CurlFrame(
          progress: _flipProgress,
          direction: dir,
          config: _activeCurlConfig,
        );
        if (!wasActive) _updateState(() {});
      }
      return true;
    } finally {
      _capturingDirs.remove(dir);
      final readyCompleter = _backFrameReadyCompleter;
      _backFrameReadyCompleter = null;
      if (readyCompleter != null && !readyCompleter.isCompleted) {
        readyCompleter.complete();
      }
      if (mounted && _pendingBackCaptureWidget != null) {
        _updateState(() => _pendingBackCaptureWidget = null);
      }
      if (identical(_backCaptureLock, lock)) {
        _backCaptureLock = null;
      }
      if (!lock.isCompleted) lock.complete();
    }
  }

  Widget? _resolveCurlBackWidget(CurlDirection dir) {
    final idx = widget.state.pageIndex;
    final forward = _isLogicalForward(dir);
    final targetIdx = forward ? (widget.spread ? idx + 2 : idx + 1) : idx - 1;
    final builder = widget.snapshotPageBuilder ?? widget.pageBuilder;
    final inChapter = targetIdx >= 0 ? builder(targetIdx) : null;
    if (inChapter != null) return inChapter;
    return widget.crossChapterSnapshotBuilder?.call(forward ? 1 : -1);
  }

  /// 循环等待 RenderRepaintBoundary 完成本帧绘制后再调用 toImage，
  /// 彻底杜绝 '!debugNeedsPaint' 异常导致静默返回 null。
  Future<ui.Image?> _captureBoundarySafe(GlobalKey key, double ratio) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted) return null;
      final ro = key.currentContext?.findRenderObject();
      if (ro is RenderRepaintBoundary &&
          !ro.debugNeedsPaint &&
          ro.hasSize &&
          !ro.size.isEmpty) {
        try {
          return await ro.toImage(pixelRatio: ratio);
        } on Object {
          return null;
        }
      }
      WidgetsBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame;
    }
    return null;
  }

  void _clearCurlImages() {
    _curlWarmupTimer?.cancel();
    _curlToken++;
    _capturingDirs.clear();
    _pendingBackCaptureWidget = null;
    final readyCompleter = _backFrameReadyCompleter;
    _backFrameReadyCompleter = null;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.complete();
    }
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
    final readyCompleter = _backFrameReadyCompleter;
    _backFrameReadyCompleter = null;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.complete();
    }
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
      seamlessSpine: widget.seamlessSpine,
    );

    final forward = _isLogicalForward(frame.direction);

    if (!widget.spread) {
      final targetIndex =
          forward ? widget.state.pageIndex + 1 : widget.state.pageIndex - 1;
      final revealed =
          targetIndex >= 0 ? widget.pageBuilder(targetIndex) : null;
      // 复用 _buildRestingPage 保持 _liveSingleKey 挂载位置不变，杜绝第 1 帧重建闪烁。
      return _buildRestingPage(
        singleOverride: revealed,
        curlOverlay: curlLayer,
      );
    }

    final idx = widget.state.pageIndex;
    final isVisualNext = frame.direction == CurlDirection.next;
    final Widget underlayLeft;
    final Widget? underlayRight;

    if (widget.reverse) {
      // RTL 日漫双页：当前右页 idx、左页 idx + 1。
      // 左向右掀（!isVisualNext = 逻辑前进）：左页露出 idx + 3，右页保持 idx；
      // 右向左掀（isVisualNext = 逻辑后退）：左页保持 idx + 1，右页露出 idx - 2。
      underlayLeft =
          (isVisualNext
              ? widget.pageBuilder(idx + 1)
              : (widget.pageBuilder(idx + 3) ??
                  (idx + 2 >= widget.state.pageCount
                      ? widget.crossChapterSnapshotBuilder?.call(1)
                      : null))) ??
          const SizedBox.expand();
      underlayRight =
          isVisualNext
              ? (idx - 2 >= 0
                  ? widget.pageBuilder(idx - 2)
                  : widget.crossChapterSnapshotBuilder?.call(-1))
              : widget.pageBuilder(idx);
    } else {
      underlayLeft =
          (isVisualNext
              ? widget.pageBuilder(idx)
              : (idx - 2 >= 0
                  ? widget.pageBuilder(idx - 2)
                  : widget.crossChapterSnapshotBuilder?.call(-1))) ??
          const SizedBox.expand();
      underlayRight =
          isVisualNext
              ? (widget.pageBuilder(idx + 3) ??
                  (idx + 2 >= widget.state.pageCount
                      ? widget.crossChapterSnapshotBuilder?.call(1)
                      : null))
              : widget.pageBuilder(idx + 1);
    }

    // 复用 _buildRestingPage 保持 _liveLeftKey / _liveRightKey 挂载在同一 RepaintBoundary。
    return _buildRestingPage(
      leftOverride: underlayLeft,
      rightOverride: underlayRight,
      curlOverlay: curlLayer,
    );
  }

  /// 置于底层全不透明绘制；双页模式统一采用 `_SpreadPage` 样式与正面截图严格对齐。
  Widget _buildSingleBackCaptureSlot(double leafWidth, double height) {
    final child = _pendingBackCaptureWidget;
    if (child == null) return const SizedBox.shrink();
    final styledChild =
        widget.spread
            ? _SpreadPage(
              color: widget.surfaceColor,
              side: _pendingBackCaptureSide,
              showPaperGrain: widget.showPaperGrain,
              seamlessSpine: widget.seamlessSpine,
              child: child,
            )
            : (widget.seamlessSpine || widget.deskColor != null)
            ? SizedBox.expand(child: child)
            : ColoredBox(color: widget.surfaceColor, child: child);
    return Positioned(
      left: 0,
      top: 0,
      width: leafWidth,
      height: height,
      child: ExcludeFocus(
        child: IgnorePointer(
          child: NotificationListener<ReaderSnapshotFrameReadyNotification>(
            onNotification: (_) {
              final completer = _backFrameReadyCompleter;
              if (completer != null && !completer.isCompleted) {
                completer.complete();
              }
              return true;
            },
            child: RepaintBoundary(
              key: _singleBackCaptureKey,
              child: styledChild,
            ),
          ),
        ),
      ),
    );
  }
}
