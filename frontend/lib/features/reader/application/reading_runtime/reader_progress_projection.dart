import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// 物理窗口 Y → 全书视觉进度的冻结映射（方案 §22-§24）。
///
/// 进度在每个章体内随物理 Y 线性（图片是零字符块但占据视觉高度，
/// 因此图片内部天然连续，不经过 charOffset）；区间来自几何快照，
/// 建立后不可变（方案 §53）。
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

  /// 每章对应的全书视觉进度区间。
  final List<double> progressStarts;
  final List<double> progressEnds;

  final double totalBodyExtent;

  /// 从几何快照构建映射：章体物理区间与全书体累计进度一一对应。
  factory ReaderVisualProgressMap.fromGeometry(
    ReaderGeometrySnapshot geometry,
  ) {
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
      progressStarts.add(
        total > 0 ? (bodyPrefix / total).clamp(0.0, 1.0) : 0.0,
      );
      progressEnds.add(
        total > 0
            ? ((bodyPrefix + chapter.totalHeight) / total).clamp(0.0, 1.0)
            : 0.0,
      );
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

/// Visual / Logical Progress 投影束（方案 §83 progress 字段的载体）。
class ReaderProgressProjection {
  ReaderProgressProjection({
    ReaderVisualProgressProjection? visual,
    ReaderLogicalProgressProjection? logical,
  }) : visual = visual ?? ReaderVisualProgressProjection(),
       logical = logical ?? ReaderLogicalProgressProjection();

  final ReaderVisualProgressProjection visual;

  final ReaderLogicalProgressProjection logical;
}

/// 视觉投影（方案 §46）：PositionSnapshot + GeometrySnapshot → 全书
/// 视觉进度。
///
/// 数学必须是 contentY → 物理视觉位置 → 全书视觉进度；禁止用
/// charOffset / totalChars 代替（方案 §46）。同一几何实例重复投影时
/// 复用已构建的映射，避免热路径重复分配。
class ReaderVisualProgressProjection {
  ReaderGeometrySnapshot? _cacheSource;
  ReaderVisualProgressMap? _cachedMap;

  ReaderVisualProgressMap _mapFor(ReaderGeometrySnapshot geometry) {
    final cachedSource = _cacheSource;
    final cachedMap = _cachedMap;
    if (cachedMap != null && identical(cachedSource, geometry)) {
      return cachedMap;
    }
    final map = ReaderVisualProgressMap.fromGeometry(geometry);
    _cacheSource = geometry;
    _cachedMap = map;
    return map;
  }

  double project(
    ReaderPositionSnapshot position,
    ReaderGeometrySnapshot geometry,
  ) {
    if (geometry.totalBodyExtent <= 0 || geometry.chapterIds.isEmpty) {
      return 0.0;
    }
    final progress = _mapFor(geometry).progressAt(position.contentY);
    return (progress ?? 0.0).clamp(0.0, 1.0);
  }
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
