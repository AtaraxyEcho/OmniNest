import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// Geometry Authority（方案 §3.2 / §13）：Live / Candidate 两级几何的
/// 唯一生命周期所有者。
///
/// 后台加载、测高与扩窗只能产生 Candidate（方案 §44）；Candidate 在
/// commit 边界（idle / settling）才允许进入 Live，且到达顺序晚但版本
/// 旧的结果必须被丢弃（方案 §14 / §119）。
class ReaderGeometryStore {
  ReaderGeometrySnapshot? _live;
  ReaderGeometrySnapshot? _candidate;

  /// 当前生效几何；idle 解析允许读取（方案 §84）。
  ReaderGeometrySnapshot? get live => _live;

  /// 待提交几何；active 事务期间只允许累积，不允许污染事务布局。
  ReaderGeometrySnapshot? get candidate => _candidate;

  /// 读取 Live 几何；未初始化视为编程错误（方案 §13 requireLive）。
  ReaderGeometrySnapshot requireLive() {
    final value = _live;
    if (value == null) {
      throw StateError('Reader geometry has not been initialized');
    }
    return value;
  }

  /// 发布 Candidate：版本旧于当前 Candidate 时丢弃（方案 §14）。
  void publishCandidate(ReaderGeometrySnapshot geometry) {
    final current = _candidate;
    if (current != null && geometry.revision < current.revision) {
      return;
    }
    _candidate = geometry;
  }

  /// 在 commit 边界把 Candidate 提交为 Live；无 Candidate 时返回 false，
  /// 调用方直接做最终解析，不得为形式上的提交强行重建（方案 §69）。
  bool commitCandidate() {
    final candidate = _candidate;
    if (candidate == null) {
      return false;
    }
    _live = candidate;
    _candidate = null;
    return true;
  }

  void discardCandidate() {
    _candidate = null;
  }
}
