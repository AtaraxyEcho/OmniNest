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
  /// 恢复引擎用户滚动探针：识别"进行中的拖动"。
  ///
  /// 只认恢复启动后的新手势（时间戳）会漏掉正在进行的拖动，恢复与用户
  /// 手指对抗；10s 兜底防止 up/cancel 被路由抢占导致标志永真。
  @override
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
  /// clamp 短跳；恢复引擎（B6 §7.3）逐帧重算目标并稳定判定。恢复期间
  /// isBusy 投影抑制位置回调，防止章首落点（窗口 offset≠0，前有前缀章）
  /// 被位置回调误收养回前章。
  @override
  void restoreToChapterStart(String chapterId) {
    scrollProgress = 0;
    positionTracker.setCharOffset(0, chapterId);
    runtime.startRestore(
      ReaderPositionTarget(chapterId: chapterId, charOffset: 0),
    );
  }
}
