import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
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

    final chapterData = contentLoader?.get(currentChapterId, settings);

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

    final totalChars = chapterData?.totalChars ?? 0;
    final newProgress =
        totalChars > 0 ? (charOffset / totalChars).clamp(0.0, 1.0) : 0.0;

    final savedCharOffset = positionTracker.charOffset;
    final restoreTarget = restoreTargetCharOffset;
    if (restoreTarget > 100 && charOffset < restoreTarget * 0.5) {
      if (kDebugMode) {
        readerDebugLog(
          'onScroll SKIP: charOffset deviates from restore target '
          '$restoreTarget -> $charOffset',
        );
      }
      return;
    }
    if (charOffset > 0 &&
        savedCharOffset > 100 &&
        charOffset < savedCharOffset * 0.5 &&
        !isSwitchingChapter) {
      if (kDebugMode) {
        readerDebugLog(
          'onScroll SKIP: charOffset regression $savedCharOffset -> $charOffset',
        );
      }
      return;
    }

    if (chapterData != null) {
      positionTracker.updateFromScroll(
        offset: scrollController.offset,
        maxExtent: max,
        totalChars: chapterData.totalChars,
        chapterId: currentChapterId,
        charOffset: charOffset,
      );
    }
    if ((newProgress - scrollProgress).abs() > 0.001) {
      if (kDebugMode) {
        readerDebugLog(
          'onScroll SAVE: $scrollProgress -> $newProgress, '
          'charOffset=$charOffset (totalChars=${chapterData?.totalChars ?? 0})',
        );
      }
      setState(() => scrollProgress = newProgress);
      scheduleLocalProgressSave(
        chapterProgress: newProgress,
        mode: 'scroll',
        charOffset: charOffset,
      );
    }
    if (max - scrollController.offset < max * 0.2) {
      preloadAdjacent();
    }

    // 边界自动续读：滚动到达章末时自动进入下一章，等效于无缝衔接。
    // 仅向前自动续读；向上回退保留点击热区操作（回弹/恢复事件会与
    // 章首判断互相触发，且回退已有"回到原进度"浮层兜底）。
    final maxStable = _lastObservedMax == max;
    _lastObservedMax = max;
    if (scrollController.offset >= max - 2 &&
        maxStable &&
        DateTime.now().isAfter(_lastAutoAdvanceAt) &&
        contentLoader != null &&
        contentLoader!.allChapters.indexWhere((c) => c.id == currentChapterId) +
                1 <
            contentLoader!.allChapters.length) {
      _lastAutoAdvanceAt = DateTime.now().add(const Duration(seconds: 1));
      tryNavigateChapter(1);
    }
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

  /// 上一次边界自动续读时间；加 1 秒冷却防止连续触发
  DateTime _lastAutoAdvanceAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 上一次滚动事件观察到的 maxScrollExtent，用于稳定门控
  double _lastObservedMax = -1;

  /// 侧边点击处理。
  Future<void> handleSideTap(
    ReaderItemDetail detail, {
    required bool forward,
  }) async {
    if (isSwitchingChapter || isLoadingChapter) return;
    _cancelOngoingRestoreForUserScroll();
    final didScroll = await scrollBy(
      (forward ? 1 : -1) * MediaQuery.sizeOf(context).height * 0.8,
    );
    if (!mounted) return;
    if (!didScroll) {
      tryNavigateChapter(forward ? 1 : -1);
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

  /// 视口变化时保持当前阅读锚点并重新分页。
  void repaginateForViewportChange(Size newSize) {
    final previousSize = lastViewportSize;
    if (previousSize == newSize) return;
    lastViewportSize = newSize;
    pageViewportSize = newSize;
    if (contentLoader == null || !isPageMode) return;
    repaginateTimer?.cancel();
    repaginateTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted || !isPageMode) return;
      final trackedAnchor = modeSwitchAnchor ?? positionTracker.charOffset;
      final anchor =
          trackedAnchor > 0
              ? trackedAnchor
              : computePageCharOffset(pageModePage);
      repaginateCurrentChapter(restoreCharOffset: anchor);
    });
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
