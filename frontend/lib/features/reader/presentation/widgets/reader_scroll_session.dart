import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// 视口快照（方案 §7/§38）：会话期间冻结的 viewport 基准。
///
/// contentY = scrollOffset + anchorY 在整个会话期间使用同一 anchorY，
/// 窗口尺寸/沉浸式/SafeArea 变化不得在会话中途改变该换算。
@immutable
class ReaderViewportSnapshot {
  const ReaderViewportSnapshot({
    required this.viewportSize,
    required this.anchorY,
  });

  final Size viewportSize;
  final double anchorY;
}

/// 物理窗口 Y → 全书视觉进度的冻结映射（方案 §22-24）。
///
/// 进度在每个章体内随物理 Y 线性（图片是零字符块但占据视觉高度，
/// 因此图片内部天然连续，不经过 charOffset）；区间来自会话几何快照，
/// 建立后不可变（§53）。
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
    ReaderScrollGeometrySnapshot geometry,
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

/// 一次用户滚动手势的事务对象（方案 §9/§40-41）。
///
/// 会话期间几何、视口、进度映射、方向与显示进度全部属于同一事务，
/// 不得出现 Geometry Session / Visual Progress Session / Phase 三个
/// 生命周期的散落状态（§3）。
class ReaderScrollSession {
  ReaderScrollSession({
    required this.id,
    required this.geometry,
    required this.viewport,
    required this.visualMap,
    required this.initialScrollOffset,
    required this.initialVisualProgress,
  }) : lastScrollOffset = initialScrollOffset,
       lastVisualProgress = initialVisualProgress,
       displayedProgress = initialVisualProgress;

  /// 会话 ID：旧回调按 id 丢弃（方案 §45-46，生产模式同样丢弃）。
  final int id;

  /// 手势期间唯一可信几何。
  final ReaderScrollGeometrySnapshot geometry;

  /// 冻结的视口基准。
  final ReaderViewportSnapshot viewport;

  /// 冻结的物理 Y → 视觉进度映射。
  final ReaderVisualProgressMap visualMap;

  final double initialScrollOffset;
  final double initialVisualProgress;

  /// 滚动方向（以会话起始物理 offset 为基准，方案 §41）。
  bool forward = true;

  double lastScrollOffset;
  double lastVisualProgress;
  double displayedProgress;

  /// 会话期间挂起的窗口操作（方案 §31-32）：USER_DRAGGING/BALLISTIC
  /// 只记录，SETTLING 一次提交。
  String? pendingAnchorChapter;
  bool pendingExpandForward = false;
  bool pendingExpandBackward = false;
}
