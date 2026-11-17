part of 'file_browser_controller.dart';

/// 上传动作的私有类型：`_UploadFileResult` 是单文件上传的结局，
/// `_UploadRuntime` 是分片上传的运行时状态。二者只服务上传流程，
/// 随上传动作一起放在本分片，控制器主文件只保留状态编排。
enum _UploadFileResult { completed, conflict, failed, paused, cancelled }

class _UploadRuntime {
  _UploadRuntime({
    required this.file,
    required this.session,
    this.asVersionOfFileId,
  });

  final XFile file;
  FileUploadSession session;

  /// 非空时完成上传后保存为目标文件的新版本，不新建文件节点。
  final String? asVersionOfFileId;
  final Set<int> completedPartNumbers = <int>{};
  bool pauseRequested = false;
  bool removed = false;
  bool running = false;
  bool completed = false;

  /// 并发分片同时上传时每个分片各有一张取消令牌。
  final Set<FileUploadCancellationToken> activeCancellations =
      <FileUploadCancellationToken>{};

  /// 在途分片已发送的字节数，用于把并发进度汇总成单条任务进度。
  final Map<int, int> inFlightBytes = <int, int>{};
  DateTime lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
  int lastReportedBytes = 0;

  int get inFlightBytesTotal =>
      inFlightBytes.values.fold<int>(0, (total, sent) => total + sent);

  int get uploadedBytes {
    if (session.isDirectUpload && completed) {
      return session.sizeBytes;
    }
    return session.parts
        .where((part) => completedPartNumbers.contains(part.partNumber))
        .fold<int>(0, (total, part) => total + part.sizeBytes)
        .clamp(0, session.sizeBytes);
  }
}

/// 上传目标目录与空间的快照。
///
/// 批量上传与冲突重试可能持续数分钟，期间用户会切换目录或空间；
/// 目标必须在发起时固化，否则排队中的文件会静默传进用户后来浏览的目录。
class UploadTarget {
  const UploadTarget({required this.parentId, required this.spaceType});

  /// 目标父目录，null 表示当前空间的根目录。
  final String? parentId;

  /// 后端空间参数：共享空间为 `SHARED`，个人空间为 null。
  final String? spaceType;

  static UploadTarget of(FileBrowserState? state) {
    return UploadTarget(
      parentId: state?.parentId,
      spaceType: state?.spaceType == 'SHARED' ? 'SHARED' : null,
    );
  }
}

class _PreparedUpload {
  const _PreparedUpload({
    required this.taskId,
    required this.file,
    required this.fileName,
    required this.sizeBytes,
    required this.target,
  });

  final String taskId;
  final XFile file;
  final String fileName;
  final int sizeBytes;
  final UploadTarget target;
}

extension FileBrowserUploadActions on FileBrowserController {
  Future<FileUploadSession> createUploadSession({
    required String fileName,
    required int sizeBytes,
    String? mimeType,
    String? sha256,
    int? partSizeBytes,
    String? asVersionOfFileId,
    UploadTarget? target,
  }) async {
    return _runAction(FileOperation.createUploadSession, () async {
      final current = _currentState;
      final resolved = target ?? UploadTarget.of(current);
      final session = await _repository.createUploadSession(
        parentId: resolved.parentId,
        fileName: fileName,
        sizeBytes: sizeBytes,
        mimeType: mimeType,
        sha256: sha256,
        partSizeBytes: partSizeBytes,
        spaceType: resolved.spaceType,
        asVersionOfFileId: asVersionOfFileId,
      );
      final live = _liveOr(current);
      // 会话列表只用于本地审计展示，保留最近 20 条，避免长会话下无界增长。
      final sessions = [session, ...live.uploadSessions];
      _emitState(
        live.copyWith(
          uploadSessions:
              sessions.length > 20 ? sessions.sublist(0, 20) : sessions,
        ),
      );
      return session;
    });
  }

  void _discardUploadSession(String uploadId) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final remaining =
        current.uploadSessions
            .where((session) => session.uploadId != uploadId)
            .toList();
    if (remaining.length == current.uploadSessions.length) {
      return;
    }
    _emitState(current.copyWith(uploadSessions: remaining));
  }

  Future<void> completeUploadSession(
    FileUploadSession session, {
    String? sha256,
  }) async {
    await _runAction(FileOperation.completeUploadSession, () async {
      await _repository.completeUploadSession(
        sessionId: session.uploadId,
        sha256: sha256,
      );
      _discardUploadSession(session.uploadId);
      final currentSection = _currentState?.section;
      if (currentSection == FileManagerSection.sharedSpace) {
        await showSharedSpace();
      } else {
        await refreshFileNodesForCurrentSection();
      }
    });
  }

  /// 用本地文件替换现有文件内容，并将旧内容保存为历史版本。
  Future<void> replaceFileWithNewVersion(FileNode file, XFile source) async {
    await _runAction(FileOperation.saveVersion, () async {
      final result = await _uploadSingleFile(
        source,
        fileName: file.name,
        asVersionOfFileId: file.id,
      );
      if (result != _UploadFileResult.completed) {
        throw const AppException(
          code: AppErrorCodes.versionUploadIncomplete,
          message: AppErrorCodes.versionUploadIncomplete,
        );
      }
      await refreshFileNodesForCurrentSection();
    });
  }

  void pauseLocalUploadTask(String taskId) {
    final task = _findLocalUploadTask(taskId);
    final runtime = _uploadRuntimes[taskId];
    if (runtime == null) {
      // 任务还在排队或创建会话：没有运行时句柄，先登记墓碑，Worker 轮到时不得开始上传。
      _prePausedLocalTaskIds.add(taskId);
      if (task != null &&
          (task.status == 'QUEUED' || task.status == 'UPLOADING')) {
        _upsertLocalUploadTask(
          task.copyWith(
            status: 'PAUSED',
            messageCode: FileUploadTaskMessageCode.paused,
          ),
        );
      }
      return;
    }
    if (runtime.removed || runtime.completed) {
      return;
    }
    runtime.pauseRequested = true;
    for (final cancellation in runtime.activeCancellations.toList()) {
      cancellation.cancel();
    }
    if (task != null && task.status != 'PAUSED') {
      _upsertLocalUploadTask(
        task.copyWith(
          status: 'PAUSED',
          messageCode: FileUploadTaskMessageCode.pausePending,
        ),
      );
    }
  }

  Future<void> resumeLocalUploadTask(String taskId) async {
    await _runAction(FileOperation.resumeUpload, () async {
      final task = _findLocalUploadTask(taskId);
      if (task == null || _cancelledLocalTaskIds.contains(taskId)) {
        return;
      }
      _prePausedLocalTaskIds.remove(taskId);
      final runtime = _uploadRuntimes[taskId];
      final ticket = _resumeTickets[taskId];
      if (runtime == null) {
        if (ticket == null) {
          // Worker 尚未轮转到该文件：先恢复排队态，轮到时自然会开始上传。
          _upsertLocalUploadTask(
            task.copyWith(
              status: 'UPLOADING',
              messageCode: FileUploadTaskMessageCode.resuming,
            ),
          );
          return;
        }
        _upsertLocalUploadTask(
          task.copyWith(
            status: 'UPLOADING',
            messageCode: FileUploadTaskMessageCode.resuming,
          ),
        );
        final result = await _uploadSingleFile(
          ticket.file,
          taskId: taskId,
          fileName: ticket.fileName,
          sizeBytes: ticket.sizeBytes,
          mimeType: ticket.mimeType,
          asVersionOfFileId: ticket.asVersionOfFileId,
          target: ticket.target,
        );
        if (result == _UploadFileResult.completed) {
          await _refreshAfterLocalUploadSettled();
        }
        return;
      }
      if (runtime.removed || runtime.running || runtime.completed) {
        return;
      }
      runtime.pauseRequested = false;
      _upsertLocalUploadTask(
        task.copyWith(
          status: 'UPLOADING',
          messageCode: FileUploadTaskMessageCode.resuming,
        ),
      );
      try {
        await _runUploadRuntime(taskId);
        if (_findLocalUploadTask(taskId)?.status.toUpperCase() == 'COMPLETED') {
          await _refreshAfterLocalUploadSettled();
        }
      } catch (error) {
        _settleUploadRuntimeFailure(taskId, runtime, error);
      }
    });
  }

  Future<void> removeLocalUploadTask(String taskId) async {
    await _runAction(FileOperation.deleteUploadTask, () async {
      // 墓碑必须先于状态移除登记：Worker 的 prepared 列表不感知 UI 删除。
      _cancelledLocalTaskIds.add(taskId);
      _prePausedLocalTaskIds.remove(taskId);
      _resumeTickets.remove(taskId);
      final runtime = _uploadRuntimes.remove(taskId);
      runtime?.removed = true;
      if (runtime != null) {
        for (final cancellation in runtime.activeCancellations.toList()) {
          cancellation.cancel();
        }
      }
      final task = _findLocalUploadTask(taskId);
      _removeLocalUploadTask(taskId);
      final uploadId = runtime?.session.uploadId ?? task?.uploadId;
      final shouldCancelServerSession =
          uploadId != null &&
          uploadId.isNotEmpty &&
          task?.status != 'COMPLETED';
      if (shouldCancelServerSession) {
        await _repository.cancelUploadSession(uploadId);
        _discardUploadSession(uploadId);
        if (_currentState?.section == FileManagerSection.uploadQueue) {
          await showUploadQueue();
        }
      }
    });
  }

  Future<void> deleteServerUploadSession(FileUploadQueueItem item) async {
    await _runAction(FileOperation.deleteServerSession, () async {
      await _repository.cancelUploadSession(item.uploadId);
      _discardUploadSession(item.uploadId);
      final current = _currentState;
      if (current == null) {
        return;
      }
      _emitState(
        current.copyWith(
          uploadQueue:
              current.uploadQueue
                  .where((session) => session.uploadId != item.uploadId)
                  .toList(),
        ),
      );
    });
  }

  /// 获取待解决的软删除冲突列表。
  Map<String, SoftDeleteConflict> get pendingConflicts {
    return Map.fromEntries(
      _pendingConflicts.entries.map((e) => MapEntry(e.key, e.value.conflict)),
    );
  }

  /// 清理回收站中的冲突文件并重试上传。
  ///
  /// `purgeFile` 只提交异步 `FILE_PURGE` 任务，必须等任务终态再重传；立即重试
  /// 会撞上尚未清理的同名节点，再次得到 409。
  Future<void> resolveConflictAndRetry(String taskId) async {
    final pending = _pendingConflicts.remove(taskId);
    if (pending == null) return;
    if (_findLocalUploadTask(taskId) == null) return;

    final originalTask = _findLocalUploadTask(taskId);
    if (originalTask != null) {
      _upsertLocalUploadTask(
        originalTask.copyWith(
          messageCode: FileUploadTaskMessageCode.purgingConflict,
        ),
      );
    }

    try {
      final submission = await _repository.purgeFile(
        pending.conflict.softDeletedFileId,
      );
      final purgeTask = await uploadRef
          .read(taskApiProvider)
          .waitForTerminal(
            submission.taskId,
            timeout: const Duration(minutes: 2),
          );
      if (!purgeTask.isCompleted) {
        throw const AppException(
          code: AppErrorCodes.operationFailed,
          message: '彻底删除回收站同名文件失败',
        );
      }

      final currentTask = _findLocalUploadTask(taskId);
      if (currentTask == null) return;
      _upsertLocalUploadTask(
        currentTask.copyWith(
          status: 'QUEUED',
          messageCode: FileUploadTaskMessageCode.retrying,
        ),
      );
      final result = await _uploadSingleFile(
        pending.file,
        taskId: taskId,
        fileName: pending.fileName,
        sizeBytes: pending.sizeBytes,
        mimeType: pending.mimeType,
        target: pending.target,
      );
      if (result == _UploadFileResult.completed) {
        await _refreshAfterLocalUploadSettled();
      }
    } on Exception catch (error) {
      final currentTask = _findLocalUploadTask(taskId);
      if (currentTask == null) return;
      _upsertLocalUploadTask(
        currentTask.copyWith(
          status: 'FAILED',
          messageCode: FileUploadTaskMessageCode.failed,
          message: userFacingErrorDisplayText(error),
        ),
      );
    }
  }

  /// 取消冲突上传任务。
  void cancelConflict(String taskId) {
    _pendingConflicts.remove(taskId);
    _removeLocalUploadTask(taskId);
  }

  Future<void> _refreshAfterLocalUploadSettled() async {
    final currentSection = _currentState?.section;
    if (currentSection == FileManagerSection.uploadQueue) {
      await showUploadQueue();
    } else if (currentSection == FileManagerSection.sharedSpace) {
      // 共享空间上传会改变共享用量，必须重载空间视图而不是只刷新目录。
      await showSharedSpace();
    } else {
      await refreshFileNodesForCurrentSection();
    }
  }

  String _uploadFileName(XFile file) {
    final name = file.name.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final path = file.path.trim();
    if (path.isEmpty) {
      return 'file-${DateTime.now().microsecondsSinceEpoch}';
    }
    final parts = path.split(RegExp(r'[\\/]'));
    final fallback = parts.isEmpty ? path : parts.last;
    return fallback.isEmpty
        ? 'file-${DateTime.now().microsecondsSinceEpoch}'
        : fallback;
  }
}
