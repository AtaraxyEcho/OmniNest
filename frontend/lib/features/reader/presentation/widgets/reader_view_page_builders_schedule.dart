part of 'reader_view_page_builders.dart';

/// 重建与视口/分页预热的调度方法。
extension ReaderViewPageBuildersSchedule on ReaderViewPageBuilders {
  void _requestReaderRebuild() {
    if (!mounted) {
      return;
    }
    if (_readerRebuildScheduled) {
      return;
    }
    _readerRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readerRebuildScheduled = false;
      if (mounted) {
        _updateState(() {});
      }
    });
  }

  void scheduleProgressSnapshotApply(ReaderProgressSnapshot snapshot) {
    final updatedAt = snapshot.updatedAt;
    if (updatedAt == null) {
      return;
    }
    final appliedAt = lastAppliedProgressAt;
    if (appliedAt != null && !updatedAt.isAfter(appliedAt)) {
      return;
    }
    final pendingAt = _pendingProgressSnapshot?.updatedAt;
    if (pendingAt != null && !updatedAt.isAfter(pendingAt)) {
      return;
    }
    _pendingProgressSnapshot = snapshot;
    if (_progressSnapshotApplyScheduled) {
      return;
    }
    _progressSnapshotApplyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _progressSnapshotApplyScheduled = false;
      final nextSnapshot = _pendingProgressSnapshot;
      _pendingProgressSnapshot = null;
      if (!mounted || nextSnapshot == null) {
        return;
      }
      final nextUpdatedAt = nextSnapshot.updatedAt;
      final currentAppliedAt = lastAppliedProgressAt;
      if (nextUpdatedAt == null ||
          (currentAppliedAt != null &&
              !nextUpdatedAt.isAfter(currentAppliedAt))) {
        return;
      }
      applyProgressSnapshot(nextSnapshot);
    });
  }

  void _scheduleViewportUpdate(Size viewportSize) {
    _pendingViewportSize = viewportSize;
    if (_viewportUpdateScheduled) {
      return;
    }
    _viewportUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportUpdateScheduled = false;
      final nextSize = _pendingViewportSize;
      _pendingViewportSize = null;
      if (!mounted || nextSize == null || pageViewportSize == nextSize) {
        return;
      }
      pageViewportSize = nextSize;
      onViewportChanged(nextSize);
    });
  }

  void _schedulePageNavigatorWarmup(
    PageNavigator navigator,
    int pageIndex,
    String chapterId,
  ) {
    if (_pageNavigatorWarmupScheduled) {
      return;
    }
    _pageNavigatorWarmupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageNavigatorWarmupScheduled = false;
      if (!mounted || currentChapterId != chapterId) {
        return;
      }
      // 换章后重置就绪页数，避免旧章页数造成边界误判。
      if (_pageCountWarmupChapterId != chapterId) {
        _pageCountWarmupChapterId = chapterId;
        pageCountNotifier.value = 0;
      }
      navigator.ensurePage(0);
      pageCountNotifier.value = navigator.readablePageCount;
      navigator.schedulePrefetch(
        pageIndex,
        onPageReady: () {
          if (!mounted) return;
          // 预取循环不随切章取消：换章后旧章的预取回调不得污染新章计数。
          if (currentChapterId != chapterId) return;
          pageCountNotifier.value = navigator.readablePageCount;
        },
      );
    });
  }
}
