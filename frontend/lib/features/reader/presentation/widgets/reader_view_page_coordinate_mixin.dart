import 'package:flutter/material.dart';

import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_mixin.dart';

/// 阅读页连续滚动窗口坐标换算与章首恢复（职责拆分自 ReaderViewPageMixin）。
///
/// 连续窗口结构为 [前章, 锚点章, 后章]，滚动 offset 0 是上一章顶部：
/// 所有窗口坐标 ↔ 章内坐标的换算必须经本 mixin 的统一入口，禁止调用
/// 方自行处理两套坐标系。
mixin ReaderViewPageCoordinateMixin on ReaderViewPageMixin {
  /// ScrollRestore 用户滚动探针：识别"进行中的拖动"。
  ///
  /// 只认恢复启动后的新手势（时间戳）会漏掉正在进行的拖动，恢复与用户
  /// 手指对抗；10s 兜底防止 up/cancel 被路由抢占导致标志永真。
  bool isUserScrollActive({required DateTime since}) {
    if (pointerDownActive &&
        DateTime.now().difference(lastPointerDownTime).inSeconds < 10) {
      return true;
    }
    return lastPointerDownTime.isAfter(since);
  }

  /// 窗口绝对 contentY（滚动 offset + viewportAnchorY）→ 章内 charOffset。
  ///
  /// 内部扣除前缀章与章头 chrome 后映射章体块坐标。
  @override
  int windowContentYToCharOffset(String chapterId, double windowContentY) {
    final loader = contentLoader;
    if (loader == null) {
      return 0;
    }
    final chapterBodyY =
        windowContentY -
        continuousScrollController.prefixHeightOf(chapterId) -
        ReaderContinuousScrollController.chapterHeaderExtent;
    if (chapterBodyY <= 0) {
      return 0;
    }
    return loader.contentYToCharOffset(
      chapterId,
      chapterBodyY,
      pageWidth: computePageWidth(),
      settings: settings,
      textScale: MediaQuery.textScalerOf(context).scale(1.0),
    );
  }

  /// 章首在窗口中的滚动 offset（章头贴视口顶）。
  @override
  double chapterStartScrollOffset(String chapterId) {
    return continuousScrollController
        .prefixHeightOf(chapterId)
        .clamp(0.0, double.infinity);
  }

  /// 滚动模式：将视口稳定恢复到章首（窗口坐标感知 + 多帧重试）。
  ///
  /// 懒布局下窗口重建当帧 maxScrollExtent 可能未收敛，单次 jumpTo 会被
  /// clamp 短跳；复用 ScrollRestore 的稳定重试。恢复期间 isRestoringProgress
  /// 抑制滚动位置回调，防止章首落点（窗口 offset≠0，前有前缀章）被位置
  /// 回调误收养回前章。恢复事务统一登记到 Runtime RestoreManager
  /// （方案 §55/§96），回调经三层身份校验（§57）。
  @override
  void restoreToChapterStart(String chapterId) {
    scrollProgress = 0;
    positionTracker.setCharOffset(0, chapterId);
    isRestoringProgress = true;
    restore.cancel();
    restoreSilenceUntil = DateTime.now().add(
      const Duration(milliseconds: ReaderViewPageMixin.restoreSilenceMs),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final restoreScheduledAt = DateTime.now();
      final restoreTx = beginRuntimeRestore(
        ReaderPositionTarget(chapterId: chapterId, charOffset: 0),
      );
      restore.start(
        scrollController: scrollController,
        targetOffsetBuilder: () {
          if (!scrollController.hasClients) return 0;
          final max = scrollController.position.maxScrollExtent;
          return chapterStartScrollOffset(chapterId).clamp(0.0, max);
        },
        isUserScrolling: () => isUserScrollActive(since: restoreScheduledAt),
        onSettled: (completed) {
          if (!completed) {
            // 被用户滚动中断：当前真实位置即事实，立即恢复进度写入。
            restoreSilenceUntil = DateTime.fromMillisecondsSinceEpoch(0);
          } else if (!runtime.restore.isCallbackValid(
            restoreTx,
            itemId: itemId,
            readingMode: settings.readingMode,
          )) {
            runtime.diagnostics.restoreCallbackDropCount++;
          }
          isRestoringProgress = false;
          if (mounted) setState(() {});
        },
      );
    });
  }
}
