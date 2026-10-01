import 'package:flutter/widgets.dart';

/// 无限滚动触发器：监听后代垂直滚动，距底部 [threshold] 像素内触发
/// [onLoadMore]。
///
/// 并发与终止纪律：
/// - [enabled] 为 false（加载中或已到末页）时不触发；调用方应在
///   isLoadingMore / hasMore 变化时同步该开关。
/// - 内置 200ms 时间节流：滚动通知高频连发时不会重复触发，与
///   [enabled] 开关构成双保险。
/// - 触发后是否继续、失败重试由调用方状态机决定；本组件自身不持有
///   加载状态。
///
/// 预期用法（瀑布流/网格/长列表统一约定）：
/// ```dart
/// InfiniteScrollTrigger(
///   threshold: 600,
///   enabled: !controller.isLoadingMore && controller.hasMore,
///   onLoadMore: controller.loadMore,
///   child: gridView,
/// )
/// ```
class InfiniteScrollTrigger extends StatefulWidget {
  const InfiniteScrollTrigger({
    required this.onLoadMore,
    required this.child,
    this.enabled = true,
    this.threshold = 600,
    super.key,
  });

  /// 距底触发阈值（像素）：统一 600，预留一屏渲染余量实现无感续页。
  final double threshold;

  /// 加载门闩：加载中或无更多数据时置 false。
  final bool enabled;

  /// 触发加载下一页；实现方需自幂等（重复调用不重复请求）。
  final VoidCallback onLoadMore;

  final Widget child;

  @override
  State<InfiniteScrollTrigger> createState() => _InfiniteScrollTriggerState();
}

class _InfiniteScrollTriggerState extends State<InfiniteScrollTrigger> {
  DateTime _lastTriggered = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!widget.enabled || notification.depth != 0) {
          return false;
        }
        if (notification is! ScrollUpdateNotification &&
            notification is! UserScrollNotification) {
          return false;
        }
        final metrics = notification.metrics;
        if (metrics.axis != Axis.vertical) {
          return false;
        }
        // 无界/未附着布局（shrinkWrap 计算阶段）不触发。
        if (!metrics.maxScrollExtent.isFinite || metrics.maxScrollExtent <= 0) {
          return false;
        }
        if (metrics.extentAfter > widget.threshold) {
          return false;
        }
        final now = DateTime.now();
        if (now.difference(_lastTriggered).inMilliseconds < 200) {
          return false;
        }
        _lastTriggered = now;
        widget.onLoadMore();
        return false;
      },
      child: widget.child,
    );
  }
}
