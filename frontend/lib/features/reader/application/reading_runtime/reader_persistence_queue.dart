import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';

/// 持久化队列（新方案 §28/§30）：唯一输入是 Runtime committedPosition 投影
/// 出的进度快照；相邻同位置去重后交给页面注入的写入器（既有
/// ReaderProgressSaveCoordinator）合并落盘。Runtime 不直接执行 IO。
class ReaderPersistenceQueue {
  ReaderPersistenceQueue({
    required void Function(ReaderProgressSnapshot snapshot) onEnqueue,
  }) : _onEnqueue = onEnqueue;

  final void Function(ReaderProgressSnapshot snapshot) _onEnqueue;

  ReaderProgressSnapshot? _last;

  /// 最近一次入队的快照（观测面）。
  ReaderProgressSnapshot? get last => _last;

  /// 入队一份持久化快照；与上一份同章同偏移同进度时去重。
  void enqueue(ReaderProgressSnapshot snapshot) {
    final last = _last;
    if (last != null &&
        last.chapterId == snapshot.chapterId &&
        last.charOffset == snapshot.charOffset &&
        (last.progress - snapshot.progress).abs() < 1e-9) {
      return;
    }
    _last = snapshot;
    _onEnqueue(snapshot);
  }

  void reset() => _last = null;
}
