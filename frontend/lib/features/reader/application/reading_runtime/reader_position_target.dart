import 'package:flutter/foundation.dart';

/// 阅读位置目标（方案 §19）：Restore / Bookmark / Search / 章节导航 /
/// Visual Seek / 外部深链的统一意图表达。
///
/// 目标换算经恢复委托（ReaderRestoreDelegate.resolveRestoreOffset）：
/// charOffset>0 走 TextPainter 精度路径（§144），charOffset=0 语义为
/// 章首（章头贴视口顶）；布局未就绪返回 null 由编排多帧重试。
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
