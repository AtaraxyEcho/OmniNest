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
    final max = scrollController.position.maxScrollExtent;
    if (max <= 0) return;

    if (restore.shouldSuppressWrites ||
        isRestoringProgress ||
        isSwitchingChapter) {
      return;
    }

    if (DateTime.now().isBefore(restoreSilenceUntil)) return;

    final timeSincePointerDown =
        DateTime.now().difference(lastPointerDownTime).inMilliseconds;
    if (timeSincePointerDown > 2000) return;

    if (modeSwitchInProgress) {
      modeSwitchInProgress = false;
      modeSwitchAnchor = null;
      restoreTargetCharOffset = 0;
    }

    // 连续滚动：进度由 ReaderContinuousScrollView 的 onScrollPosition 驱动。
    // 此处仅保留近端预取，不再在章末硬切章。
    if (max - scrollController.offset < max * 0.2) {
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

    final timeSincePointerDown =
        DateTime.now().difference(lastPointerDownTime).inMilliseconds;
    if (timeSincePointerDown > 2000) return;

    if (modeSwitchInProgress) {
      modeSwitchInProgress = false;
      modeSwitchAnchor = null;
      restoreTargetCharOffset = 0;
    }

    dismissReturnSnackBar();

    final loader = contentLoader;
    if (loader == null) return;

    // 锚点章切换：顺序续读，不走 switchToChapter 硬切。
    if (position.chapterId != currentChapterId) {
      adoptContinuousAnchorChapter(position.chapterId);
    }

    final chapterData = loader.getByChapterId(position.chapterId);
    final totalChars = chapterData?.totalChars ?? 0;
    // 连续滚动：以窗口控制器的块级映射为准，避免与 contentYToCharOffset 双路径不一致。
    final charOffset = position.charOffset;
    final newProgress =
        totalChars > 0 ? (charOffset / totalChars).clamp(0.0, 1.0) : 0.0;

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
    if ((newProgress - scrollProgress).abs() > 0.001 ||
        position.chapterId == currentChapterId) {
      setState(() => scrollProgress = newProgress);
      scheduleLocalProgressSave(
        chapterProgress: newProgress,
        mode: 'scroll',
        charOffset: charOffset,
      );
    }

    if (scrollController.hasClients) {
      final max = scrollController.position.maxScrollExtent;
      if (max - scrollController.offset < max * 0.2) {
        preloadAdjacent();
      }
    }
  }

  /// 顺序滚动进入邻章：只更新锚点，不重建整棵阅读树。
  void adoptContinuousAnchorChapter(String chapterId) {
    if (chapterId == currentChapterId) return;
    currentChapterId = chapterId;
    annotationHandler?.updateChapter(chapterId);
    final needFetch = contentLoader?.setActive(chapterId) ?? const [];
    for (final id in needFetch) {
      unawaited(prefetchChapter(id));
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// 连续滚动窗口扩挂：预取前后章并重建窗口。
  void onContinuousWindowExpand({required bool forward}) {
    if (!mounted || isPageMode) return;
    final loader = contentLoader;
    if (loader == null) return;
    final chapterIds = loader.chapterIds;
    final idx = chapterIds.indexOf(currentChapterId);
    if (idx < 0) return;
    final targetIndex = forward ? idx + 1 : idx - 1;
    if (targetIndex < 0 || targetIndex >= chapterIds.length) {
      return;
    }
    final targetId = chapterIds[targetIndex];
    if (loader.getByChapterId(targetId) != null &&
        loader.isScrollLayoutReady(targetId)) {
      // 已就绪：仅重建窗口（锚点仍可能是当前章）。
      rebuildContinuousWindow();
      return;
    }
    unawaited(() async {
      await prefetchChapter(targetId);
      if (!mounted) return;
      loader.ensureScrollLayoutForNeighbors(
        currentChapterId,
        pageWidth: computePageWidth(),
        settings: settings,
        textScale: MediaQuery.textScalerOf(context).scale(1.0),
      );
      rebuildContinuousWindow();
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
      // 连续滚动窗口：先扩挂邻章再尝试；仍无法滚动时才按目录跳章。
      onContinuousWindowExpand(forward: forward);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      final again = await scrollBy(viewportDelta);
      if (!again && mounted) {
        tryNavigateChapter(forward ? 1 : -1);
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
    final latestMax = scrollController.position.maxScrollExtent;
    if (latestMax > 0) {
      final contentY = scrollController.offset + viewportAnchorY;
      final charOffset =
          contentLoader?.contentYToCharOffset(
            currentChapterId,
            contentY,
            pageWidth: computePageWidth(),
            settings: settings,
            textScale: MediaQuery.textScalerOf(context).scale(1.0),
          ) ??
          0;
      final totalChars =
          contentLoader?.getByChapterId(currentChapterId)?.totalChars ?? 0;
      final latestProgress =
          totalChars > 0
              ? (charOffset / totalChars).clamp(0.0, 1.0)
              : scrollProgress;
      if ((latestProgress - scrollProgress).abs() > 0.001) {
        setState(() => scrollProgress = latestProgress);
      }
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
        // 滚动模式：从实际滚动位置计算精确锚点
        final contentY = scrollController.offset + viewportAnchorY;
        savedCharOffset =
            contentLoader?.contentYToCharOffset(
              currentChapterId,
              contentY,
              pageWidth: computePageWidth(),
              settings: settings,
              textScale: MediaQuery.textScalerOf(context).scale(1.0),
            ) ??
            positionTracker.charOffset;
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
        final mapped = loader.contentYToCharOffset(
          currentChapterId,
          scrollController.offset + viewportAnchorY,
          pageWidth: computePageWidth(),
          settings: settings,
          textScale: MediaQuery.textScalerOf(context).scale(1.0),
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
