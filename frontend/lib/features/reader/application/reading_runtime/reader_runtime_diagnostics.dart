/// Runtime 观测事件（方案 §103）：实机日志按该分类输出，
/// 与 §126-§130 的日志验收格式对应。
enum ReaderRuntimeEventType {
  transactionStarted,

  transactionCancelled,

  positionResolved,

  candidateUpdated,

  windowRequested,

  settlingStarted,

  geometryCommitted,

  positionFinalized,

  progressPublished,

  restoreInvalidated,

  restoreFinished,

  transactionCompleted,
}

/// 单条观测事件负载（方案 §103）：每个事件携带事务与位置上下文。
class ReaderRuntimeEvent {
  const ReaderRuntimeEvent({
    required this.type,
    required this.at,
    this.transactionId = 0,
    this.kind,
    this.phase,
    this.layoutRevision,
    this.offset,
    this.chapterId,
    this.blockIndex,
    this.charOffset,
    this.visualProgress,
    this.logicalProgress,
  });

  final ReaderRuntimeEventType type;

  final DateTime at;

  final int transactionId;

  final String? kind;

  final String? phase;

  final String? layoutRevision;

  final double? offset;

  final String? chapterId;

  final int? blockIndex;

  final int? charOffset;

  final double? visualProgress;

  final double? logicalProgress;
}

/// Debug 诊断计数器（方案 §104）：全部目标为 0（§105-§108 断言的观测面）。
class ReaderRuntimeDiagnostics {
  int geometryCommitCount = 0;

  int stalePositionDropCount = 0;

  int restoreCallbackDropCount = 0;

  int liveGeometryReadDuringTransaction = 0;

  int duplicateProgressWriteCount = 0;

  int transactionConflictCount = 0;

  void reset() {
    geometryCommitCount = 0;
    stalePositionDropCount = 0;
    restoreCallbackDropCount = 0;
    liveGeometryReadDuringTransaction = 0;
    duplicateProgressWriteCount = 0;
    transactionConflictCount = 0;
  }
}
