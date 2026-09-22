import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';
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
///
/// 队列生命周期跟随登录账号：上传请求由当前会话 token 承载，换号后继续
/// 执行会把前一账号选择的文件导入新账号书架，因此在账号身份变化时取消
/// 全部进行中的本地任务并清空队列。已提交到服务端的任务不受影响，由后端
/// 按提交账号继续执行。
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
  String? _sessionUserId;

  @override
  List<ReaderImportJob> build() {
    final userId = ref.watch(
      authSessionProvider.select((value) => value.asData?.value.user?.id),
    );
    if (_sessionUserId != userId) {
      _sessionUserId = userId;
      _cancelAllJobs();
    }
    return const <ReaderImportJob>[];
  }

  /// 取消全部进行中的本地导入任务并清空队列簿记；不触碰服务端任务。
  void _cancelAllJobs() {
    for (final token in _cancellations.values) {
      token.cancel();
    }
    _cancellations.clear();
    for (final waiter in _completionWaiters.values) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _completionWaiters.clear();
    _pendingIds.clear();
    _runningIds.clear();
    _files.clear();
    // 目录 ID 属前一账号个人空间，换号后必须重新解析，避免新账号
    // 携旧目录 ID 发起上传。
    _readerDirectory = null;
  }

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
    // parentId 提升到方法级，供 catch 内的自愈轮询复用。
    String? parentId;
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
      parentId = await _readerDirectory;
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
      // 安全扫描受理失败时后端晋升与自动导入链仍可能完成：
      // 进入自愈轮询，按文件节点找回已导入的书，找回即视为成功。
      if (error is AppException &&
          error.code == AppErrorCodes.securityScanFailed) {
        var recovered = false;
        var cancelled = false;
        try {
          recovered = await _awaitLibraryRegistration(
            jobId,
            file,
            parentId,
            cancellation,
          );
        } on MediaImportCancelledException {
          cancelled = true;
        } on Object {
          recovered = false;
        }
        if (cancelled) {
          _remove(jobId);
          return;
        }
        if (recovered) {
          return;
        }
      }
      _update(
        jobId,
        (job) => job.copyWith(
          status: ReaderImportJobStatus.failed,
          errorMessage: _describeImportError(error),
        ),
      );
    } finally {
      _cancellations.remove(jobId);
    }
  }

  /// 安全扫描受理失败后的自愈轮询：后端晋升与自动导入完成即补齐书架。
  Future<bool> _awaitLibraryRegistration(
    String jobId,
    XFile file,
    String? parentId,
    MediaImportCancellationToken cancellation,
  ) async {
    final importService = ref.read(mediaImportServiceProvider);
    for (var attempt = 0; attempt < 60; attempt++) {
      if (!ref.mounted) return false;
      cancellation.throwIfCancelled();
      final node = await importService.findImportedNode(
        parentId: parentId,
        fileName: file.name,
        timeout: const Duration(seconds: 5),
      );
      if (!ref.mounted) return false;
      if (node == null) {
        continue;
      }
      final importedItem = await ref
          .read(readerApiProvider)
          .importFile(
            fileNodeId: node,
            contentKindOverride: _contentKind(file.name),
          );
      if (!ref.mounted) return false;
      ref.invalidate(textParseProgressProvider(importedItem.id));
      await ref.read(readerCenterControllerProvider.notifier).refresh();
      if (!ref.mounted) return false;
      _remove(jobId);
      return true;
    }
    return false;
  }

  /// 队列内无 BuildContext，优先展示异常自带的可读信息，再回退统一映射。
  String _describeImportError(Object error) {
    if (error is AppException) {
      final message = error.message;
      if (message.isNotEmpty && message != error.code) {
        return '$message（${error.code}）';
      }
    }
    return describeUserFacingError(error).displayMessage;
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
