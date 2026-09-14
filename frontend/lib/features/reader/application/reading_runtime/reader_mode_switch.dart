import 'package:flutter/foundation.dart';

/// 模式切换请求（方案 §51/B7）：跨模式迁移的不可变意图数据。
///
/// 锚点在捕获时一次冻结进请求，是切换期定位与进度快照的共用数据，
/// 不再是页面的长期可变状态（原 modeSwitchAnchor 字段退役）。
@immutable
class ReaderModeSwitchRequest {
  const ReaderModeSwitchRequest({
    required this.fromMode,
    required this.toMode,
    required this.chapterId,
    required this.anchorCharOffset,
  });

  final String fromMode;

  final String toMode;

  final String chapterId;

  /// 切换捕获的精确章内锚点（滚动位置换算优先于 tracker）。
  final int anchorCharOffset;

  @override
  bool operator ==(Object other) =>
      other is ReaderModeSwitchRequest &&
      other.fromMode == fromMode &&
      other.toMode == toMode &&
      other.chapterId == chapterId &&
      other.anchorCharOffset == anchorCharOffset;

  @override
  int get hashCode =>
      Object.hash(fromMode, toMode, chapterId, anchorCharOffset);

  @override
  String toString() =>
      'ReaderModeSwitchRequest($fromMode→$toMode, $chapterId, '
      'anchor=$anchorCharOffset)';
}

/// 模式切换状态机（方案 §51/§96：Runtime 唯一权威）。
///
/// request 非 null 即切换活跃：切换期守卫（首次 onPageChanged 吞除、
/// 锚点未消耗时进度只展示不落库）与进度快照锚点均读此状态。请求由
/// 用户触摸（锚点消费）或目标模式定位完成终结，不设独立代次——异步
/// 定位回调经请求值比对判定是否仍代表当前切换。
class ReaderModeSwitchManager {
  ReaderModeSwitchRequest? _request;

  ReaderModeSwitchRequest? get request => _request;

  /// 切换是否活跃（原 modeSwitchInProgress 的唯一替代读口）。
  bool get isActive => _request != null;

  /// 发起切换：登记请求。新切换天然取代旧请求。
  void begin(ReaderModeSwitchRequest request) {
    _request = request;
  }

  /// 终结当前切换（定位完成或用户锚点消费）。
  void complete() {
    _request = null;
  }
}
