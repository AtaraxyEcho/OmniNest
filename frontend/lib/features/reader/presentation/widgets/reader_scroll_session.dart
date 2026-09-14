import 'package:omninest/features/reader/application/reading_runtime/reader_progress_projection.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

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
  final ReaderGeometrySnapshot geometry;

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
}
