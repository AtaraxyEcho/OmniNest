/// Geometry 提交调度（新方案 §25/§42/§49）：Candidate 随时可产生，何时
/// 进入 Live 由调度器单点决定——用户手势期间只登记挂起并拒绝装载，
/// 终端提交（settle 旁路）与空闲边界总是放行，取最新状态一次装载；
/// 挂起随终端消费清零。
class ReaderGeometryScheduler {
  bool _pending = false;

  /// 是否存在被手势挂起的待装载 Candidate。
  bool get hasPendingCommit => _pending;

  /// 装载边界决策（§49）。
  ///
  /// [inActiveGesture] 且非终端边界时登记挂起并返回 false（不得装载）；
  /// 终端边界（[terminal] = settle 旁路构建）或空闲边界返回 true，装载
  /// 即取当前最新状态——滚动中多份中间 Candidate 由终端一次收敛。
  bool authorizeInstall({
    required bool inActiveGesture,
    bool terminal = false,
  }) {
    if (inActiveGesture && !terminal) {
      _pending = true;
      return false;
    }
    return true;
  }

  /// 终端消费：返回是否存在被挂起的待装载，并清除标记。
  bool consumePendingCommit() {
    final pending = _pending;
    _pending = false;
    return pending;
  }

  void reset() => _pending = false;
}
