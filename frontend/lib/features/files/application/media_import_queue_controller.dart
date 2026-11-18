import 'dart:async';
import 'dart:collection';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/features/files/application/media_import_service.dart';

final mediaImportQueueProvider =
    NotifierProvider<MediaImportQueueController, List<MediaImportQueueTask>>(
      MediaImportQueueController.new,
    );

enum MediaImportQueueStatus {
  queued,
  uploading,
  processing,
  completed,
  failed,
  cancelled,
}

class MediaImportQueueTask {
  const MediaImportQueueTask({
    required this.id,
    required this.title,
    required this.status,
    this.progress = 0,
    this.canRetry = false,
  });

  final String id;
  final String title;
  final MediaImportQueueStatus status;
  final double progress;
  final bool canRetry;

  bool get isActive =>
      status == MediaImportQueueStatus.queued ||
      status == MediaImportQueueStatus.uploading ||
      status == MediaImportQueueStatus.processing;

  bool get isFailed => status == MediaImportQueueStatus.failed;
}

typedef MediaImportQueueCompletion =
    FutureOr<void> Function(MediaImportBatchResult result);

class _MediaImportQueueBatch {
  _MediaImportQueueBatch({
    required this.id,
    required this.remaining,
    required this.onComplete,
  });

  final String id;
  final MediaImportQueueCompletion? onComplete;
  final List<ImportedMediaFile> imported = <ImportedMediaFile>[];
  final List<MediaImportFailure> failures = <MediaImportFailure>[];
  final List<String> taskIds = <String>[];
  int remaining;
}

class _MediaImportQueueWork {
  _MediaImportQueueWork({
    required this.id,
    required this.batchId,
    required this.file,
    required this.directoryName,
    required this.spaceType,
    required this.reuseExistingFiles,
    required this.cancellationToken,
  });

  final String id;
  final String batchId;
  final XFile file;
  final String directoryName;
  final String spaceType;
  final bool reuseExistingFiles;
  final MediaImportCancellationToken cancellationToken;
}

class _RetryableMediaImport {
  const _RetryableMediaImport({
    required this.file,
    required this.directoryName,
    required this.spaceType,
    required this.reuseExistingFiles,
    required this.onComplete,
  });

  final XFile file;
  final String directoryName;
  final String spaceType;
  final bool reuseExistingFiles;
  final MediaImportQueueCompletion? onComplete;
}

/// 桌面媒体设备导入沿用样例的队列反馈：导入弹窗关闭后继续上传，
/// 每个文件在任务面板独立显示状态，页面切换不会中断正在进行的上传。
class MediaImportQueueController extends Notifier<List<MediaImportQueueTask>> {
  static const int _workerLimit = 2;
  static const int _retainedTaskLimit = 40;

  final Queue<_MediaImportQueueWork> _pending = Queue<_MediaImportQueueWork>();
  final Map<String, _MediaImportQueueWork> _workById =
      <String, _MediaImportQueueWork>{};
  final Map<String, _RetryableMediaImport> _retryableById =
      <String, _RetryableMediaImport>{};
  final Map<String, _MediaImportQueueBatch> _batches =
      <String, _MediaImportQueueBatch>{};
  final Map<String, Future<String?>> _directories = <String, Future<String?>>{};
  int _activeWorkers = 0;
  int _sequence = 0;
  int? _sessionEpoch;

  int get activeCount => state.where((task) => task.isActive).length;

  int get failedCount => state.where((task) => task.isFailed).length;

  @override
  List<MediaImportQueueTask> build() {
    final sessionEpoch = ref.watch(sessionEpochProvider);
    if (_sessionEpoch != sessionEpoch) {
      _sessionEpoch = sessionEpoch;
      _cancelAll();
    }
    ref.onDispose(_cancelAll);
    return const <MediaImportQueueTask>[];
  }

  void enqueue({
    required List<XFile> files,
    required String directoryName,
    required String spaceType,
    required bool reuseExistingFiles,
    required String Function(XFile file) titleForFile,
    MediaImportQueueCompletion? onComplete,
  }) {
    if (!ref.mounted || files.isEmpty) return;

    final batchId = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    final batch = _MediaImportQueueBatch(
      id: batchId,
      remaining: files.length,
      onComplete: onComplete,
    );
    _batches[batchId] = batch;

    final nextTasks = <MediaImportQueueTask>[...state];
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final id = '$batchId-$index';
      final work = _MediaImportQueueWork(
        id: id,
        batchId: batchId,
        file: file,
        directoryName: directoryName,
        spaceType: spaceType,
        reuseExistingFiles: reuseExistingFiles,
        cancellationToken: MediaImportCancellationToken(),
      );
      _workById[id] = work;
      _pending.addLast(work);
      batch.taskIds.add(id);
      nextTasks.add(
        MediaImportQueueTask(
          id: id,
          title: titleForFile(file),
          status: MediaImportQueueStatus.queued,
        ),
      );
    }
    final trimmed = _trimTerminalTasks(nextTasks);
    final retainedIds = trimmed.map((task) => task.id).toSet();
    _retryableById.removeWhere((id, _) => !retainedIds.contains(id));
    state = trimmed;
    _drain();
  }

  void retry(String taskId) {
    final task = state.where((item) => item.id == taskId).firstOrNull;
    final retryable = _retryableById.remove(taskId);
    if (task?.canRetry != true || retryable == null || !ref.mounted) return;

    final batchId = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    final batch = _MediaImportQueueBatch(
      id: batchId,
      remaining: 1,
      onComplete: retryable.onComplete,
    )..taskIds.add(taskId);
    final work = _MediaImportQueueWork(
      id: taskId,
      batchId: batchId,
      file: retryable.file,
      directoryName: retryable.directoryName,
      spaceType: retryable.spaceType,
      reuseExistingFiles: retryable.reuseExistingFiles,
      cancellationToken: MediaImportCancellationToken(),
    );
    _batches[batchId] = batch;
    _workById[taskId] = work;
    _pending.addLast(work);
    _updateTask(
      taskId,
      MediaImportQueueStatus.queued,
      progress: 0,
      canRetry: false,
    );
    _drain();
  }

  void cancel(String taskId) {
    final work = _workById[taskId];
    if (work == null) return;
    work.cancellationToken.cancel();
    _retryableById.remove(taskId);
    final wasQueued = _pending.remove(work);
    if (wasQueued) {
      _updateTask(taskId, MediaImportQueueStatus.cancelled);
      unawaited(_settle(work));
    }
  }

  void _drain() {
    while (ref.mounted &&
        _activeWorkers < _workerLimit &&
        _pending.isNotEmpty) {
      final work = _pending.removeFirst();
      if (work.cancellationToken.isCancelled) continue;
      _activeWorkers++;
      unawaited(_run(work));
    }
  }

  Future<void> _run(_MediaImportQueueWork work) async {
    _updateTask(work.id, MediaImportQueueStatus.uploading);
    try {
      final importService = ref.read(mediaImportServiceProvider);
      final directoryKey = '${work.spaceType}:${work.directoryName}';
      final directoryFuture = _directories.putIfAbsent(
        directoryKey,
        () => importService.ensureDefaultDirectory(
          directoryName: work.directoryName,
          spaceType: work.spaceType,
        ),
      );
      String? parentId;
      try {
        parentId = await directoryFuture;
      } on Object {
        if (identical(_directories[directoryKey], directoryFuture)) {
          _directories.remove(directoryKey);
        }
        rethrow;
      }
      if (!ref.mounted) return;
      work.cancellationToken.throwIfCancelled();
      if (parentId == null || parentId.isEmpty) {
        if (identical(_directories[directoryKey], directoryFuture)) {
          _directories.remove(directoryKey);
        }
        throw StateError('Media import directory is unavailable');
      }

      final imported = await importService.importFile(
        file: work.file,
        parentId: parentId,
        spaceType: work.spaceType,
        reuseExistingFiles: work.reuseExistingFiles,
        cancellationToken: work.cancellationToken,
        onProgress: (_, uploadedBytes, totalBytes) {
          if (!ref.mounted) return;
          _updateTask(
            work.id,
            MediaImportQueueStatus.uploading,
            progress: totalBytes <= 0 ? 0 : uploadedBytes / totalBytes,
          );
        },
      );
      if (!ref.mounted) return;
      _batches[work.batchId]?.imported.add(imported);
      _retryableById.remove(work.id);
      _updateTask(work.id, MediaImportQueueStatus.processing, progress: 1);
    } on MediaImportCancelledException {
      if (ref.mounted) {
        _updateTask(work.id, MediaImportQueueStatus.cancelled);
      }
    } on Object catch (error) {
      if (ref.mounted) {
        final batch = _batches[work.batchId];
        if (batch != null) {
          _retryableById[work.id] = _RetryableMediaImport(
            file: work.file,
            directoryName: work.directoryName,
            spaceType: work.spaceType,
            reuseExistingFiles: work.reuseExistingFiles,
            onComplete: batch.onComplete,
          );
        }
        _batches[work.batchId]?.failures.add(
          MediaImportFailure(fileName: work.file.name, error: error),
        );
        _updateTask(work.id, MediaImportQueueStatus.failed, canRetry: true);
      }
    } finally {
      _activeWorkers--;
      if (ref.mounted) {
        await _settle(work);
        _drain();
      }
    }
  }

  Future<void> _settle(_MediaImportQueueWork work) async {
    final batch = _batches[work.batchId];
    if (batch == null) return;
    batch.remaining--;
    _workById.remove(work.id);
    if (batch.remaining > 0 || !ref.mounted) return;

    try {
      final imported = batch.imported;
      if (imported.isNotEmpty || batch.failures.isNotEmpty) {
        await batch.onComplete?.call(
          MediaImportBatchResult(
            imported: List<ImportedMediaFile>.unmodifiable(imported),
            failures: List<MediaImportFailure>.unmodifiable(batch.failures),
          ),
        );
      }
    } catch (error) {
      if (ref.mounted) {
        for (final taskId in batch.taskIds) {
          if (_statusFor(taskId) == MediaImportQueueStatus.processing) {
            _updateTask(taskId, MediaImportQueueStatus.failed, canRetry: false);
          }
        }
      }
    } finally {
      _batches.remove(batch.id);
      if (ref.mounted) {
        for (final taskId in batch.taskIds) {
          if (_statusFor(taskId) == MediaImportQueueStatus.processing) {
            _updateTask(taskId, MediaImportQueueStatus.completed, progress: 1);
          }
        }
      }
    }
  }

  MediaImportQueueStatus? _statusFor(String id) =>
      state.where((task) => task.id == id).firstOrNull?.status;

  void _updateTask(
    String id,
    MediaImportQueueStatus status, {
    double? progress,
    bool? canRetry,
  }) {
    if (!ref.mounted) return;
    state = [
      for (final task in state)
        if (task.id == id)
          MediaImportQueueTask(
            id: task.id,
            title: task.title,
            status: status,
            progress: (progress ?? task.progress).clamp(0, 1),
            canRetry: canRetry ?? task.canRetry,
          )
        else
          task,
    ];
  }

  List<MediaImportQueueTask> _trimTerminalTasks(
    List<MediaImportQueueTask> tasks,
  ) {
    if (tasks.length <= _retainedTaskLimit) return tasks;
    final active = tasks.where((task) => task.isActive).toList();
    final terminal = tasks.where((task) => !task.isActive).toList();
    final keepTerminal = _retainedTaskLimit - active.length;
    final terminalToKeep =
        keepTerminal < terminal.length ? keepTerminal : terminal.length;
    return <MediaImportQueueTask>[
      ...terminal.skip(terminal.length - terminalToKeep),
      ...active,
    ];
  }

  void _cancelAll() {
    for (final work in _workById.values) {
      work.cancellationToken.cancel();
    }
    _pending.clear();
    _workById.clear();
    _retryableById.clear();
    _batches.clear();
    _directories.clear();
  }
}
