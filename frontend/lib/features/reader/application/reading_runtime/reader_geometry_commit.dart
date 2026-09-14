import 'package:omninest/features/reader/presentation/widgets/reader_continuous_position_resolver.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// 锚点保持修正计算（方案 §38/§70/§78）。
///
/// 提交边界与 Live 装载由 GeometryScheduler + WindowBuilder 决定（B5
/// §49）；本类只承载无状态的锚点重映射数学：在候选几何中重解锚点窗口
/// 坐标，返回相对旧布局的位移量。装载后必须用修正 offset 重新 Resolve
/// 出新 PositionSnapshot（方案 §40）。
class ReaderGeometryCommit {
  const ReaderGeometryCommit();

  /// 窗口变化后的锚点保持修正量（方案 §38/§70/§78）。
  ///
  /// 返回锚点在新几何中的窗口 contentY 相对旧布局的位移量；调用方以
  /// 「位移合成」方式叠加到当前 offset——用户在捕获与应用之间的滚动
  /// 已在当前 offset 中，按绝对目标回跳会撤销用户滚动（慢滚回拉根因）。
  /// 锚点在候选几何中不可解析时返回 null，调用方回退高度差补偿。
  double? computeAnchorCorrection({
    required ReaderGeometrySnapshot oldGeometry,
    required ReaderGeometrySnapshot candidate,
    required VisualAnchor anchor,
    required double anchorContentY,
  }) {
    final math = ReaderContinuousPositionResolver();
    final oldEntry = oldGeometry.chapterOf(anchor.chapterId)?.toEntry();
    final remapped = math.remapVisualPosition(
      VisualPosition(
        chapterId: anchor.chapterId,
        blockIndex: anchor.blockIndex,
        offsetInBlock: anchor.offsetInBlock,
        blockRatio: 0,
      ),
      oldEntry: oldEntry,
      source: SnapshotScrollGeometrySource(candidate),
    );
    if (remapped == null) {
      return null;
    }
    final newAnchorY = math.contentYForVisualPosition(
      remapped,
      source: SnapshotScrollGeometrySource(candidate),
    );
    if (newAnchorY == null) {
      return null;
    }
    return newAnchorY - anchorContentY;
  }
}
