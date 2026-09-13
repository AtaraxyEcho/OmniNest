import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/files/application/media_import_service.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';

enum ReaderImportJobStatus { queued, uploading, registering, failed, cancelled }

class ReaderImportJob {
  const ReaderImportJob({
    required this.id,
    required this.fileName,
    required this.status,
    this.progress = 0,
    this.errorMessage,
  });

  final String id;
  final String fileName;
  final ReaderImportJobStatus status;
  final double progress;
  final String? errorMessage;

  ReaderImportJob copyWith({
    ReaderImportJobStatus? status,
    double? progress,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ReaderImportJob(
      id: id,
      fileName: fileName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final readerImportQueueProvider =
    NotifierProvider<ReaderImportQueueController, List<ReaderImportJob>>(
      ReaderImportQueueController.new,
    );

/// 阅读上传流程由 application 层持有，页面离开不会造成失效的 WidgetRef 访问。
class ReaderImportQueueController extends Notifier<List<ReaderImportJob>> {
  static const int _maxConcurrentImports = 3;
  final Map<String, XFile> _files = <String, XFile>{};
  final Map<String, MediaImportCancellationToken> _cancellations =
      <String, MediaImportCancellationToken>{};
  final Set<String> _pendingIds = <String>{};
  final Set<String> _runningIds = <String>{};
  final Map<String, Completer<void>> _completionWaiters =
      <String, Completer<void>>{};
  Future<String?>? _readerDirectory;
  int _sequence = 0;

  @override
  List<ReaderImportJob> build() => const <ReaderImportJob>[];

  void enqueue(List<XFile> files) {
    if (files.isEmpty) return;
    final jobs = <ReaderImportJob>[];
    for (final file in files) {
      final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
      _files[id] = file;
      jobs.add(
        ReaderImportJob(
          id: id,
          fileName: file.name,
          status: ReaderImportJobStatus.queued,
        ),
      );
    }
    state = <ReaderImportJob>[...state, ...jobs];
    _pendingIds.addAll(jobs.map((job) => job.id));
    _pump();
  }

  Future<void> retry(String jobId) async {
    if (!_files.containsKey(jobId)) return;
    final existingWaiter = _completionWaiters[jobId];
    if (existingWaiter != null) {
      await existingWaiter.future;
      return;
    }
    final waiter = Completer<void>();
    _completionWaiters[jobId] = waiter;
    _update(
      jobId,
      (job) => job.copyWith(
        status: ReaderImportJobStatus.queued,
        progress: 0,
        clearError: true,
      ),
    );
    _pendingIds.add(jobId);
    _pump();
    await waiter.future;
  }

  Future<void> cancel(String jobId) async {
    _cancellations[jobId]?.cancel();
    _update(
      jobId,
      (job) => job.copyWith(status: ReaderImportJobStatus.cancelled),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _remove(jobId);
  }

  void dismiss(String jobId) => _remove(jobId);

  void _pump() {
    while (_runningIds.length < _maxConcurrentImports &&
        _pendingIds.isNotEmpty) {
      final jobId = _pendingIds.first;
      _pendingIds.remove(jobId);
      if (!_files.containsKey(jobId)) continue;
      _runningIds.add(jobId);
      unawaited(
        _run(jobId).whenComplete(() {
          _runningIds.remove(jobId);
          final waiter = _completionWaiters.remove(jobId);
          if (waiter != null && !waiter.isCompleted) {
            waiter.complete();
          }
          _pump();
        }),
      );
    }
  }

  Future<void> _run(String jobId) async {
    final file = _files[jobId];
    if (file == null) return;
    final cancellation = MediaImportCancellationToken();
    _cancellations[jobId] = cancellation;
    try {
      _update(
        jobId,
        (job) => job.copyWith(
          status: ReaderImportJobStatus.uploading,
          clearError: true,
        ),
      );
      _readerDirectory ??= ref
          .read(mediaImportServiceProvider)
          .ensureDefaultDirectory(
            directoryName: 'Reader',
            spaceType: 'PERSONAL',
          );
      final parentId = await _readerDirectory;
      if (!ref.mounted) return;
      if (parentId == null) throw StateError('Reader directory unavailable');
      cancellation.throwIfCancelled();
      final uploaded = await ref
          .read(mediaImportServiceProvider)
          .importFile(
            file: file,
            parentId: parentId,
            spaceType: 'PERSONAL',
            reuseExistingFiles: true,
            cancellationToken: cancellation,
            onProgress: (_, uploadedBytes, totalBytes) {
              _update(
                jobId,
                (job) => job.copyWith(
                  status: ReaderImportJobStatus.uploading,
                  progress: totalBytes <= 0 ? 0 : uploadedBytes / totalBytes,
                ),
              );
            },
          );
      if (!ref.mounted) return;
      cancellation.throwIfCancelled();
      _update(
        jobId,
        (job) => job.copyWith(
          status: ReaderImportJobStatus.registering,
          progress: 1,
        ),
      );
      final importedItem = await ref
          .read(readerApiProvider)
          .importFile(
            fileNodeId: uploaded.fileNodeId,
            contentKindOverride: _contentKind(file.name),
          );
      if (!ref.mounted) return;
      ref.invalidate(textParseProgressProvider(importedItem.id));
      await ref.read(readerCenterControllerProvider.notifier).refresh();
      if (!ref.mounted) return;
      _remove(jobId);
    } on MediaImportCancelledException {
      _remove(jobId);
    } on Object catch (error) {
      _update(
        jobId,
        (job) => job.copyWith(
          status: ReaderImportJobStatus.failed,
          errorMessage: describeUserFacingError(error).displayMessage,
        ),
      );
    } finally {
      _cancellations.remove(jobId);
    }
  }

  String? _contentKind(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.cbz') || lower.endsWith('.zip')) return 'COMIC';
    if (lower.endsWith('.txt') || lower.endsWith('.pdf')) return 'TEXT';
    return null;
  }

  void _update(
    String jobId,
    ReaderImportJob Function(ReaderImportJob job) update,
  ) {
    if (!ref.mounted) return;
    state = <ReaderImportJob>[
      for (final job in state)
        if (job.id == jobId) update(job) else job,
    ];
  }

  void _remove(String jobId) {
    _pendingIds.remove(jobId);
    if (ref.mounted) {
      state = state.where((job) => job.id != jobId).toList(growable: false);
    }
    _files.remove(jobId);
    _cancellations.remove(jobId)?.cancel();
    final waiter = _completionWaiters.remove(jobId);
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }
}
