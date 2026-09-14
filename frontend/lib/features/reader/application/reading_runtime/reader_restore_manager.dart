import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_identity.dart';

/// Restore 相位（方案 §97）：超时/被打断后当前物理位置即事实，
/// 不得继续修改用户位置。
enum ReaderRestorePhase {
  /// 无恢复事务。
  idle,

  /// 目标 layout 未收敛，多帧重试中。
  applying,

  /// 位置已稳定，监控期（图片渐进加载等漂移）。
  stabilizing,

  /// 正常完成。
  completed,

  /// 被用户输入或新恢复取消。
  cancelled,

  /// 超时退出。
  timedOut,

  /// 定位异常退出。
  failed,
}

/// Restore 生命周期唯一权威（方案 §55 / §96）。
///
/// 所有恢复入口（章首恢复 / 进度快照恢复 / 搜索跳转 / 视觉 seek）都
/// 统一为 ReaderPositionTarget → [begin]；编排机械动作（多帧重试与
/// 监控）由 Runtime Facade 驱动（B6 §7.3），本类只持有目标、相位与
/// 发起身份，不再存在独立 generation / RestoreTransaction。
class ReaderRestoreManager {
  ReaderRestorePhase _phase = ReaderRestorePhase.idle;

  ReaderPositionTarget? _target;

  ReaderRuntimeIdentity? _identity;

  ReaderRestorePhase get phase => _phase;

  ReaderPositionTarget? get target => _target;

  /// 恢复进行中（§82 守卫语义的唯一读取口）：applying 含多帧重试，
  /// stabilizing 含监控期；恢复遮罩、位置回写抑制与模式切换守卫共用。
  bool get isBusy =>
      _phase == ReaderRestorePhase.applying ||
      _phase == ReaderRestorePhase.stabilizing;

  /// 发起一次恢复：登记目标与身份，相位进入 applying。
  ///
  /// 旧目标被清除；返回是否成功接管（调用方据此决定是否启动编排）。
  bool begin(ReaderPositionTarget target, {ReaderRuntimeIdentity? identity}) {
    _target = target;
    _identity = identity;
    _phase = ReaderRestorePhase.applying;
    return true;
  }

  /// 发起身份是否仍与 [identity] 一致（方案 §57 的 B6 侧替代：
  /// item/mode 已变的恢复不得回写 tracker）。
  bool matchesIdentity(ReaderRuntimeIdentity? identity) {
    if (_identity == null || identity == null) {
      return true;
    }
    return _identity == identity;
  }

  /// 取消当前恢复：applying/stabilizing 进入 cancelled 并清除目标；
  /// 已达终态（completed/timedOut/failed）或本就 idle 时保持原相位。
  void cancel() {
    if (_phase == ReaderRestorePhase.applying ||
        _phase == ReaderRestorePhase.stabilizing) {
      _phase = ReaderRestorePhase.cancelled;
      _target = null;
      _identity = null;
    }
  }

  /// 位置稳定进入监控期（引擎稳定判定后调用，方案 §97）。
  void markStabilizing() {
    if (_phase == ReaderRestorePhase.applying) {
      _phase = ReaderRestorePhase.stabilizing;
    }
  }

  /// 监控期正常结束。
  void markCompleted() {
    if (_phase == ReaderRestorePhase.stabilizing ||
        _phase == ReaderRestorePhase.applying) {
      _phase = ReaderRestorePhase.completed;
      _target = null;
      _identity = null;
    }
  }

  /// 总超时退出（方案 §97：超时后当前物理位置成为事实）。
  void markTimedOut() {
    _phase = ReaderRestorePhase.timedOut;
    _target = null;
    _identity = null;
  }

  /// 定位异常退出。
  void markFailed() {
    _phase = ReaderRestorePhase.failed;
    _target = null;
    _identity = null;
  }
}
