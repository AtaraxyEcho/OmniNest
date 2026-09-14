import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';

/// Restore 事务（方案 §56）：generation + item/mode 身份 + 目标 + 冻结布局。
@immutable
class ReaderRestoreTransaction {
  const ReaderRestoreTransaction({
    required this.generation,
    required this.itemId,
    required this.readingMode,
    required this.target,
    required this.layout,
  });

  final int generation;

  final String itemId;

  final String readingMode;

  final ReaderPositionTarget target;

  final ReaderLayoutSnapshot layout;

  /// 三层身份校验（方案 §57）：generation 由 RestoreManager 判定，
  /// itemId 与 readingMode 由回调方逐次校验，任一不符即丢弃回调。
  bool matchesIdentity({required String itemId, required String readingMode}) {
    return this.itemId == itemId && this.readingMode == readingMode;
  }
}
