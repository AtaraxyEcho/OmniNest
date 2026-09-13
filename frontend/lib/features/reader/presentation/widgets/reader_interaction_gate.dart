/// 翻页输入阻塞原因；[none] 表示输入放行。
///
/// 统一对外判断入口，替代散落的阻塞布尔组合；原因枚举同时承担
/// 调试可观测职责（日志可表达"为什么不能翻页"）。
enum ReaderInteractionBlockReason {
  none,

  /// 切章锁定、章节内容加载或恢复定位进行中（PagedState.isPaginating）。
  chapterSwitching,

  /// 跨章边界请求（下一章/上一章硬切）进行中。
  boundaryTransition,

  /// 程序化翻页动画（cover/fade）进行中。
  pageAnimation,

  /// 翻页过渡收尾期：PointerUp 与 PageView ScrollStart 的时间竞态窗口。
  pageTransition,
}

/// 翻页输入闸门：把分散的阻塞布尔收口为单一原因判定。
///
/// 三条判定语义：
/// - 拖拽与外部命令：任何非 [ReaderInteractionBlockReason.none] 原因都阻塞。
/// - 点击热区翻页：放行 [ReaderInteractionBlockReason.pageTransition]。
///   指针按下时 PageView 拖拽识别器先赢得手势竞技场并派发 ScrollStart，
///   而原始 Listener 的 onPointerUp 早于该手势的结束处理执行，此刻过渡
///   标志仍为 true；若据此拦截点击，翻页会被自身按下动作产生的状态吞掉
///   （点击热区失效的根因）。
/// - PageView 拖拽 physics：仅切章与边界期整体锁死，动画/过渡不锁。
class ReaderInteractionGate {
  const ReaderInteractionGate._();

  /// 按优先级解析当前阻塞原因：加载 > 边界 > 动画 > 过渡 > 放行。
  static ReaderInteractionBlockReason resolve({
    required bool isPaginating,
    required bool boundaryRequestInFlight,
    required bool pageAnimationActive,
    required bool pageTransitionInFlight,
  }) {
    if (isPaginating) {
      return ReaderInteractionBlockReason.chapterSwitching;
    }
    if (boundaryRequestInFlight) {
      return ReaderInteractionBlockReason.boundaryTransition;
    }
    if (pageAnimationActive) {
      return ReaderInteractionBlockReason.pageAnimation;
    }
    if (pageTransitionInFlight) {
      return ReaderInteractionBlockReason.pageTransition;
    }
    return ReaderInteractionBlockReason.none;
  }

  /// 拖拽与外部翻页命令的闸门判定。
  static bool blocksInput(ReaderInteractionBlockReason reason) {
    return reason != ReaderInteractionBlockReason.none;
  }

  /// 点击热区翻页的闸门判定：仅放行过渡收尾窗口。
  static bool blocksTapTurn(ReaderInteractionBlockReason reason) {
    return reason != ReaderInteractionBlockReason.none &&
        reason != ReaderInteractionBlockReason.pageTransition;
  }

  /// PageView 拖拽 physics 的锁定判定：不把动画/过渡当作锁定原因。
  static bool locksScroll(ReaderInteractionBlockReason reason) {
    return reason == ReaderInteractionBlockReason.chapterSwitching ||
        reason == ReaderInteractionBlockReason.boundaryTransition;
  }
}
