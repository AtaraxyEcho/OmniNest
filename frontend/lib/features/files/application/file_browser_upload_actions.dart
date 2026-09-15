part of 'file_browser_controller.dart';

extension FileBrowserUploadActions on FileBrowserController {
  Future<FileUploadSession> createUploadSession({
    required String fileName,
    required int sizeBytes,
    String? mimeType,
    String? sha256,
    int? partSizeBytes,
    String? asVersionOfFileId,
  }) async {
    return _runAction(FileOperation.createUploadSession, () async {
      final current = _currentState;
      // 根据当前空间决定上传目标
      final isShared = current?.spaceType == 'SHARED';
      final session = await _repository.createUploadSession(
        parentId: current?.parentId,
        fileName: fileName,
        sizeBytes: sizeBytes,
        mimeType: mimeType,
        sha256: sha256,
        partSizeBytes: partSizeBytes,
        spaceType: isShared ? 'SHARED' : null,
        asVersionOfFileId: asVersionOfFileId,
      );
      _emitState(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          uploadSessions: [session, ...?current?.uploadSessions],
        ),
      );
      return session;
    });
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
      await _uploadSingleFile(
        source,
        fileName: file.name,
        asVersionOfFileId: file.id,
      );
      await refreshFileNodesForCurrentSection();
    });
  }

  void pauseLocalUploadTask(String taskId) {
    final runtime = _uploadRuntimes[taskId];
    if (runtime == null || runtime.removed || runtime.completed) {
      return;
    }
    runtime.pauseRequested = true;
    runtime.activeCancellation?.cancel();
    final task = _findLocalUploadTask(taskId);
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
      final runtime = _uploadRuntimes[taskId];
      final task = _findLocalUploadTask(taskId);
      if (runtime == null || task == null || runtime.removed) {
        return;
      }
      if (runtime.running || runtime.completed) {
        return;
      }
      runtime.pauseRequested = false;
      _upsertLocalUploadTask(
        task.copyWith(
          status: 'UPLOADING',
          messageCode: FileUploadTaskMessageCode.resuming,
        ),
      );
      await _runUploadRuntime(taskId);
      final settled = _findLocalUploadTask(taskId);
      if (settled?.status.toUpperCase() == 'COMPLETED') {
        await _refreshAfterLocalUploadSettled();
      }
    });
  }

  Future<void> removeLocalUploadTask(String taskId) async {
    await _runAction(FileOperation.deleteUploadTask, () async {
      final runtime = _uploadRuntimes.remove(taskId);
      runtime?.removed = true;
      runtime?.activeCancellation?.cancel();
      final task = _findLocalUploadTask(taskId);
      _removeLocalUploadTask(taskId);
      final uploadId = runtime?.session.uploadId ?? task?.uploadId;
      final shouldCancelServerSession =
          uploadId != null &&
          uploadId.isNotEmpty &&
          task?.status != 'COMPLETED';
      if (shouldCancelServerSession) {
        await _repository.cancelUploadSession(uploadId);
        if (_currentState?.section == FileManagerSection.uploadQueue) {
          await showUploadQueue();
        }
      }
    });
  }

  Future<void> deleteServerUploadSession(FileUploadQueueItem item) async {
    await _runAction(FileOperation.deleteServerSession, () async {
      await _repository.cancelUploadSession(item.uploadId);
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
  Future<void> resolveConflictAndRetry(String taskId) async {
    final pending = _pendingConflicts.remove(taskId);
    if (pending == null) return;

    // 从回收站永久删除冲突文件
    await _repository.purgeFile(pending.conflict.softDeletedFileId);

    // 重试上传
    final currentTask = _findLocalUploadTask(taskId);
    if (currentTask != null) {
      _upsertLocalUploadTask(
        currentTask.copyWith(
          status: 'QUEUED',
          messageCode: FileUploadTaskMessageCode.retrying,
        ),
      );
    }
    final result = await _uploadSingleFile(
      pending.file,
      taskId: taskId,
      fileName: pending.fileName,
      sizeBytes: pending.sizeBytes,
      mimeType: pending.mimeType,
    );
    if (result == _UploadFileResult.completed) {
      await _refreshAfterLocalUploadSettled();
    }
  }

  /// 取消冲突上传任务。
  void cancelConflict(String taskId) {
    _pendingConflicts.remove(taskId);
    _removeLocalUploadTask(taskId);
  }

  Future<FileUploadBatchResult> uploadFiles(List<XFile> files) async {
    if (files.isEmpty) {
      return const FileUploadBatchResult(
        total: 0,
        completed: 0,
        conflicts: 0,
        failed: 0,
        paused: 0,
      );
    }
    clearActionError();
    var completed = 0;
    var conflicts = 0;
    var failed = 0;
    var paused = 0;
    try {
      final policy = await _repository.uploadPolicy();
      for (final file in files) {
        try {
          final result = await _uploadSingleFile(file, policy: policy);
          switch (result) {
            case _UploadFileResult.completed:
              completed += 1;
              break;
            case _UploadFileResult.conflict:
              conflicts += 1;
              break;
            case _UploadFileResult.failed:
              failed += 1;
              break;
            case _UploadFileResult.paused:
              paused += 1;
              break;
            case _UploadFileResult.cancelled:
              break;
          }
        } catch (error) {
          failed += 1;
          _recordActionError(FileOperation.upload, error);
        }
      }
      await _refreshAfterLocalUploadSettled();
      return FileUploadBatchResult(
        total: files.length,
        completed: completed,
        conflicts: conflicts,
        failed: failed,
        paused: paused,
      );
    } catch (error) {
      _recordActionError(FileOperation.upload, error);
      rethrow;
    }
  }

  /// 本地上传任务完成后的列表收尾，与批量上传路径保持一致。
  Future<void> _refreshAfterLocalUploadSettled() async {
    final currentSection = _currentState?.section;
    if (currentSection == FileManagerSection.uploadQueue) {
      await showUploadQueue();
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

  Future<_UploadFileResult> _uploadSingleFile(
    XFile file, {
    FileUploadPolicy? policy,
    String? taskId,
    String? fileName,
    int? sizeBytes,
    String? mimeType,
    String? asVersionOfFileId,
  }) async {
    sizeBytes ??= await file.length();
    fileName ??= _uploadFileName(file);
    final task = FileUploadClientTask(
      id: taskId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      fileName: fileName,
      sizeBytes: sizeBytes,
      uploadedBytes: 0,
      status: 'QUEUED',
      messageCode: FileUploadTaskMessageCode.waiting,
    );
    _upsertLocalUploadTask(task);
    _UploadRuntime? uploadRuntime;
    try {
      final effectivePolicy = policy ?? await _repository.uploadPolicy();
      final needsMultipart = sizeBytes > effectivePolicy.directUploadMaxBytes;
      final partSizeBytes =
          needsMultipart
              ? calculatePartSizeBytes(
                fileSizeBytes: sizeBytes,
                defaultPartSizeBytes: effectivePolicy.defaultPartSizeBytes,
                maxPartSizeBytes: effectivePolicy.maxPartSizeBytes,
                maxTotalParts: effectivePolicy.maxTotalParts,
              )
              : null;
      final session = await createUploadSession(
        fileName: fileName,
        sizeBytes: sizeBytes,
        mimeType: mimeType ?? file.mimeType ?? 'application/octet-stream',
        partSizeBytes: partSizeBytes,
        asVersionOfFileId: asVersionOfFileId,
      );
      _upsertLocalUploadTask(
        task.copyWith(
          status: 'UPLOADING',
          messageCode:
              session.isDirectUpload
                  ? FileUploadTaskMessageCode.directUploading
                  : FileUploadTaskMessageCode.multipartUploading,
          uploadId: session.uploadId,
        ),
      );
      uploadRuntime = _UploadRuntime(
        file: file,
        session: session,
        asVersionOfFileId: asVersionOfFileId,
      );
      _uploadRuntimes[task.id] = uploadRuntime;
      await _runUploadRuntime(task.id);
      final finalTask = _findLocalUploadTask(task.id);
      return switch (finalTask?.status.toUpperCase()) {
        'COMPLETED' => _UploadFileResult.completed,
        'PAUSED' => _UploadFileResult.paused,
        _ => _UploadFileResult.cancelled,
      };
    } catch (error) {
      final runtime = uploadRuntime ?? _uploadRuntimes[task.id];
      if (runtime?.pauseRequested == true) {
        final currentTask = _findLocalUploadTask(task.id) ?? task;
        _upsertLocalUploadTask(
          currentTask.copyWith(
            status: 'PAUSED',
            messageCode: FileUploadTaskMessageCode.paused,
          ),
        );
        return _UploadFileResult.paused;
      }
      if (runtime?.removed == true) {
        return _UploadFileResult.cancelled;
      }
      // 检测软删除同名文件冲突
      if (error is DioException) {
        final conflict = SoftDeleteConflict.fromDioException(error);
        if (conflict != null) {
          final currentTask = _findLocalUploadTask(task.id) ?? task;
          _upsertLocalUploadTask(
            currentTask.copyWith(
              status: 'CONFLICT',
              messageCode: FileUploadTaskMessageCode.conflict,
              messageArgument: conflict.fileName,
            ),
          );
          _pendingConflicts[task.id] = (
            conflict: conflict,
            file: file,
            fileName: fileName,
            sizeBytes: sizeBytes,
            mimeType: file.mimeType ?? 'application/octet-stream',
          );
          return _UploadFileResult.conflict;
        }
      }
      final currentTask = _findLocalUploadTask(task.id) ?? task;
      _upsertLocalUploadTask(
        currentTask.copyWith(
          status: 'FAILED',
          messageCode: FileUploadTaskMessageCode.failed,
          message: describeUserFacingError(error).displayMessage,
        ),
      );
      return _UploadFileResult.failed;
    }
  }

  Future<void> _runUploadRuntime(String taskId) async {
    final runtime = _uploadRuntimes[taskId];
    final task = _findLocalUploadTask(taskId);
    if (runtime == null || task == null || runtime.running) {
      return;
    }
    runtime.running = true;
    try {
      if (runtime.session.isDirectUpload) {
        await _runDirectUpload(taskId, runtime);
      } else {
        await _runMultipartUpload(taskId, runtime);
      }
    } finally {
      runtime.running = false;
    }
  }

  Future<void> _runDirectUpload(String taskId, _UploadRuntime runtime) async {
    if (_shouldPause(taskId, runtime)) {
      return;
    }
    final task = _findLocalUploadTask(taskId);
    if (task == null) {
      return;
    }
    final uploadUrl = runtime.session.uploadUrl;
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw const AppException(
        code: AppErrorCodes.uploadUrlMissing,
        message: AppErrorCodes.uploadUrlMissing,
      );
    }
    final cancellation = FileUploadCancellationToken();
    runtime.activeCancellation = cancellation;
    try {
      await _repository.putUploadUrl(
        uploadUrl: uploadUrl,
        data: runtime.file.openRead(),
        contentLength: runtime.session.sizeBytes,
        cancellationToken: cancellation,
        onProgress:
            (sent, total) => _reportUploadProgress(
              taskId,
              runtime,
              sent.clamp(0, runtime.session.sizeBytes),
            ),
      );
    } finally {
      if (identical(runtime.activeCancellation, cancellation)) {
        runtime.activeCancellation = null;
      }
    }
    if (runtime.removed) {
      return;
    }
    if (runtime.pauseRequested) {
      _markUploadPaused(taskId, runtime);
      return;
    }
    await _repository.completeUploadSession(
      sessionId: runtime.session.uploadId,
      asVersionOfFileId: runtime.asVersionOfFileId,
    );
    runtime.completed = true;
    _uploadRuntimes.remove(taskId);
    _upsertLocalUploadTask(
      task.copyWith(
        uploadedBytes: runtime.session.sizeBytes,
        status: 'COMPLETED',
        messageCode: FileUploadTaskMessageCode.completed,
        uploadId: runtime.session.uploadId,
      ),
    );
  }

  Future<void> _runMultipartUpload(
    String taskId,
    _UploadRuntime runtime,
  ) async {
    for (final part in runtime.session.parts) {
      if (runtime.removed) {
        return;
      }
      if (runtime.completedPartNumbers.contains(part.partNumber)) {
        continue;
      }
      if (_shouldPause(taskId, runtime)) {
        return;
      }
      final uploadUrl = part.uploadUrl;
      if (uploadUrl == null || uploadUrl.isEmpty) {
        throw AppException(
          code: AppErrorCodes.uploadUrlMissing,
          message: '${AppErrorCodes.uploadUrlMissing}:${part.partNumber}',
        );
      }
      final start = (part.partNumber - 1) * runtime.session.partSizeBytes;
      final end = math.min(start + part.sizeBytes, runtime.session.sizeBytes);
      final completedBytes = runtime.uploadedBytes;
      final cancellation = FileUploadCancellationToken();
      runtime.activeCancellation = cancellation;
      final String eTag;
      try {
        eTag = await _repository.putUploadUrl(
          uploadUrl: uploadUrl,
          data: runtime.file.openRead(start, end),
          contentLength: part.sizeBytes,
          cancellationToken: cancellation,
          onProgress:
              (sent, total) => _reportUploadProgress(
                taskId,
                runtime,
                completedBytes + sent.clamp(0, part.sizeBytes),
              ),
        );
      } finally {
        if (identical(runtime.activeCancellation, cancellation)) {
          runtime.activeCancellation = null;
        }
      }
      if (runtime.removed) {
        return;
      }
      await _repository.completeUploadPart(
        uploadId: runtime.session.uploadId,
        partNumber: part.partNumber,
        eTag: eTag,
      );
      runtime.completedPartNumbers.add(part.partNumber);
      _upsertLocalUploadTask(
        (_findLocalUploadTask(taskId)!).copyWith(
          uploadedBytes: runtime.uploadedBytes,
          status: 'UPLOADING',
          messageCode: FileUploadTaskMessageCode.partCompleted,
          messageCurrent: part.partNumber,
          messageTotal: runtime.session.totalParts,
          uploadId: runtime.session.uploadId,
        ),
      );
    }
    if (_shouldPause(taskId, runtime)) {
      return;
    }
    await _repository.completeUploadSession(
      sessionId: runtime.session.uploadId,
      asVersionOfFileId: runtime.asVersionOfFileId,
    );
    runtime.completed = true;
    _uploadRuntimes.remove(taskId);
    _upsertLocalUploadTask(
      (_findLocalUploadTask(taskId)!).copyWith(
        uploadedBytes: runtime.session.sizeBytes,
        status: 'COMPLETED',
        messageCode: FileUploadTaskMessageCode.completed,
        uploadId: runtime.session.uploadId,
      ),
    );
  }

  bool _shouldPause(String taskId, _UploadRuntime runtime) {
    if (!runtime.pauseRequested) {
      return false;
    }
    _markUploadPaused(taskId, runtime);
    return true;
  }

  void _markUploadPaused(String taskId, _UploadRuntime runtime) {
    final task = _findLocalUploadTask(taskId);
    if (task == null) {
      return;
    }
    _upsertLocalUploadTask(
      task.copyWith(
        uploadedBytes: runtime.uploadedBytes,
        status: 'PAUSED',
        messageCode: FileUploadTaskMessageCode.paused,
        uploadId: runtime.session.uploadId,
      ),
    );
  }

  void _reportUploadProgress(
    String taskId,
    _UploadRuntime runtime,
    int uploadedBytes,
  ) {
    final now = DateTime.now();
    final elapsed = now.difference(runtime.lastProgressAt);
    final byteDelta = (uploadedBytes - runtime.lastReportedBytes).abs();
    final isComplete = uploadedBytes >= runtime.session.sizeBytes;
    if (!isComplete &&
        elapsed < const Duration(milliseconds: 80) &&
        byteDelta < 256 * 1024) {
      return;
    }
    final task = _findLocalUploadTask(taskId);
    if (task == null || runtime.pauseRequested || runtime.removed) {
      return;
    }
    runtime.lastProgressAt = now;
    runtime.lastReportedBytes = uploadedBytes;
    _upsertLocalUploadTask(task.copyWith(uploadedBytes: uploadedBytes));
  }

  FileUploadClientTask? _findLocalUploadTask(String taskId) {
    final current = _currentState;
    if (current == null) {
      return null;
    }
    for (final task in current.localUploadTasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  void _upsertLocalUploadTask(FileUploadClientTask task) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final tasks = [
      task,
      ...current.localUploadTasks.where((item) => item.id != task.id),
    ];
    _emitState(current.copyWith(localUploadTasks: tasks.take(20).toList()));
    _startUploadQueuePolling();
  }

  void _removeLocalUploadTask(String taskId) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    _emitState(
      current.copyWith(
        localUploadTasks:
            current.localUploadTasks
                .where((item) => item.id != taskId)
                .toList(),
      ),
    );
    _startUploadQueuePolling();
  }
}
