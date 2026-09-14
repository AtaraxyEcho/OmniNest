import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_transaction.dart';

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
/// 所有恢复入口（restoreToChapterStart / 进度快照恢复 / 模式切换恢复 /
/// 锚点恢复）都必须统一为 ReaderPositionTarget → RestoreTransaction；
/// 不再存在多个 restore.start 入口（方案 §96 / §144）。generation 单调
/// 递增：新恢复或取消都会使旧回调全部失效（方案 §14/§120）。
class ReaderRestoreManager {
  int _generation = 0;

  ReaderRestoreTransaction? _current;

  ReaderRestorePhase _phase = ReaderRestorePhase.idle;

  ReaderRestoreTransaction? get current => _current;

  int get generation => _generation;

  ReaderRestorePhase get phase => _phase;

  ReaderRestoreTransaction begin({
    required ReaderPositionTarget target,
    required ReaderLayoutSnapshot layout,
    required String itemId,
    required String readingMode,
  }) {
    _generation++;
    final tx = ReaderRestoreTransaction(
      generation: _generation,
      itemId: itemId,
      readingMode: readingMode,
      target: target,
      layout: layout,
    );
    _current = tx;
    _phase = ReaderRestorePhase.applying;
    return tx;
  }

  /// [generation] 是否仍为当前恢复事务（方案 §58：所有回调必查）。
  bool isCurrent(int generation) {
    return generation == _generation && _current != null;
  }

  /// 当前回调是否仍然有效：generation + item/mode 身份双层校验
  /// （方案 §57）。
  bool isCallbackValid(
    ReaderRestoreTransaction tx, {
    required String itemId,
    required String readingMode,
  }) {
    return identical(_current, tx) &&
        tx.matchesIdentity(itemId: itemId, readingMode: readingMode);
  }

  /// 取消当前恢复：generation 前进，在途回调全部失效（方案 §59）。
  void cancel() {
    _generation++;
    if (_current != null) {
      _phase = ReaderRestorePhase.cancelled;
    }
    _current = null;
  }

  /// 位置稳定进入监控期（引擎 settle(true) 后调用，方案 §97）。
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
    }
  }

  /// 总超时退出（方案 §97：超时后当前物理位置成为事实）。
  void markTimedOut() {
    _phase = ReaderRestorePhase.timedOut;
  }

  /// 定位异常退出。
  void markFailed() {
    _phase = ReaderRestorePhase.failed;
  }

  // ── Restore 请求与守卫状态（方案 §96/§140：所有权自页面 State 迁入）──

  /// 恢复静默窗截止时刻（§60 过渡期兼容语义）：期间位置回调不回写
  /// 进度，防止恢复 jumpTo 与进度守卫互相污染。
  DateTime silenceUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// 待恢复章内 charOffset（build 期登记，postFrame 消费）。
  int? pendingCharOffset;

  /// 待恢复章内进度比例（charOffset 未就绪时的降级恢复目标）。
  double? pendingChapterProgress;

  /// 恢复进行中：恢复遮罩显示与进度写入守卫共用（§82 守卫语义，
  /// 遮罩渲染仍属 UI 层）。
  bool isRestoring = false;

  /// [now] 是否仍处于恢复静默窗内。
  bool isSilenced(DateTime now) => now.isBefore(silenceUntil);
}
