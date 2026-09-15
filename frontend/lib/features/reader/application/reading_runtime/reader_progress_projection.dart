import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// 章体在全书视觉进度表中的锚点区间（方案 §46 全书尺度）。
///
/// [start]/[end] 为该章章体起始/结束位置对应的全书视觉进度；事务冻结
/// 映射携带锚点后，事务期发布的进度与空闲期全书视觉表同尺度。
@immutable
class ReaderChapterProgressAnchor {
  const ReaderChapterProgressAnchor({required this.start, required this.end});

  final double start;
  final double end;
}

/// 物理窗口 Y → 全书视觉进度的冻结映射（方案 §22-§24）。
///
/// 进度在每个章体内随物理 Y 线性（图片是零字符块但占据视觉高度，
/// 因此图片内部天然连续，不经过 charOffset）；区间来自几何快照，
/// 建立后不可变（方案 §53）。
///
/// [bookAnchors] 提供且覆盖全部窗口章时，章体区间映射到全书视觉
/// 进度（与 idle 全书视觉表同尺度）；未提供或任一章缺失时回退为
/// 窗口内相对进度——该回退仅供诊断与直构单测，发布路径必须带锚点。
@immutable
class ReaderVisualProgressMap {
  const ReaderVisualProgressMap({
    required this.chapterIds,
    required this.physicalStarts,
    required this.physicalEnds,
    required this.progressStarts,
    required this.progressEnds,
    required this.totalBodyExtent,
  });

  /// 窗口章节顺序。
  final List<String> chapterIds;

  /// 每章的物理区间（窗口坐标，章体 = 前缀 + 章头 → 前缀 + 章头 + 章体）。
  final List<double> physicalStarts;
  final List<double> physicalEnds;

  /// 每章对应的视觉进度区间（全书锚点或窗口相对回退）。
  final List<double> progressStarts;
  final List<double> progressEnds;

  final double totalBodyExtent;

  /// 从几何快照构建映射：章体物理区间与进度区间一一对应。
  factory ReaderVisualProgressMap.fromGeometry(
    ReaderGeometrySnapshot geometry, {
    Map<String, ReaderChapterProgressAnchor>? bookAnchors,
  }) {
    final useAnchors =
        bookAnchors != null &&
        geometry.chapterIds.every(bookAnchors.containsKey);
    final ids = <String>[];
    final physicalStarts = <double>[];
    final physicalEnds = <double>[];
    final progressStarts = <double>[];
    final progressEnds = <double>[];
    var bodyPrefix = 0.0;
    for (final id in geometry.chapterIds) {
      final chapter = geometry.chapterOf(id);
      if (chapter == null) {
        continue;
      }
      final header = ReaderContinuousScrollController.chapterHeaderExtent;
      final start = geometry.prefixOf(id) + header;
      final end = start + chapter.totalHeight;
      final total = geometry.totalBodyExtent;
      ids.add(id);
      physicalStarts.add(start);
      physicalEnds.add(end);
      if (useAnchors) {
        final anchor = bookAnchors[id]!;
        progressStarts.add(anchor.start.clamp(0.0, 1.0));
        progressEnds.add(anchor.end.clamp(0.0, 1.0));
      } else {
        progressStarts.add(
          total > 0 ? (bodyPrefix / total).clamp(0.0, 1.0) : 0.0,
        );
        progressEnds.add(
          total > 0
              ? ((bodyPrefix + chapter.totalHeight) / total).clamp(0.0, 1.0)
              : 0.0,
        );
      }
      bodyPrefix += chapter.totalHeight;
    }
    return ReaderVisualProgressMap(
      chapterIds: ids,
      physicalStarts: physicalStarts,
      physicalEnds: physicalEnds,
      progressStarts: progressStarts,
      progressEnds: progressEnds,
      totalBodyExtent: geometry.totalBodyExtent,
    );
  }

  /// 物理窗口 Y → 全书视觉进度；章头/章尾区间钳制到该章边缘进度。
  double? progressAt(double contentY) {
    if (chapterIds.isEmpty || totalBodyExtent <= 0) {
      return null;
    }
    var index = -1;
    for (var i = 0; i < chapterIds.length; i++) {
      if (contentY < physicalEnds[i] || i == chapterIds.length - 1) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      return null;
    }
    final start = physicalStarts[index];
    final end = physicalEnds[index];
    final span = end - start;
    final localRatio =
        span > 0 ? ((contentY - start) / span).clamp(0.0, 1.0) : 0.0;
    final progressSpan = progressEnds[index] - progressStarts[index];
    return (progressStarts[index] + localRatio * progressSpan).clamp(0.0, 1.0);
  }
}

/// 逻辑投影束（方案 §83 progress 字段的载体）。
///
/// 视觉进度不再有独立投影类：事务帧读事务冻结映射（tx.visualMap），
/// 无事务帧读全书视觉表兜底，均与发布值同源同尺度。
class ReaderProgressProjection {
  ReaderProgressProjection({ReaderLogicalProgressProjection? logical})
    : logical = logical ?? ReaderLogicalProgressProjection();

  final ReaderLogicalProgressProjection logical;
}

/// 逻辑投影（方案 §47）：charOffset / 所在章 totalChars，供持久化使用。
class ReaderLogicalProgressProjection {
  const ReaderLogicalProgressProjection();

  double project(
    ReaderPositionSnapshot position,
    ReaderGeometrySnapshot geometry,
  ) {
    final entry = geometry.chapterOf(position.chapterId);
    if (entry == null || entry.totalChars <= 0) {
      return 0.0;
    }
    return (position.charOffset / entry.totalChars).clamp(0.0, 1.0);
  }
}
