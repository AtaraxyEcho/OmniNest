import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_mixin.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 阅读页面的滚动交互、设置应用与重新分页逻辑。
mixin ReaderViewPageInteractionMixin
    on ConsumerState<ReaderViewPage>, ReaderViewPageMixin {
  static const restoreSilenceMs = 400;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 滚动模式交互
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 滚动事件处理。
  void onScroll() {
    if (!scrollController.hasClients) return;
    if (isLoadingChapter) return;
    dismissReturnSnackBar();
    lastScrollActivityAt = DateTime.now();
    final max = scrollController.position.maxScrollExtent;
    if (max <= 0) return;

    if (restore.shouldSuppressWrites ||
        isRestoringProgress ||
        isSwitchingChapter) {
      return;
    }

    if (DateTime.now().isBefore(restoreSilenceUntil)) return;

    if (modeSwitchInProgress) {
      modeSwitchInProgress = false;
      modeSwitchAnchor = null;
      restoreTargetCharOffset = 0;
    }

    // 连续滚动：进度由 ReaderContinuousScrollView 的 onScrollPosition 驱动。
    if (max - scrollController.offset < max * 0.5) {
      preloadAdjacent();
    }
  }

  /// 连续滚动位置回调：更新锚点章、进度与邻章窗口。
  void onContinuousScrollPosition(ContinuousScrollPosition position) {
    if (!mounted || isPageMode) return;
    if (restore.shouldSuppressWrites ||
        isRestoringProgress ||
        isSwitchingChapter) {
      return;
    }
    if (DateTime.now().isBefore(restoreSilenceUntil)) return;
    lastScrollActivityAt = DateTime.now();

    if (modeSwitchInProgress) {
      modeSwitchInProgress = false;
      modeSwitchAnchor = null;
      restoreTargetCharOffset = 0;
    }

    handleResolvedPosition(position);
  }

  /// 以窗口控制器解析出的位置更新锚点章、进度与邻章窗口。
  ///
  /// 滚动回调与键盘滚动（scrollBy）共用：键盘不产生指针事件，
  /// 距上次指针事件 >2s 的守卫会使其停更，故由 scrollBy 主动调用。
  void handleResolvedPosition(ContinuousScrollPosition position) {
    dismissReturnSnackBar();

    final loader = contentLoader;
    if (loader == null) return;

    // 顺序滚动进入邻章：先收养锚点，避免封面/短章 totalChars<=0 时
    // 视口已过章但 currentChapterId 停留旧章导致跳章与扩窗错位。
    if (position.chapterId != currentChapterId) {
      adoptContinuousAnchorChapter(position.chapterId);
    }

    // 图片主导的封面等章节 totalChars 为 0：不要用 charOffset=0 覆盖进度。
    final chapterData = loader.getByChapterId(position.chapterId);
    final totalChars = chapterData?.totalChars ?? 0;
    if (totalChars <= 0) {
      if (scrollController.hasClients) {
        final max = scrollController.position.maxScrollExtent;
        if (max - scrollController.offset < max * 0.5) {
          preloadAdjacent();
        }
      }
      return;
    }

    // 连续滚动：以窗口控制器的块级映射为准，避免与 contentYToCharOffset 双路径不一致。
    final charOffset = position.charOffset;
    final newProgress = (charOffset / totalChars).clamp(0.0, 1.0);

    positionTracker.updateFromScroll(
      offset: scrollController.hasClients ? scrollController.offset : 0,
      maxExtent:
          scrollController.hasClients
              ? scrollController.position.maxScrollExtent
              : 0,
      totalChars: totalChars,
      chapterId: position.chapterId,
      charOffset: charOffset,
    );
    if ((newProgress - scrollProgress).abs() > 0.004 ||
        (position.chapterId == currentChapterId &&
            (charOffset - (_lastSavedScrollCharOffset ?? -1)).abs() >= 48)) {
      // 热路径：只更新通知器；写盘经 coordinator 合并。
      // 阈值避免滚动每帧都 schedule，降低写入与 noteOwnProgressSave 开销。
      scrollProgress = newProgress;
      _lastSavedScrollCharOffset = charOffset;
      scheduleLocalProgressSave(
        chapterProgress: newProgress,
        mode: 'scroll',
        charOffset: charOffset,
      );
    }

    if (scrollController.hasClients) {
      final max = scrollController.position.maxScrollExtent;
      final offset = scrollController.offset;
      if (max > 0 && max - offset < max * 0.5) {
        _throttledPreloadAdjacent();
      }
      if (max > 0 && max - offset < max * 0.35) {
        _throttledExpandForward();
      }
      if (offset < 240) {
        _throttledExpandBackward();
      }
    }
  }

  int? _lastSavedScrollCharOffset;
  Timer? _preloadDebounce;
  Timer? _expandForwardDebounce;
  Timer? _expandBackwardDebounce;
  bool _expandForwardInFlight = false;

  void _throttledPreloadAdjacent() {
    if (_preloadDebounce?.isActive ?? false) {
      return;
    }
    preloadAdjacent();
    _preloadDebounce = Timer(const Duration(milliseconds: 400), () {});
  }

  void _throttledExpandForward() {
    if (_expandForwardInFlight || (_expandForwardDebounce?.isActive ?? false)) {
      return;
    }
    _expandForwardInFlight = true;
    onContinuousWindowExpand(forward: true);
    _expandForwardDebounce = Timer(const Duration(milliseconds: 600), () {
      _expandForwardInFlight = false;
    });
  }

  void _throttledExpandBackward() {
    if (_expandBackwardDebounce?.isActive ?? false) {
      return;
    }
    onContinuousWindowExpand(forward: false);
    _expandBackwardDebounce = Timer(const Duration(milliseconds: 600), () {});
  }

  /// 释放滚动节流 Timer（由 State.dispose 调用）。
  void disposeScrollThrottles() {
    _preloadDebounce?.cancel();
    _expandForwardDebounce?.cancel();
    _expandBackwardDebounce?.cancel();
  }

  /// 顺序滚动进入邻章：只更新锚点，不重建整棵阅读树。
  void adoptContinuousAnchorChapter(String chapterId) {
    if (chapterId == currentChapterId) return;
    // 加载中改写 currentChapterId 会使在途 loadCurrentChapter 判定失效；
    // 但若正文/块均已就绪，仍允许收养，避免封面章后锚点卡死。
    if (isLoadingChapter || isSwitchingChapter) {
      final ready =
          contentLoader?.getByChapterId(chapterId) != null &&
          contentLoader?.contentFor(chapterId) != null;
      if (!ready) {
        return;
      }
    }
    currentChapterId = chapterId;
    annotationHandler?.updateChapter(chapterId);
    final needFetch = contentLoader?.setActive(chapterId) ?? const [];
    for (final id in needFetch) {
      unawaited(prefetchChapter(id));
    }
    // blocks 与 HTML 均就绪时同步加载标记：避免 build 后
    // loadChapterContentIfNeeded 对锚点章冗余重取正文。
    final content = contentLoader?.contentFor(chapterId);
    if (contentLoader?.getByChapterId(chapterId) != null && content != null) {
      cachedContent = content;
      lastLoadedChapterId = chapterId;
    }
    // 滚动回调可能来自 layout 阶段，禁止同步 setState。
    if (mounted) {
      _scheduleContinuousAdoptRebuild();
    }
  }

  bool _continuousAdoptRebuildScheduled = false;

  void _scheduleContinuousAdoptRebuild() {
    if (_continuousAdoptRebuildScheduled) return;
    _continuousAdoptRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _continuousAdoptRebuildScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// 连续滚动窗口扩挂：以窗口边缘章为基准预取并重建。
  void onContinuousWindowExpand({required bool forward}) {
    if (!mounted || isPageMode) return;
    final loader = contentLoader;
    if (loader == null) return;
    final chapterIds = loader.chapterIds;
    // 以窗口边缘而非 currentChapterId 为基准：锚点收养滞后时避免重复扩同一章。
    final windowIds = continuousScrollController.entries
        .map((e) => e.chapterId)
        .toList(growable: false);
    final edgeId =
        windowIds.isNotEmpty
            ? (forward ? windowIds.last : windowIds.first)
            : currentChapterId;
    final idx = chapterIds.indexOf(edgeId);
    if (idx < 0) return;
    final targetIndex = forward ? idx + 1 : idx - 1;
    if (targetIndex < 0 || targetIndex >= chapterIds.length) {
      return;
    }
    final targetId = chapterIds[targetIndex];
    final targetData = loader.getByChapterId(targetId);
    if (targetData != null) {
      // blocks 已就绪：只补滚动测高（未就绪时），不重取正文 HTML。
      if (!loader.isScrollLayoutReady(targetId)) {
        loader.ensureScrollLayoutForNeighbors(
          edgeId,
          pageWidth: computePageWidth(),
          settings: settings,
          textScale: MediaQuery.textScalerOf(context).scale(1.0),
        );
      }
      invalidateContinuousWindowFingerprint();
      rebuildContinuousWindow();
      return;
    }
    unawaited(() async {
      await prefetchChapter(targetId);
      if (!mounted) return;
      loader.ensureScrollLayoutForNeighbors(
        edgeId,
        pageWidth: computePageWidth(),
        settings: settings,
        textScale: MediaQuery.textScalerOf(context).scale(1.0),
      );
      invalidateContinuousWindowFingerprint();
      rebuildContinuousWindow();
      if (mounted) {
        setState(() {});
      }
    }());
  }

  /// 用户主动滚动前终止进行中的进度恢复。
  ///
  /// ScrollRestore 在恢复期与监控期都会 jumpTo 锚点，会与本次滚动对抗，
  /// 导致滚动位移归零被误判为章末并触发跳章；同时清掉恢复遮罩。
  void _cancelOngoingRestoreForUserScroll() {
    if (!restore.shouldSuppressWrites && !isRestoringProgress) {
      return;
    }
    restore.cancel();
    isRestoringProgress = false;
    pendingChapterProgress = null;
    pendingRestoreCharOffset = null;
    if (mounted) {
      setState(() {});
    }
  }

  /// 侧边点击处理。
  Future<void> handleSideTap(
    ReaderItemDetail detail, {
    required bool forward,
  }) async {
    if (isSwitchingChapter || isLoadingChapter) return;
    _cancelOngoingRestoreForUserScroll();
    final viewportDelta =
        (forward ? 1 : -1) * MediaQuery.sizeOf(context).height * 0.8;
    final didScroll = await scrollBy(viewportDelta);
    if (!mounted) return;
    if (!didScroll) {
      // 连续滚动窗口：先扩挂邻章再尝试；大章测高需更长等待。
      onContinuousWindowExpand(forward: forward);
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;
      final again = await scrollBy(viewportDelta);
      if (!again && mounted) {
        onContinuousWindowExpand(forward: forward);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
        final retry = await scrollBy(viewportDelta);
        if (!retry && mounted) {
          tryNavigateChapter(forward ? 1 : -1);
        }
      }
    }
  }

  /// 滚动指定距离。返回 true 表示实际执行了滚动。
  Future<bool> scrollBy(double delta) async {
    if (!scrollController.hasClients) return false;
    final currentOffset = scrollController.offset;
    final max = scrollController.position.maxScrollExtent;
    final target = (currentOffset + delta).clamp(0.0, max);
    if ((target - currentOffset).abs() < 1.0) return false;
    await scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !scrollController.hasClients) return true;
    // 键盘滚动不产生指针事件：主动取消进行中的恢复并按窗口控制器
    // 解析结果汇报位置，绕过"距上次指针事件 >2s"守卫的停更。
    _cancelOngoingRestoreForUserScroll();
    final resolved = continuousScrollController.positionAtContentY(
      scrollController.offset + viewportAnchorY,
    );
    if (resolved != null) {
      handleResolvedPosition(resolved);
    }
    unawaited(syncProgressAsync());
    return true;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 设置变更
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 设置变更回调。
  void onSettingsChanged(ReaderViewSettings newSettings) {
    if (showControls) startHideTimer();
    if (isAnimating) {
      pendingSettings = newSettings;
      return;
    }
    applySettings(newSettings);
  }

  /// 动画完成后检查延迟的设置变更。
  void onAnimationComplete() {
    if (pendingSettings != null) {
      applySettings(pendingSettings!);
      pendingSettings = null;
    }
  }

  /// 应用阅读设置变更。
  void applySettings(ReaderViewSettings newSettings) {
    if (!supportsPageMode && newSettings.readingMode != 'scroll') {
      newSettings = newSettings.copyWith(readingMode: 'scroll');
    }

    final fontChanged =
        newSettings.fontSize != settings.fontSize ||
        newSettings.lineHeight != settings.lineHeight ||
        newSettings.fontFamily != settings.fontFamily;
    final modeChanged = newSettings.readingMode != settings.readingMode;
    final immersiveChanged =
        newSettings.immersiveMode != settings.immersiveMode;
    final layoutChanged = fontChanged || modeChanged || immersiveChanged;

    // 冻结当前阅读锚点：优先从滚动位置计算（比 tracker 更精确），
    // 因为翻页模式的 onPageChanged 可能已将 tracker 更新为页首。
    int savedCharOffset = 0;
    if (layoutChanged) {
      if (!isPageMode &&
          scrollController.hasClients &&
          scrollController.position.maxScrollExtent > 0) {
        // 滚动模式：从实际滚动位置计算精确锚点（窗口坐标统一换算）
        savedCharOffset = windowContentYToCharOffset(
          currentChapterId,
          scrollController.offset + viewportAnchorY,
        );
        if (savedCharOffset <= 0) {
          savedCharOffset = positionTracker.charOffset;
        }
      } else {
        savedCharOffset = positionTracker.charOffset;
      }
    }

    if (immersiveChanged) {
      applyImmersiveMode(newSettings.immersiveMode);
      if (newSettings.immersiveMode) {
        hideTimer?.cancel();
        showControls = false;
      }
    }
    settings = newSettings;
    persistSettings(newSettings);

    if (layoutChanged) {
      if (modeChanged) {
        modeSwitchInProgress = true;
        // 冻结锚点，防止 onPageChanged 用页首覆盖
        modeSwitchAnchor = savedCharOffset;
      }

      if (kDebugMode) {
        readerDebugLog(
          'ApplySettings: modeChanged=$modeChanged, fontChanged=$fontChanged, '
          'immersiveChanged=$immersiveChanged, '
          'savedCharOffset=$savedCharOffset, isPageMode=$isPageMode',
        );
      }

      if (isPageMode) {
        // 翻页跨章窗口内多章同步失效，避免邻章仍用旧排版分页。
        final windowIds =
            contentLoader?.chapterIds
                .where((id) {
                  final all = contentLoader?.chapterIds ?? const [];
                  final idx = all.indexOf(currentChapterId);
                  final i = all.indexOf(id);
                  return idx >= 0 && (i - idx).abs() <= 2;
                })
                .toList(growable: false) ??
            [currentChapterId];
        for (final id in windowIds) {
          contentLoader?.getByChapterId(id)?.invalidatePageNavigator();
        }
        contentLoader?.rekeyAndRecomputeHeights(
          currentChapterId,
          computePageWidth(),
          settings,
          MediaQuery.textScalerOf(context).scale(1.0),
          prepareScrollLayout: false,
        );
        repaginateCurrentChapter(restoreCharOffset: savedCharOffset);
      } else {
        contentLoader?.rekeyAndRecomputeHeights(
          currentChapterId,
          computePageWidth(),
          settings,
          MediaQuery.textScalerOf(context).scale(1.0),
        );
        contentLoader?.ensureScrollLayoutForNeighbors(
          currentChapterId,
          pageWidth: computePageWidth(),
          settings: settings,
          textScale: MediaQuery.textScalerOf(context).scale(1.0),
        );
        rebuildContinuousWindow();
        restoreScrollPositionFromOffset(savedCharOffset);
      }
    }

    setState(() {});
  }

  /// 重新分页当前章节。
  void repaginateCurrentChapter({required int restoreCharOffset}) {
    final chapterData = contentLoader?.get(currentChapterId, settings);
    if (chapterData == null) return;

    if (isPageMode) {
      chapterData.invalidatePageNavigator();
      // 邻章分页器一并失效（页流窗口 ±2），保持窗口内页数与切片一致。
      final all = contentLoader?.chapterIds ?? const <String>[];
      final idx = all.indexOf(currentChapterId);
      if (idx >= 0) {
        for (var i = idx - 2; i <= idx + 2; i++) {
          if (i < 0 || i >= all.length) continue;
          contentLoader?.getByChapterId(all[i])?.invalidatePageNavigator();
        }
      }
      pageLocator.cancel();
      isRestoringProgress = true;
      pendingRestoreCharOffset = restoreCharOffset;
      setState(() {});
      return;
    }

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    contentLoader?.rekeyAndRecomputeHeights(
      currentChapterId,
      computePageWidth(),
      settings,
      textScale,
    );
    restoreScrollPosition();
  }

  /// 恢复滚动位置（累积高度已由调用方重算）。
  void restoreScrollPosition() {
    restoreScrollPositionFromOffset(positionTracker.charOffset);
  }

  /// 视口变化时保持当前阅读锚点并重新分页/重测。
  void repaginateForViewportChange(Size newSize) {
    final previousSize = lastViewportSize;
    if (previousSize == newSize) return;
    final widthChanged =
        previousSize == null ||
        (previousSize.width - newSize.width).abs() > 0.5;
    lastViewportSize = newSize;
    pageViewportSize = newSize;
    if (contentLoader == null) return;
    repaginateTimer?.cancel();
    repaginateTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      if (isPageMode) {
        final trackedAnchor = modeSwitchAnchor ?? positionTracker.charOffset;
        final anchor =
            trackedAnchor > 0
                ? trackedAnchor
                : computePageCharOffset(pageModePage);
        repaginateCurrentChapter(restoreCharOffset: anchor);
        return;
      }
      if (!widthChanged) {
        // 高度变化不改变换行；仅刷新窗口启发与布局。
        rebuildContinuousWindow();
        return;
      }
      _repaginateContinuousForViewportWidth();
    });
  }

  /// 连续滚动：视口宽度变化后重测窗口内章节并恢复阅读锚点。
  void _repaginateContinuousForViewportWidth() {
    final loader = contentLoader;
    if (loader == null) return;
    // 先冻结当前锚点（优先真实滚动位置，避免 tracker 滞后）。
    var anchorCharOffset = positionTracker.charOffset;
    if (scrollController.hasClients &&
        scrollController.position.maxScrollExtent > 0) {
      final contentY = scrollController.offset + viewportAnchorY;
      final resolved = continuousScrollController.positionAtContentY(contentY);
      if (resolved != null) {
        anchorCharOffset = resolved.charOffset;
        if (resolved.chapterId != currentChapterId) {
          currentChapterId = resolved.chapterId;
          annotationHandler?.updateChapter(resolved.chapterId);
        }
      } else {
        final mapped = windowContentYToCharOffset(
          currentChapterId,
          scrollController.offset + viewportAnchorY,
        );
        if (mapped > 0) {
          anchorCharOffset = mapped;
        }
      }
    }
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final pageWidth = computePageWidth();
    final windowIds = continuousScrollController.entries
        .map((e) => e.chapterId)
        .toList(growable: false);
    loader.rekeyAndRecomputeHeightsForChapters(
      windowIds.isEmpty ? [currentChapterId] : windowIds,
      pageWidth,
      settings,
      textScale,
    );
    loader.ensureScrollLayoutForNeighbors(
      currentChapterId,
      pageWidth: pageWidth,
      settings: settings,
      textScale: textScale,
    );
    positionTracker.setCharOffset(anchorCharOffset, currentChapterId);
    rebuildContinuousWindow();
    restoreScrollPositionFromOffset(anchorCharOffset);
    if (mounted) {
      setState(() {});
    }
  }

  /// 用指定 charOffset 恢复滚动位置（模式切换专用）。
  void restoreScrollPositionFromOffset(int charOffset) {
    if (charOffset <= 0) return;
    isRestoringProgress = true;
    restoreTargetCharOffset = charOffset;
    restoreSilenceUntil = DateTime.now().add(
      const Duration(milliseconds: restoreSilenceMs),
    );
    pendingChapterProgress = null;
    pendingRestoreCharOffset = charOffset;
  }

  /// 重新分页所有章节。
  void repaginateAll() {
    contentLoader?.invalidateAll();
    repaginateCurrentChapter(restoreCharOffset: positionTracker.charOffset);
  }
}
