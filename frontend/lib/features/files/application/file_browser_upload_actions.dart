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
  final FileUploadSession session;

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

class _PreparedUpload {
  const _PreparedUpload({
    required this.taskId,
    required this.file,
    required this.fileName,
    required this.sizeBytes,
  });

  final String taskId;
  final XFile file;
  final String fileName;
  final int sizeBytes;
}

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
    final runtime = _uploadRuntimes[taskId];
    if (runtime == null || runtime.removed || runtime.completed) {
      return;
    }
    runtime.pauseRequested = true;
    for (final cancellation in runtime.activeCancellations.toList()) {
      cancellation.cancel();
    }
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
          message: describeUserFacingError(error).displayMessage,
        ),
      );
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
      // 先把整批文件登记进上传队列，用户能看到所有待传文件而不是只看到当前一个。
      final prepared = <_PreparedUpload>[];
      final baseId = DateTime.now().microsecondsSinceEpoch;
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        final sizeBytes = await file.length();
        final fileName = _uploadFileName(file);
        final taskId = '$baseId-$index';
        prepared.add(
          _PreparedUpload(
            taskId: taskId,
            file: file,
            fileName: fileName,
            sizeBytes: sizeBytes,
          ),
        );
        _upsertLocalUploadTask(
          FileUploadClientTask(
            id: taskId,
            fileName: fileName,
            sizeBytes: sizeBytes,
            uploadedBytes: 0,
            status: 'QUEUED',
            messageCode: FileUploadTaskMessageCode.waiting,
          ),
        );
      }

      var cursor = 0;
      Future<void> runWorker() async {
        while (true) {
          if (cursor >= prepared.length) {
            return;
          }
          final item = prepared[cursor++];
          try {
            final result = await _uploadSingleFile(
              item.file,
              policy: policy,
              taskId: item.taskId,
              fileName: item.fileName,
              sizeBytes: item.sizeBytes,
            );
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
      }

      final workerCount = math.min(_uploadBatchConcurrency, prepared.length);
      await Future.wait(
        List<Future<void>>.generate(workerCount, (_) => runWorker()),
      );
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
      // 检测软删除同名文件冲突：409 在 validateStatus < 500 下由信封解析抛
      // AppException，只有旧路径才会是 DioException。
      final conflict =
          error is DioException
              ? SoftDeleteConflict.fromDioException(error)
              : error is AppException
              ? SoftDeleteConflict.fromAppException(error)
              : null;
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
    runtime.activeCancellations.add(cancellation);
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
      runtime.activeCancellations.remove(cancellation);
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
    _discardUploadSession(runtime.session.uploadId);
    _upsertLocalUploadTask(
      task.copyWith(
        uploadedBytes: runtime.session.sizeBytes,
        status: 'COMPLETED',
        messageCode: FileUploadTaskMessageCode.scanPending,
        uploadId: runtime.session.uploadId,
      ),
    );
  }

  /// 分片上传并发度：3 个在途分片足以吃满常见上行带宽，又不会让
  /// 单个大文件占满连接池。
  static const int _multipartConcurrency = 3;

  /// 批量上传并发文件数：小文件不必排在大文件后面，同时限制连接总量。
  static const int _uploadBatchConcurrency = 3;

  Future<void> _runMultipartUpload(
    String taskId,
    _UploadRuntime runtime,
  ) async {
    final pendingParts =
        runtime.session.parts
            .where(
              (part) => !runtime.completedPartNumbers.contains(part.partNumber),
            )
            .toList();
    var cursor = 0;
    var stopped = false;

    Future<void> runWorker() async {
      while (true) {
        if (stopped || runtime.removed || runtime.pauseRequested) {
          return;
        }
        if (cursor >= pendingParts.length) {
          return;
        }
        final part = pendingParts[cursor++];
        try {
          await _uploadAndCompletePart(taskId, runtime, part);
        } catch (error) {
          stopped = true;
          for (final cancellation in runtime.activeCancellations.toList()) {
            cancellation.cancel();
          }
          rethrow;
        }
      }
    }

    final workerCount = math.min(_multipartConcurrency, pendingParts.length);
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => runWorker()),
    );

    if (stopped || _shouldPause(taskId, runtime)) {
      return;
    }
    await _repository.completeUploadSession(
      sessionId: runtime.session.uploadId,
      asVersionOfFileId: runtime.asVersionOfFileId,
    );
    runtime.completed = true;
    _uploadRuntimes.remove(taskId);
    _discardUploadSession(runtime.session.uploadId);
    final completedTask = _findLocalUploadTask(taskId);
    if (runtime.removed || completedTask == null) {
      return;
    }
    _upsertLocalUploadTask(
      completedTask.copyWith(
        uploadedBytes: runtime.session.sizeBytes,
        status: 'COMPLETED',
        messageCode: FileUploadTaskMessageCode.scanPending,
        uploadId: runtime.session.uploadId,
      ),
    );
  }

  /// 上传并确认单个分片；失败时由工作池统一收敛为任务失败。
  Future<void> _uploadAndCompletePart(
    String taskId,
    _UploadRuntime runtime,
    FileUploadPart part,
  ) async {
    var uploadUrl = part.uploadUrl;
    if (uploadUrl == null || uploadUrl.isEmpty) {
      // 创建会话只预签名首批分片，其余分片在上传前逐个按需获取。
      uploadUrl = await _repository.getUploadPartUrl(
        uploadId: runtime.session.uploadId,
        partNumber: part.partNumber,
      );
    }
    final start = (part.partNumber - 1) * runtime.session.partSizeBytes;
    final end = math.min(start + part.sizeBytes, runtime.session.sizeBytes);
    final cancellation = FileUploadCancellationToken();
    runtime.activeCancellations.add(cancellation);
    try {
      final eTag = await _repository.putUploadUrl(
        uploadUrl: uploadUrl,
        data: runtime.file.openRead(start, end),
        contentLength: part.sizeBytes,
        cancellationToken: cancellation,
        onProgress: (sent, total) {
          runtime.inFlightBytes[part.partNumber] = sent.clamp(
            0,
            part.sizeBytes,
          );
          _reportUploadProgress(
            taskId,
            runtime,
            runtime.uploadedBytes + runtime.inFlightBytesTotal,
          );
        },
      );
      if (runtime.removed || runtime.pauseRequested) {
        return;
      }
      await _repository.completeUploadPart(
        uploadId: runtime.session.uploadId,
        partNumber: part.partNumber,
        eTag: eTag,
      );
      runtime.completedPartNumbers.add(part.partNumber);
      final afterPartTask = _findLocalUploadTask(taskId);
      if (runtime.removed || afterPartTask == null) {
        return;
      }
      _upsertLocalUploadTask(
        afterPartTask.copyWith(
          uploadedBytes: runtime.uploadedBytes,
          status: 'UPLOADING',
          messageCode: FileUploadTaskMessageCode.partCompleted,
          messageCurrent: part.partNumber,
          messageTotal: runtime.session.totalParts,
          uploadId: runtime.session.uploadId,
        ),
      );
    } finally {
      runtime.activeCancellations.remove(cancellation);
      runtime.inFlightBytes.remove(part.partNumber);
    }
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
    // 只裁剪已完成/已失败的历史记录；活跃任务与待用户处理的冲突任务不能被挤出。
    final kept = <FileUploadClientTask>[];
    var terminalCount = 0;
    for (final item in tasks) {
      if (item.isTerminal) {
        if (terminalCount >= 20) {
          continue;
        }
        terminalCount++;
      }
      kept.add(item);
    }
    _emitState(current.copyWith(localUploadTasks: kept));
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
