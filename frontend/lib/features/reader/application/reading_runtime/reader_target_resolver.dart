import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_position_resolver.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// Target Authority（方案 §19-§20）：PositionTarget → 物理 scrollOffset
/// 的唯一解释器。
///
/// Restore / Bookmark / Search / 章节导航 / Visual Seek / 外部深链全部
/// 经此换算，不再各自维护目标算法（方案 §18/§20/§96）。
class ReaderTargetResolver {
  const ReaderTargetResolver();

  /// 解析目标对应的滚动 offset；目标章不在布局内或块级几何缺失时返回
  /// null，调用方按各自的事务策略失败退出，不得静默回退其他坐标。
  double? resolveScrollOffset({
    required ReaderPositionTarget target,
    required ReaderLayoutSnapshot layout,
  }) {
    final geometry = layout.geometry;
    if (!geometry.contains(target.chapterId)) {
      return null;
    }
    // 章首语义 = 章头 chrome 顶部贴锚线（与 chapterStartScrollOffset 同
    // 口径）：charOffset=0 映射章体顶会把章头甩出锚线上方。
    final double contentY;
    if (target.charOffset <= 0) {
      contentY = geometry.prefixOf(target.chapterId);
    } else {
      final math = ReaderContinuousPositionResolver();
      final resolved = math.contentYForLogicalPosition(
        target.chapterId,
        target.charOffset,
        source: SnapshotScrollGeometrySource(geometry),
      );
      if (resolved == null) {
        return null;
      }
      contentY = resolved;
    }
    return (contentY - layout.viewport.anchorY).clamp(0.0, double.infinity);
  }
}
