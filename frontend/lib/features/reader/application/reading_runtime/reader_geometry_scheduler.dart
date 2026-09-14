/// Geometry 提交调度（新方案 §25/§42/§49）：Candidate 随时可产生，何时
/// 进入 Live 由调度器决定——用户手势/滚动事务期间只挂起，终端提交
/// （settling/超时）时取最新兼容 Candidate；空闲时立即提交。
class ReaderGeometryScheduler {
  bool _pending = false;

  /// 是否存在被手势挂起的待提交 Candidate。
  bool get hasPendingCommit => _pending;

  /// [inActiveGesture] 为 true 时只挂起并返回 false（不得提交）；
  /// 否则返回 true（立即提交）。
  bool shouldCommitImmediately({required bool inActiveGesture}) {
    if (inActiveGesture) {
      _pending = true;
      return false;
    }
    return true;
  }

  /// 终端提交：返回是否存在被挂起的待提交，并清除标记。
  bool consumePendingCommit() {
    final pending = _pending;
    _pending = false;
    return pending;
  }

  void reset() => _pending = false;
}
