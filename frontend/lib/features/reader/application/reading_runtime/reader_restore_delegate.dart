import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';

/// Restore 编排的页面供给（B6 §7.2）：Runtime 不持有 Controller 与
/// 内容数据，目标换算、用户滚动探针与稳定回写由页面实现注入。
abstract interface class ReaderRestoreDelegate {
  /// [target] → 窗口滚动 offset；布局或章节数据未就绪返回 null
  /// （引擎多帧重试，总超时兜底）。
  double? resolveRestoreOffset(ReaderPositionTarget target);

  /// 用户滚动判定（isUserScrollActive 包装）：恢复与进行中的用户手势
  /// 对抗时让位。
  bool isUserScrollingSince(DateTime since);

  /// 稳定回写（稳定 10 帧后调用）：页面记账至 Runtime 逻辑位置并触发
  /// 进度持久化与全书进度发布。
  void onRestoreSettled(ReaderPositionTarget target);
}
