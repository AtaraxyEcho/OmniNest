part of 'file_browser_controller.dart';

/// 上传运行时执行：单文件会话创建、分片/直传调度与终态收敛。
///
/// 与 upload_actions 拆分，避免单个 part 超过源码行数棘轮；两者同属
/// FileBrowserController 扩展，私有成员在同一 library 内可见。
extension FileBrowserUploadRuntime on FileBrowserController {
  /// 批量上传并发文件数：小文件不必排在大文件后面，同时限制连接总量。
  static const int _uploadBatchConcurrency = 3;

  /// 把服务端未完成的分片会话重新关联到用户重新选择的原文件。
  ///
  /// 分级校验：文件大小强一致（否则直接拒绝）；已完成分片再逐个用本地
  /// 区间 MD5 与 ETag 对账，只有对得上的分片才跳过，对不上的重新上传。
  /// 这样既不会把错文件续到原会话，也不会因预签名或本地文件变化而跳过坏分片。
  Future<void> rebindServerUploadSession(
    FileUploadQueueItem item,
    XFile file,
  ) async {
    await _runAction(FileOperation.resumeUpload, () async {
      final fileSize = await file.length();
      if (fileSize != item.sizeBytes) {
        throw const AppException(
          code: AppErrorCodes.uploadRebindSizeMismatch,
          message: '所选文件大小与原上传会话不一致',
        );
      }
      final api = uploadRef.read(fileApiProvider);
      final extended = await api.extendUploadSession(item.uploadId);
      final partsInfo = await api.listUploadParts(item.uploadId);
      if (partsInfo.parts.length != extended.totalParts) {
        throw const AppException(
          code: AppErrorCodes.operationFailed,
          message: '上传分片明细不完整，无法续传',
        );
      }
      final verifiedParts = <int>{};
      var uploadedBytes = 0;
      for (final part in partsInfo.parts) {
        if (part.status.toUpperCase() != 'COMPLETED' || part.sizeBytes <= 0) {
          continue;
        }
        final start = (part.partNumber - 1) * extended.partSizeBytes;
        final end = math.min(start + part.sizeBytes, extended.sizeBytes);
        if (end - start != part.sizeBytes) {
          continue;
        }
        final eTag = part.eTag?.trim().replaceAll('"', '').toLowerCase();
        if (eTag == null || !RegExp(r'^[0-9a-f]{32}$').hasMatch(eTag)) {
          // 非 MD5 ETag（或缺少 ETag）无法证明本地分片一致，宁可重传。
          continue;
        }
        try {
          final digest = await md5.bind(file.openRead(start, end)).first;
          if (digest.toString().toLowerCase() == eTag) {
            verifiedParts.add(part.partNumber);
            uploadedBytes += part.sizeBytes;
          }
        } on Object {
          // 读取失败（文件被移动/权限变化）按未校验处理，后续重新上传该分片。
        }
      }
      final session = FileUploadSession(
        id: extended.id,
        uploadId: item.uploadId,
        parentId: extended.parentId,
        fileName: extended.fileName,
        sizeBytes: extended.sizeBytes,
        partSizeBytes: extended.partSizeBytes,
        totalParts: extended.totalParts,
        mimeType: extended.mimeType,
        status: extended.status,
        uploadUrl: extended.uploadUrl,
        uploadUrlExpiresAt: extended.uploadUrlExpiresAt,
        parts: partsInfo.parts,
        expiresAt: extended.expiresAt,
      );
      final taskId = 'rebound-${item.uploadId}';
      final task = FileUploadClientTask(
        id: taskId,
        fileName: extended.fileName,
        sizeBytes: extended.sizeBytes,
        uploadedBytes: uploadedBytes.clamp(0, extended.sizeBytes),
        status: 'UPLOADING',
        messageCode: FileUploadTaskMessageCode.resuming,
        uploadId: item.uploadId,
      );
      final runtime = _UploadRuntime(file: file, session: session);
      runtime.completedPartNumbers.addAll(verifiedParts);
      _uploadRuntimes[taskId] = runtime;
      _upsertLocalUploadTask(task);
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

  /// [target] 让不在当前目录发起的入口（例如按原会话位置重新提交）指定落点；
  /// 省略时取当前浏览快照。
  Future<FileUploadBatchResult> uploadFiles(
    List<XFile> files, {
    UploadTarget? target,
  }) async {
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
    // 整批共用一个目标快照：上传进行中切换目录/空间不能改动排队文件的落点。
    final uploadTarget = target ?? UploadTarget.of(_currentState);
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
            target: uploadTarget,
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
          if (_cancelledLocalTaskIds.remove(item.taskId)) {
            _resumeTickets.remove(item.taskId);
            continue;
          }
          final existingQueued = _findLocalUploadTask(item.taskId);
          if (existingQueued == null) {
            _cancelledLocalTaskIds.remove(item.taskId);
            continue;
          }
          if (_prePausedLocalTaskIds.contains(item.taskId)) {
            // 保留重启信息：Worker 已跳过该项，用户点继续时要能重新发起会话。
            _resumeTickets[item.taskId] = (
              file: item.file,
              fileName: item.fileName,
              sizeBytes: item.sizeBytes,
              mimeType: item.file.mimeType,
              asVersionOfFileId: null,
              target: item.target,
            );
            paused += 1;
            continue;
          }
          try {
            final result = await _uploadSingleFile(
              item.file,
              policy: policy,
              taskId: item.taskId,
              fileName: item.fileName,
              sizeBytes: item.sizeBytes,
              target: item.target,
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
  Future<_UploadFileResult> _uploadSingleFile(
    XFile file, {
    FileUploadPolicy? policy,
    String? taskId,
    String? fileName,
    int? sizeBytes,
    String? mimeType,
    String? asVersionOfFileId,
    UploadTarget? target,
  }) async {
    sizeBytes ??= await file.length();
    fileName ??= _uploadFileName(file);
    final resolvedTaskId =
        taskId ?? DateTime.now().microsecondsSinceEpoch.toString();
    if (_cancelledLocalTaskIds.remove(resolvedTaskId)) {
      return _UploadFileResult.cancelled;
    }
    final existingTask = _findLocalUploadTask(resolvedTaskId);
    final task =
        existingTask ??
        FileUploadClientTask(
          id: resolvedTaskId,
          fileName: fileName,
          sizeBytes: sizeBytes,
          uploadedBytes: 0,
          status: 'QUEUED',
          messageCode: FileUploadTaskMessageCode.waiting,
        );
    _resumeTickets[task.id] = (
      file: file,
      fileName: fileName,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      asVersionOfFileId: asVersionOfFileId,
      target: target ?? UploadTarget.of(_currentState),
    );
    _upsertLocalUploadTask(task);
    _UploadRuntime? uploadRuntime;
    try {
      final effectivePolicy = policy ?? await _repository.uploadPolicy();
      // 单文件上限先本地拦一遍：超限文件传出去几个 GB 才被服务端拒绝，
      // 白占带宽、白排队，也把队列堵在注定失败的任务上。
      final maxFileSizeBytes = effectivePolicy.maxFileSizeBytes;
      if (maxFileSizeBytes > 0 && sizeBytes > maxFileSizeBytes) {
        throw AppException(
          code: AppErrorCodes.operationFailed,
          message:
              '文件超过单文件上传上限'
              '（${(maxFileSizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB）',
        );
      }
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
        target: target,
      );
      if (_cancelledLocalTaskIds.remove(task.id)) {
        await _cancelUploadSessionQuietly(session.uploadId);
        _discardUploadSession(session.uploadId);
        return _UploadFileResult.cancelled;
      }
      uploadRuntime = _UploadRuntime(
        file: file,
        session: session,
        asVersionOfFileId: asVersionOfFileId,
      );
      _uploadRuntimes[task.id] = uploadRuntime;
      if (_prePausedLocalTaskIds.contains(task.id)) {
        // 创建会话期间用户点了暂停：保留运行时供继续，但不得短暂闪回 UPLOADING。
        uploadRuntime.pauseRequested = true;
        _markUploadPaused(task.id, uploadRuntime);
        return _UploadFileResult.paused;
      }
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
      await _runUploadRuntime(task.id);
      final finalTask = _findLocalUploadTask(task.id);
      final result = switch (finalTask?.status.toUpperCase()) {
        'COMPLETED' => _UploadFileResult.completed,
        'PAUSED' => _UploadFileResult.paused,
        _ => _UploadFileResult.cancelled,
      };
      if (result == _UploadFileResult.completed) {
        _resumeTickets.remove(task.id);
      }
      return result;
    } catch (error) {
      final runtime = uploadRuntime ?? _uploadRuntimes[task.id];
      if (runtime?.pauseRequested == true ||
          runtime?.removed == true ||
          _prePausedLocalTaskIds.contains(task.id) ||
          _cancelledLocalTaskIds.contains(task.id)) {
        return _settleUploadRuntimeFailure(task.id, runtime, error);
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
          target: target ?? UploadTarget.of(_currentState),
        );
        _resumeTickets.remove(task.id);
        return _UploadFileResult.conflict;
      }
      return _settleUploadRuntimeFailure(task.id, runtime, error);
    }
  }

  /// 清理被删除任务已创建的服务端会话；失败只记日志，由过期回收兜底。
  Future<void> _cancelUploadSessionQuietly(String uploadId) async {
    try {
      await _repository.cancelUploadSession(uploadId);
    } on Exception catch (error) {
      devLog('取消已删除任务的服务端上传会话失败: $error');
    }
  }

  /// 运行时异常的统一收敛：删除、暂停、失败三种终态都在这里判定，
  /// 避免 _uploadSingleFile 与 resume 各自实现后再次分叉。
  _UploadFileResult _settleUploadRuntimeFailure(
    String taskId,
    _UploadRuntime? runtime,
    Object error,
  ) {
    if (_cancelledLocalTaskIds.remove(taskId)) {
      _uploadRuntimes.remove(taskId);
      _resumeTickets.remove(taskId);
      return _UploadFileResult.cancelled;
    }
    final currentTask = _findLocalUploadTask(taskId);
    if (currentTask == null) {
      return _UploadFileResult.cancelled;
    }
    if (runtime?.pauseRequested == true ||
        _prePausedLocalTaskIds.contains(taskId)) {
      if (runtime != null) {
        runtime.pauseRequested = true;
        _markUploadPaused(taskId, runtime);
      } else {
        _upsertLocalUploadTask(
          currentTask.copyWith(
            status: 'PAUSED',
            messageCode: FileUploadTaskMessageCode.paused,
          ),
        );
      }
      return _UploadFileResult.paused;
    }
    if (runtime?.removed == true) {
      return _UploadFileResult.cancelled;
    }
    _upsertLocalUploadTask(
      currentTask.copyWith(
        status: 'FAILED',
        messageCode: FileUploadTaskMessageCode.failed,
        message: describeUserFacingError(error).displayMessage,
      ),
    );
    return _UploadFileResult.failed;
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
    var uploadUrl = runtime.session.uploadUrl;
    final uploadUrlExpiresAt = runtime.session.uploadUrlExpiresAt;
    final urlUsable =
        uploadUrl != null &&
        uploadUrl.isNotEmpty &&
        (uploadUrlExpiresAt == null ||
            DateTime.now().isBefore(
              uploadUrlExpiresAt.subtract(const Duration(minutes: 1)),
            ));
    if (!urlUsable) {
      // 直传沿用单分片 URL 接口重签：暂停超过预签名有效期后复用旧 URL 必定 403。
      uploadUrl = await _repository.getUploadPartUrl(
        uploadId: runtime.session.uploadId,
        partNumber: 1,
      );
      if (runtime.removed || runtime.pauseRequested) {
        return;
      }
    }
    if (uploadUrl.isEmpty) {
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
    _resumeTickets.remove(taskId);
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
    _resumeTickets.remove(taskId);
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
    final expiresAt = part.uploadUrlExpiresAt;
    final urlUsable =
        uploadUrl != null &&
        uploadUrl.isNotEmpty &&
        (expiresAt == null ||
            DateTime.now().isBefore(
              expiresAt.subtract(const Duration(minutes: 1)),
            ));
    if (!urlUsable) {
      // 创建会话只预签名首批分片，其余分片在上传前逐个按需获取；
      // 暂停超过预签名有效期后也必须重新签发，不能复用已过期 URL。
      uploadUrl = await _repository.getUploadPartUrl(
        uploadId: runtime.session.uploadId,
        partNumber: part.partNumber,
      );
      // 请求在途期间任务可能已被暂停或删除：此时还没有登记取消令牌，
      // 不在这里拦截会继续上传整个分片（最大 64 MB）。
      if (runtime.removed || runtime.pauseRequested) {
        return;
      }
    }
    if (uploadUrl.isEmpty) {
      throw const AppException(
        code: AppErrorCodes.uploadUrlMissing,
        message: '上传地址不可用',
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
      // 先移除当前分片的在途字节，避免把已完成字节与同一分片重复相加。
      runtime.inFlightBytes.remove(part.partNumber);
      final afterPartTask = _findLocalUploadTask(taskId);
      // 暂停标记必须在确认分片后重查：确认请求在途时用户可能已经点了暂停，
      // 不拦住会把刚置为 PAUSED 的任务覆写回 UPLOADING。
      if (runtime.removed || runtime.pauseRequested || afterPartTask == null) {
        return;
      }
      _upsertLocalUploadTask(
        afterPartTask.copyWith(
          uploadedBytes: runtime.uploadedBytes + runtime.inFlightBytesTotal,
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
    // 时间下限必须独立成立：旧写法让高速链路每满一个字节阈值就上报一次，整页高频重建。
    if (!isComplete &&
        (elapsed < const Duration(milliseconds: 80) || byteDelta == 0)) {
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
    final existingIndex = current.localUploadTasks.indexWhere(
      (item) => item.id == task.id,
    );
    final previous =
        existingIndex < 0 ? null : current.localUploadTasks[existingIndex];
    // 进度回调每 80ms 一次：已有任务必须原地替换，头插会让队列行随并发进度跳动。
    // 新任务追加到队尾，保持用户选择文件的顺序。
    final tasks =
        existingIndex < 0
            ? [...current.localUploadTasks, task]
            : [
              for (final item in current.localUploadTasks)
                if (item.id == task.id) task else item,
            ];
    // 只裁剪已完成/已失败的历史记录；活跃任务与待用户处理的冲突任务不能被挤出。
    // 保留最近 20 条终态记录：新任务追加在队尾，从队首正向计数会把刚完成的任务
    // 立刻丢弃，因此先算出需要跳过的最旧条数。
    final totalTerminal = tasks.where((item) => item.isTerminal).length;
    var toDrop = math.max(0, totalTerminal - 20);
    final kept = <FileUploadClientTask>[];
    for (final item in tasks) {
      if (item.isTerminal && toDrop > 0) {
        toDrop--;
        continue;
      }
      kept.add(item);
    }
    _emitState(current.copyWith(localUploadTasks: kept));
    if (previous == null || previous.status != task.status) {
      _startUploadQueuePolling();
    }
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
