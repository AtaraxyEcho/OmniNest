import 'package:flutter/foundation.dart';

/// 阅读位置目标（方案 §19）：Restore / Bookmark / Search / 章节导航 /
/// Visual Seek / 外部深链的统一意图表达。
///
/// 所有路径都收敛为 Intent → PositionTarget → TargetResolver →
/// scrollOffset，不再各自维护一套目标换算算法。
@immutable
class ReaderPositionTarget {
  const ReaderPositionTarget({
    required this.chapterId,
    required this.charOffset,
  });

  final String chapterId;

  /// 章内字符偏移；0 表示章首（含章头 chrome）。
  final int charOffset;

  @override
  bool operator ==(Object other) =>
      other is ReaderPositionTarget &&
      other.chapterId == chapterId &&
      other.charOffset == charOffset;

  @override
  int get hashCode => Object.hash(chapterId, charOffset);

  @override
  String toString() => 'ReaderPositionTarget($chapterId, $charOffset)';
}
