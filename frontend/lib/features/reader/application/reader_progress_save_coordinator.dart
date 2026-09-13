import 'dart:async';

import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';

/// 阅读进度写入函数。
typedef ReaderProgressWriter =
    Future<void> Function(ReaderProgressSnapshot snapshot);

/// 合并高频阅读进度并串行写入存储。
class ReaderProgressSaveCoordinator {
  ReaderProgressSaveCoordinator({
    required ReaderProgressWriter writer,
    this.debounce = const Duration(milliseconds: 900),
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _writer = writer,
       _onError = onError;

  final ReaderProgressWriter _writer;
  final Duration debounce;
  final void Function(Object error, StackTrace stackTrace)? _onError;

  Timer? _timer;
  ReaderProgressSnapshot? _pending;
  Future<void> _writeTail = Future<void>.value();
  bool _disposed = false;

  /// 记录最新进度，并从最后一次更新开始重新计时。
  void schedule(ReaderProgressSnapshot snapshot) {
    if (_disposed) {
      return;
    }
    _pending = snapshot;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(flush());
    });
  }

  /// 立即捕获当前待写入进度，并排入串行写入队列。
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final snapshot = _pending;
    _pending = null;
    if (snapshot == null) {
      return _writeTail;
    }
    _writeTail = _writeTail.then((_) => _write(snapshot)).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _onError?.call(error, stackTrace);
    });
    return _writeTail;
  }

  Future<void> _write(ReaderProgressSnapshot snapshot) async {
    await _writer(snapshot);
  }

  /// 停止计时器；可选择在释放前提交最后一条进度。
  Future<void> dispose({bool flushPending = true}) {
    if (_disposed) {
      return _writeTail;
    }
    if (flushPending) {
      final pendingWrite = flush();
      _disposed = true;
      return pendingWrite;
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    return _writeTail;
  }
}
