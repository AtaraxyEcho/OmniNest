part of 'file_browser_controller.dart';

const _externalBrowseTimeout = Duration(seconds: 30);

extension FileBrowserIntegrationActions on FileBrowserController {
  Future<ExternalStorageAccount> createExternalStorage({
    required String provider,
    required String displayName,
    required String encryptedCredentials,
  }) async {
    return _runAction(FileOperation.addExternalStorage, () async {
      final account = await _repository.createExternalStorage(
        provider: provider,
        displayName: displayName,
        encryptedCredentials: encryptedCredentials,
      );
      await showExternalStorage();
      return account;
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
    int? page,
    int? size,
  }) async {
    await _loadExternalDirectory(
      accountId,
      path,
      operationLabel: FileOperation.browseRemoteDirectory,
      loadSpace: true,
      page: page,
      size: size,
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
    int? page,
    int? size,
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
        final externalMeta =
            _currentState?.externalMeta ?? const FilesSubPageMeta();
        final browseResult = await _repository
            .browseExternalStoragePage(
              accountId,
              path,
              page: page ?? 0,
              size: size ?? externalMeta.size,
            )
            .timeout(_externalBrowseTimeout);
        final files = browseResult.items;
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
            externalMeta: browseResult.meta,
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

  /// 外部存储浏览滚动续载：同目录下一页按路径去重后追加。与
  /// `_loadExternalDirectory` 不同，续载不清空已列条目、不进 loading 态，
  /// 只借用同一代际号丢弃被目录切换作废的回包。
  Future<void> loadMoreExternalBrowse() async {
    final current = _currentState;
    if (current == null ||
        current.isBusy ||
        current.externalFiles.length >= current.externalMeta.totalElements ||
        current.externalBrowseAccountId == null) {
      return;
    }
    final accountId = current.externalBrowseAccountId!;
    final path = current.externalBrowsePath ?? '/';
    final meta = current.externalMeta;
    final requestGeneration = ++_externalBrowseRequestGeneration;
    await _runAction(FileOperation.browseRemoteDirectory, () async {
      final result = await _repository
          .browseExternalStoragePage(
            accountId,
            path,
            page: meta.page + 1,
            size: meta.size,
          )
          .timeout(_externalBrowseTimeout);
      if (requestGeneration != _externalBrowseRequestGeneration) {
        return;
      }
      final latest = _currentState;
      if (latest == null ||
          latest.externalBrowseAccountId != accountId ||
          latest.externalBrowsePath != path ||
          latest.externalMeta.page != meta.page) {
        return;
      }
      final loaded = latest.externalFiles;
      final seen = loaded.map((item) => item.path).toSet();
      _emitState(
        latest.copyWith(
          externalFiles: <ExternalFileItem>[
            ...loaded,
            ...result.items.where((item) => seen.add(item.path)),
          ],
          externalMeta: result.meta,
        ),
      );
    });
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

  /// 开始 OAuth 授权并返回授权 URL。
  Future<String> startExternalOAuth({
    required String connectorCode,
    required String accountId,
  }) {
    return _repository
        .startExternalOAuth(connectorCode: connectorCode, accountId: accountId)
        .timeout(const Duration(seconds: 20));
  }

  Future<void> createImportTask(
    String accountId,
    String sourcePath, {
    required String sourceKind,
    String? spaceType,
  }) async {
    await _runAction(FileOperation.createImportTask, () async {
      final current = _currentState;
      final targetSpace = spaceType ?? 'PERSONAL';
      // 目标父目录只在“导入到当前空间”时有效：跨空间导入必须落到目标空间根目录，
      // 否则会把另一空间的文件夹 ID 传给后端。
      final sameSpace = targetSpace == (current?.spaceType ?? 'PERSONAL');
      final task = await _repository.createImportTask(
        accountId,
        sourcePath: sourcePath,
        sourceKind: sourceKind,
        targetParentId: sameSpace ? current?.parentId : null,
        spaceType: targetSpace,
      );
      final live = _liveOr(current);
      _emitState(
        live.copyWith(
          importTasks: [
            task,
            ...live.importTasks.where((item) => item.id != task.id),
          ],
        ),
      );
    });
    await showImportTasks();
  }

  Future<void> showImportTasks({int? page, int? size}) async {
    _applySectionOptimistically(FileManagerSection.importTasks);
    await _runAction(FileOperation.loadImportTasks, () async {
      final current = _currentState;
      final meta = current?.importMeta ?? const FilesSubPageMeta();
      final result = await _repository.listImportTasksPage(
        page: page ?? 0,
        size: size ?? meta.size,
      );
      _emitState(
        _liveOr(current).copyWith(
          importTasks: result.items,
          importMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
        ),
      );
    });
    _startImportTaskPolling();
  }

  /// 导入任务滚动续载：下一页按任务 id 去重后追加，续载后继续轮询进度。
  Future<void> loadMoreImportTasks() async {
    final current = _currentState;
    if (current == null ||
        current.isBusy ||
        current.importTasks.length >= current.importMeta.totalElements) {
      return;
    }
    final meta = current.importMeta;
    await _runAction(FileOperation.loadImportTasks, () async {
      final result = await _repository.listImportTasksPage(
        page: meta.page + 1,
        size: meta.size,
      );
      final latest = _currentState;
      if (latest == null || latest.importMeta.page != meta.page) {
        return;
      }
      final loaded = latest.importTasks;
      final seen = loaded.map((task) => task.id).toSet();
      _emitState(
        latest.copyWith(
          importTasks: <ImportTask>[
            ...loaded,
            ...result.items.where((task) => seen.add(task.id)),
          ],
          importMeta: FilesSubPageMeta(
            page: result.page,
            size: result.size,
            totalElements: result.totalElements,
            totalPages: result.totalPages,
          ),
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
    _emitState(_liveOr(current).copyWith(importTasks: tasks));
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
      _emitState(_liveOr(current).copyWith(uploadQueue: uploadQueue));
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
