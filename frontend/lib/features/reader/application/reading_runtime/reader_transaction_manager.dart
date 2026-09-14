import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction.dart';

/// 事务所有权唯一权威（方案 §3.3 / §24）。
///
/// 强制不变量（方案 §23 / §25 / §26）：
/// - 一个 Reader 实例最多一个 active 事务；
/// - 事务切换必须原子化（cancel 旧 + begin 新在同一同步状态转换内完成，
///   不产生 phase=active 且 transaction=null 的中间状态）；
/// - finish/cancel 只对当前事务生效，旧事务回调按 id 丢弃。
class ReaderTransactionManager {
  ReaderTransaction? _current;
  int _sequence = 0;

  ReaderTransaction? get current => _current;

  bool get hasActive => _current != null;

  /// 开始一个新事务；已有 active 事务时直接失败（方案 §24）。
  ///
  /// 调用方若无法静态保证无 active 事务，应使用 [beginOrReplace]。
  ReaderTransaction begin({
    required ReaderTransactionKind kind,
    required ReaderLayoutSnapshot layout,
    required double initialOffset,
    required double initialVisualProgress,
  }) {
    if (_current != null) {
      throw StateError('A Reader transaction is already active');
    }
    final tx = ReaderTransaction(id: ++_sequence, kind: kind, layout: layout);
    tx.lastScrollOffset = initialOffset;
    tx.lastVisualProgress = initialVisualProgress;
    tx.displayedProgress = initialVisualProgress;
    _current = tx;
    return tx;
  }

  /// 原子切换（方案 §25）：取消旧事务并开始新事务在同一同步转换内完成。
  ///
  /// 旧事务对象被标记为 cancelled，其后续回调可凭 phase 与 id 判定失效。
  ReaderTransaction beginOrReplace({
    required ReaderTransactionKind kind,
    required ReaderLayoutSnapshot layout,
    required double initialOffset,
    required double initialVisualProgress,
  }) {
    final previous = _current;
    if (previous != null) {
      previous.phase = ReaderTransactionPhase.cancelled;
    }
    final tx = ReaderTransaction(id: ++_sequence, kind: kind, layout: layout);
    tx.lastScrollOffset = initialOffset;
    tx.lastVisualProgress = initialVisualProgress;
    tx.displayedProgress = initialVisualProgress;
    _current = tx;
    return tx;
  }

  /// 完成当前事务（方案 §22：completed）；其他 id 的调用为 no-op。
  void finish(int transactionId) {
    final current = _current;
    if (current == null || current.id != transactionId) {
      return;
    }
    current.phase = ReaderTransactionPhase.completed;
    _current = null;
  }

  /// 取消当前事务（方案 §59：用户输入 / 新程序化动作使旧路径立即失效）。
  void cancelCurrent() {
    final current = _current;
    if (current == null) {
      return;
    }
    current.phase = ReaderTransactionPhase.cancelled;
    _current = null;
  }

  /// [transactionId] 是否仍为当前事务。
  bool isCurrent(int transactionId) => _current?.id == transactionId;
}
