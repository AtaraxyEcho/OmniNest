import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_revision.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_position_resolver.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// Position Authority（方案 §3.1 / §16-§17）。
///
/// 唯一负责 scrollOffset → contentY → chapter → block → charOffset →
/// visualCursor 的解释；只接受 LayoutSnapshot + scrollOffset，绝不访问
/// ScrollController / MediaQuery / currentChapterId / settings，也不从
/// 任何外部可变 State 获取数据。换算数学委托给
/// [ReaderContinuousPositionResolver] 的快照路径，保证全工程只有一套
/// 位置解释实现（方案 §18）。
class ReaderPositionResolver {
  const ReaderPositionResolver();

  /// 确定性纯计算：same LayoutSnapshot + same scrollOffset =
  /// same PositionSnapshot（方案 §17 / §110）。
  ReaderPositionSnapshot? resolve({
    required double scrollOffset,
    required ReaderLayoutSnapshot layout,
    required int transactionId,
  }) {
    final contentY = scrollOffset + layout.viewport.anchorY;
    final math = ReaderContinuousPositionResolver();
    final resolved = math.resolveContentY(
      contentY,
      source: SnapshotScrollGeometrySource(layout.geometry),
    );
    if (resolved == null) {
      return null;
    }
    return ReaderPositionSnapshot(
      transactionId: transactionId,
      layoutRevision: ReaderLayoutRevision(
        geometryRevision: layout.geometry.revision,
        windowRevision: layout.windowRevision,
      ),
      scrollOffset: scrollOffset,
      contentY: resolved.contentY,
      chapterId: resolved.chapterId,
      blockIndex: resolved.visual.blockIndex,
      blockRatio: resolved.visual.blockRatio,
      charOffset: resolved.logical.charOffset,
      chapterVisualCursor: resolved.chapterVisualCursor,
    );
  }
}
