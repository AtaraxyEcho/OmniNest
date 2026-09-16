part of 'file_browser_controller.dart';

const _externalBrowseTimeout = Duration(seconds: 30);

extension FileBrowserIntegrationActions on FileBrowserController {
  Future<void> createOfflineDownload(
    String sourceUri, {
    String? spaceType,
  }) async {
    await _runAction(FileOperation.createOfflineDownload, () async {
      await _repository.createOfflineDownload(
        sourceUri: sourceUri,
        targetParentId: _currentState?.parentId,
        spaceType: spaceType,
      );
      await showOfflineDownloads();
    });
  }

  Future<void> cancelOfflineDownload(OfflineDownloadTask task) async {
    if (!task.canCancel) {
      return;
    }
    await _runAction(FileOperation.cancelOfflineDownload, () async {
      final current = _currentState;
      if (current != null) {
        _emitState(
          current.copyWith(
            offlineTasks:
                current.offlineTasks
                    .map(
                      (item) =>
                          item.id == task.id
                              ? item.copyWith(status: 'CANCELLING')
                              : item,
                    )
                    .toList(),
          ),
        );
      }
      await _repository.cancelOfflineDownload(task.id);
      await showOfflineDownloads();
    });
  }

  Future<void> createExternalStorage({
    required String provider,
    required String displayName,
    required String encryptedCredentials,
  }) async {
    await _runAction(FileOperation.addExternalStorage, () async {
      await _repository.createExternalStorage(
        provider: provider,
        displayName: displayName,
        encryptedCredentials: encryptedCredentials,
      );
      await showExternalStorage();
    });
  }

  Future<void> disableExternalStorage(ExternalStorageAccount account) async {
    await _runAction(FileOperation.disableExternalStorage, () async {
      await _repository.disableExternalStorage(account.id);
      await showExternalStorage();
    });
  }

  Future<void> deleteExternalStorage(ExternalStorageAccount account) async {
    await _runAction(FileOperation.deleteMount, () async {
      await _repository.deleteExternalStorage(account.id);
      await showExternalStorage();
    });
  }

  Future<void> updateExternalStorage({
    required String accountId,
    required String displayName,
    required String encryptedCredentials,
  }) async {
    await _runAction(FileOperation.updateExternalStorage, () async {
      await _repository.updateExternalStorage(
        accountId: accountId,
        displayName: displayName,
        encryptedCredentials: encryptedCredentials,
      );
      await showExternalStorage();
    });
  }

  Future<void> browseExternalStorage(
    String accountId, {
    String path = '/',
  }) async {
    await _loadExternalDirectory(
      accountId,
      path,
      operationLabel: FileOperation.browseRemoteDirectory,
      loadSpace: true,
    );
  }

  Future<void> browseExternalSubdirectory(String accountId, String path) async {
    await _loadExternalDirectory(
      accountId,
      path,
      operationLabel: FileOperation.openRemoteSubdirectory,
    );
  }

  void closeExternalBrowse() {
    _externalBrowseRequestGeneration++;
    final current = _currentState;
    if (current == null) {
      return;
    }
    _emitState(
      current.copyWith(
        externalFiles: const [],
        externalBrowsePath: null,
        externalBrowseAccountId: null,
        clearExternalSpace: true,
        isExternalBrowseLoading: false,
        clearExternalBrowseError: true,
      ),
    );
  }

  Future<void> _loadExternalDirectory(
    String accountId,
    String path, {
    required FileOperation operationLabel,
    bool loadSpace = false,
  }) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final requestGeneration = ++_externalBrowseRequestGeneration;
    _emitState(
      current.copyWith(
        externalFiles: const [],
        externalBrowsePath: path,
        externalBrowseAccountId: accountId,
        clearExternalSpace: loadSpace,
        isExternalBrowseLoading: true,
        clearExternalBrowseError: true,
      ),
    );

    try {
      await _runAction(operationLabel, () async {
        final spaceFuture =
            loadSpace
                ? _loadExternalSpaceSafely(accountId)
                : Future<ExternalSpaceUsage?>.value(
                  _currentState?.externalSpace,
                );
        final files = await _repository
            .browseExternalStorage(accountId, path)
            .timeout(_externalBrowseTimeout);
        final space = await spaceFuture;
        if (requestGeneration != _externalBrowseRequestGeneration) {
          return;
        }
        final latest = _currentState;
        if (latest == null) {
          return;
        }
        if (latest.section != FileManagerSection.externalStorage ||
            latest.externalBrowseAccountId != accountId ||
            latest.externalBrowsePath != path) {
          _emitState(latest.copyWith(isExternalBrowseLoading: false));
          return;
        }
        _emitState(
          latest.copyWith(
            externalFiles: files,
            externalBrowsePath: path,
            externalBrowseAccountId: accountId,
            externalSpace: space,
            isExternalBrowseLoading: false,
            clearExternalBrowseError: true,
          ),
        );
      });
    } catch (error) {
      if (requestGeneration == _externalBrowseRequestGeneration) {
        final latest = _currentState;
        if (latest != null) {
          _emitState(
            latest.copyWith(
              isExternalBrowseLoading: false,
              externalBrowseError: describeUserFacingError(error).message,
            ),
          );
        }
      }
      rethrow;
    }
  }

  Future<ExternalSpaceUsage?> _loadExternalSpaceSafely(String accountId) async {
    try {
      return await _repository
          .getExternalStorageSpace(accountId)
          .timeout(_externalBrowseTimeout);
    } on Exception {
      return null;
    }
  }

  /// 测试外部存储连接。
  Future<void> testExternalStorageConnection(String accountId) async {
    await _repository
        .testExternalStorageConnection(accountId)
        .timeout(_externalBrowseTimeout);
    await showExternalStorage();
  }

  Future<void> createImportTask(
    String accountId,
    String sourcePath, {
    required String sourceKind,
    String? spaceType,
  }) async {
    await _runAction(FileOperation.createImportTask, () async {
      final current = _currentState;
      final isShared = spaceType == 'SHARED';
      final task = await _repository.createImportTask(
        accountId,
        sourcePath: sourcePath,
        sourceKind: sourceKind,
        targetParentId: isShared ? null : current?.parentId,
        spaceType: spaceType ?? 'PERSONAL',
      );
      if (current != null) {
        _emitState(
          current.copyWith(
            importTasks: [
              task,
              ...current.importTasks.where((item) => item.id != task.id),
            ],
            section: FileManagerSection.importTasks,
          ),
        );
      }
    });
    await showImportTasks();
  }

  Future<void> showImportTasks() async {
    await _runAction(FileOperation.loadImportTasks, () async {
      final current = _currentState;
      final tasks = await _repository.listImportTasks();
      _emitState(
        (current ?? const FileBrowserState(files: [], recycleBin: [])).copyWith(
          importTasks: tasks,
          section: FileManagerSection.importTasks,
        ),
      );
    });
    _startImportTaskPolling();
  }

  Future<bool> refreshImportTasksForRealtime() async {
    final current = _currentState;
    if (current == null || current.section != FileManagerSection.importTasks) {
      return false;
    }
    final tasks = await _repository.listImportTasks();
    _emitState(current.copyWith(importTasks: tasks));
    _startImportTaskPolling();
    return true;
  }

  void _startImportTaskPolling() {
    final current = _currentState;
    final shouldPoll =
        current != null &&
        current.section == FileManagerSection.importTasks &&
        current.importTasks.any((task) => task.isActive);
    if (!shouldPoll) {
      _stopImportTaskPolling();
      return;
    }
    _importTaskPollTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshImportTasksForPolling()),
    );
  }

  void _stopImportTaskPolling() {
    _importTaskPollTimer?.cancel();
    _importTaskPollTimer = null;
  }

  Future<void> _refreshImportTasksForPolling() async {
    final current = _currentState;
    if (current == null || current.section != FileManagerSection.importTasks) {
      _stopImportTaskPolling();
      return;
    }
    try {
      final tasks = await _repository.listImportTasks();
      final latest = _currentState;
      if (latest == null || latest.section != FileManagerSection.importTasks) {
        _stopImportTaskPolling();
        return;
      }
      _emitState(latest.copyWith(importTasks: tasks));
    } on Exception {
      // 实时通道仍可继续推送状态，轮询失败不覆盖当前任务数据。
    }
    _startImportTaskPolling();
  }

  void _startUploadQueuePolling() {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final hasActive = current.localUploadTasks.any(
      (task) => !FileBrowserState.isTerminalUploadStatus(task.status),
    );
    if (hasActive) {
      if (_uploadQueuePollTimer != null) {
        return;
      }
      _uploadQueuePollTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refreshUploadQueueForBadge(),
      );
    } else {
      _stopUploadQueuePolling();
    }
  }

  void _stopUploadQueuePolling() {
    _uploadQueuePollTimer?.cancel();
    _uploadQueuePollTimer = null;
  }

  Future<void> _refreshUploadQueueForBadge() async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    try {
      final uploadQueue = await _repository.listUploadQueue();
      _emitState(current.copyWith(uploadQueue: uploadQueue));
    } on Exception {
      // 轮询失败不中断流程
    }
    _startUploadQueuePolling();
  }

  Future<void> cancelImportTask(ImportTask task) async {
    if (!task.canCancel) {
      return;
    }
    await _runAction(FileOperation.cancelImportTask, () async {
      final current = _currentState;
      if (current != null) {
        _emitState(
          current.copyWith(
            importTasks:
                current.importTasks
                    .map(
                      (item) =>
                          item.id == task.id
                              ? item.copyWith(status: 'CANCELLING')
                              : item,
                    )
                    .toList(),
          ),
        );
      }
      await _repository.cancelImportTask(task.id);
      await showImportTasks();
    });
  }

  Future<void> deleteImportTask(ImportTask task) async {
    await _runAction(FileOperation.deleteImportTask, () async {
      await _repository.cancelImportTask(task.id);
      await showImportTasks();
    });
  }
}
