import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';

/// Runtime 事件日志（方案 §103/§126）：环形缓冲按序记录生命周期事件，
/// 供实机按 §126-§130 格式验收（禁止出现 idle+session、visual 与
/// displayed 分叉、geometry 越过 commit 跳变等日志形态）。
class ReaderRuntimeEventLog {
  ReaderRuntimeEventLog({this.capacity = 512});

  final int capacity;

  final List<ReaderRuntimeEvent> _events = [];

  int _dropped = 0;

  void emit(ReaderRuntimeEvent event) {
    _events.add(event);
    if (_events.length > capacity) {
      _events.removeAt(0);
      _dropped++;
    }
  }

  List<ReaderRuntimeEvent> get events => List.unmodifiable(_events);

  int get droppedCount => _dropped;

  void clear() {
    _events.clear();
    _dropped = 0;
  }

  /// §126 日志格式：ReaderTransaction / ReaderPosition / ReaderGeometry /
  /// ReaderProgress 四类行。
  String format(ReaderRuntimeEvent e) {
    switch (e.type) {
      case ReaderRuntimeEventType.transactionStarted:
        return 'ReaderTransaction: tx=${e.transactionId} started kind=${e.kind}';
      case ReaderRuntimeEventType.transactionCancelled:
        return 'ReaderTransaction: tx=${e.transactionId} cancelled kind=${e.kind}';
      case ReaderRuntimeEventType.transactionCompleted:
        return 'ReaderTransaction: tx=${e.transactionId} completed kind=${e.kind}';
      case ReaderRuntimeEventType.settlingStarted:
        return 'ReaderTransaction: tx=${e.transactionId} settling';
      case ReaderRuntimeEventType.positionResolved:
        return 'ReaderPosition: tx=${e.transactionId} '
            'geometry=${e.layoutRevision} '
            'offset=${e.offset?.toStringAsFixed(1)} '
            'chapter=${e.chapterId} block=${e.blockIndex} char=${e.charOffset} '
            'visual=${e.visualProgress?.toStringAsFixed(4)} '
            'logical=${e.logicalProgress?.toStringAsFixed(4)}';
      case ReaderRuntimeEventType.candidateUpdated:
        return 'ReaderGeometry: candidate=${e.layoutRevision}';
      case ReaderRuntimeEventType.windowRequested:
        return 'ReaderWindow: requested forward=${e.blockIndex}';
      case ReaderRuntimeEventType.geometryCommitted:
        return 'ReaderGeometry: tx=${e.transactionId} commit geometry=${e.layoutRevision}';
      case ReaderRuntimeEventType.positionFinalized:
        return 'ReaderPosition: tx=${e.transactionId} finalized geometry=${e.layoutRevision}';
      case ReaderRuntimeEventType.progressPublished:
        return 'ReaderProgress: tx=${e.transactionId} visual=${e.visualProgress?.toStringAsFixed(4)}';
      case ReaderRuntimeEventType.restoreInvalidated:
        return 'ReaderRestore: invalidated generation=${e.charOffset}';
    }
  }
}
