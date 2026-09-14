import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/application/reading_runtime/reader_layout_revision.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// 布局快照（方案 §9）：几何 + 冻结视口构成一次事务的唯一坐标基准。
///
/// PositionResolver 只接受 LayoutSnapshot + scrollOffset，绝不自行访问
/// ScrollController / MediaQuery / currentChapterId / settings；同一
/// LayoutSnapshot 与同一 scrollOffset 必须产生相同 PositionSnapshot。
@immutable
class ReaderLayoutSnapshot {
  const ReaderLayoutSnapshot({
    required this.geometry,
    required this.viewport,
    required this.windowRevision,
  });

  /// 事务期间唯一可信几何（不可变快照）。
  final ReaderGeometrySnapshot geometry;

  /// 冻结的完整视口上下文。
  final ReaderViewportSnapshot viewport;

  /// 快照构建时的窗口结构版本号；几何版本来自 [geometry]。
  final int windowRevision;

  ReaderLayoutRevision get revision => ReaderLayoutRevision(
    geometryRevision: geometry.revision,
    windowRevision: windowRevision,
  );

  @override
  bool operator ==(Object other) =>
      other is ReaderLayoutSnapshot &&
      identical(other.geometry, geometry) &&
      other.viewport == viewport &&
      other.windowRevision == windowRevision;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(geometry), viewport, windowRevision);

  @override
  String toString() => 'ReaderLayoutSnapshot(${revision.toString()})';
}
