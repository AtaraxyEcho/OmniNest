import 'package:flutter/foundation.dart';

/// 布局版本（方案 §7）。
///
/// [geometryRevision] 表达块 / 章 / 高度 / 前缀等几何变化；
/// [windowRevision] 表达窗口结构变化（例如 A B C → A B C D）。
/// 两者共同构成一次位置解析的完整布局上下文版本。
@immutable
class ReaderLayoutRevision {
  const ReaderLayoutRevision({
    required this.geometryRevision,
    required this.windowRevision,
  });

  final int geometryRevision;

  final int windowRevision;

  @override
  bool operator ==(Object other) =>
      other is ReaderLayoutRevision &&
      other.geometryRevision == geometryRevision &&
      other.windowRevision == windowRevision;

  @override
  int get hashCode => Object.hash(geometryRevision, windowRevision);

  @override
  String toString() =>
      'ReaderLayoutRevision($geometryRevision/$windowRevision)';
}
