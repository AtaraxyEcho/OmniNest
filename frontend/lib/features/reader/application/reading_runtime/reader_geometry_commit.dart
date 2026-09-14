import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/application/reading_runtime/reader_transaction.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_position_resolver.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// Geometry Commit 结果（方案 §38）。
@immutable
class ReaderGeometryCommitResult {
  const ReaderGeometryCommitResult({
    required this.geometry,
    required this.correctedOffset,
  });

  /// 本次提交后生效的新几何。
  final ReaderGeometrySnapshot geometry;

  /// 按视觉锚点重映射后的修正滚动 offset；锚点不可解析时为 null，
  /// 调用方回退高度差补偿，不得静默跳过（方案 §78）。
  final double? correctedOffset;
}

/// 结束性 Geometry Commit（方案 §38-§40）。
///
/// 一次 Commit 包含：Candidate → 锚点捕获 → 新几何重映射 → 修正
/// offset → Live；不是调用一次窗口重建就算完成。每个 Scroll Transaction
/// 最多一次结束性 Commit（方案 §68 / §107），Commit 后必须用修正 offset
/// 重新 Resolve 出新 PositionSnapshot（方案 §40）。
class ReaderGeometryCommit {
  const ReaderGeometryCommit();

  ReaderGeometryCommitResult commit({
    required ReaderTransaction transaction,
    required ReaderGeometrySnapshot candidate,
  }) {
    if (transaction.geometryCommitted) {
      throw StateError(
        'Geometry has already been committed for transaction '
        '${transaction.id}',
      );
    }

    final anchorY = transaction.layout.viewport.anchorY;
    final contentY = transaction.lastScrollOffset + anchorY;
    final oldGeometry = transaction.layout.geometry;
    final math = ReaderContinuousPositionResolver();
    final anchor = math.visualAtContentY(
      contentY,
      source: SnapshotScrollGeometrySource(oldGeometry),
    );

    double? correctedOffset;
    if (anchor != null) {
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
      if (remapped != null) {
        final anchorContentY = math.contentYForVisualPosition(
          remapped,
          source: SnapshotScrollGeometrySource(candidate),
        );
        if (anchorContentY != null) {
          correctedOffset = (anchorContentY - anchorY).clamp(
            0.0,
            double.infinity,
          );
        }
      }
    }

    transaction.geometryCommitted = true;

    return ReaderGeometryCommitResult(
      geometry: candidate,
      correctedOffset: correctedOffset,
    );
  }
}
