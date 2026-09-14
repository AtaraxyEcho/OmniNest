import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/application/reading_runtime/reader_layout_revision.dart';

/// 位置事实快照（方案 §5）：整个新架构的核心事实对象。
///
/// 只描述位置事实（scrollOffset / contentY / chapter / block /
/// charOffset / visualCursor），不直接携带 Progress；Visual / Logical
/// Progress 由 ProgressProjection 从本对象纯派生（方案 §6）。
@immutable
class ReaderPositionSnapshot {
  const ReaderPositionSnapshot({
    required this.transactionId,
    required this.layoutRevision,
    required this.scrollOffset,
    required this.contentY,
    required this.chapterId,
    required this.blockIndex,
    required this.blockRatio,
    required this.charOffset,
    required this.chapterVisualCursor,
  });

  /// 产生本快照的事务 ID；无事务解析时为 0。
  final int transactionId;

  /// 本次解析使用的布局版本（方案 §26：必须与事务布局版本一致）。
  final ReaderLayoutRevision layoutRevision;

  final double scrollOffset;

  final double contentY;

  final String chapterId;

  final int blockIndex;

  final double blockRatio;

  final int charOffset;

  /// 章体视觉游标（前面块高度 + 当前块内偏移）。
  final double chapterVisualCursor;

  @override
  bool operator ==(Object other) =>
      other is ReaderPositionSnapshot &&
      other.transactionId == transactionId &&
      other.layoutRevision == layoutRevision &&
      other.scrollOffset == scrollOffset &&
      other.contentY == contentY &&
      other.chapterId == chapterId &&
      other.blockIndex == blockIndex &&
      other.blockRatio == blockRatio &&
      other.charOffset == charOffset &&
      other.chapterVisualCursor == chapterVisualCursor;

  @override
  int get hashCode => Object.hash(
    transactionId,
    layoutRevision,
    scrollOffset,
    contentY,
    chapterId,
    blockIndex,
    blockRatio,
    charOffset,
    chapterVisualCursor,
  );

  @override
  String toString() =>
      'ReaderPositionSnapshot(tx=$transactionId, '
      'rev=${layoutRevision.geometryRevision}/${layoutRevision.windowRevision}, '
      'offset=${scrollOffset.toStringAsFixed(1)}, chapter=$chapterId, '
      'block=$blockIndex, char=$charOffset)';
}
