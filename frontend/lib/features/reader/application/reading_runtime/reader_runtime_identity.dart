import 'package:flutter/foundation.dart';

/// 运行时身份（新方案 §57）：itemId + readingMode 构成恢复回调三层身份的
/// Runtime 侧载体；模式切换时由 Runtime 更新。
@immutable
class ReaderRuntimeIdentity {
  const ReaderRuntimeIdentity({
    required this.itemId,
    required this.readingMode,
  });

  final String itemId;

  final String readingMode;

  @override
  bool operator ==(Object other) =>
      other is ReaderRuntimeIdentity &&
      other.itemId == itemId &&
      other.readingMode == readingMode;

  @override
  int get hashCode => Object.hash(itemId, readingMode);
}
