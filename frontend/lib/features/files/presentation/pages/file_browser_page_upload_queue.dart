part of 'file_browser_page.dart';

/// 上传队列、外部存储与导入任务三个子页工作区
/// （自 file_browser_page_subpage 拆出）。

class _UploadQueueWorkspace extends ConsumerWidget {
  const _UploadQueueWorkspace({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final localUploadIds =
        state.localUploadTasks
            .map((task) => task.uploadId)
            .whereType<String>()
            .toSet();
    final serverQueue =
        state.uploadQueue
            .where((item) => !localUploadIds.contains(item.uploadId))
            .toList();
    final localActive = state.inlineUploadTasks.length;
    final serverActive =
        serverQueue
            .where(
              (item) => !FileBrowserState.isTerminalUploadStatus(item.status),
            )
            .length;
    final completed =
        serverQueue
            .where((item) => item.status.toUpperCase() == 'COMPLETED')
            .length;
    final failed =
        serverQueue
            .where((item) => item.status.toUpperCase() == 'FAILED')
            .length;
    final locale = Localizations.localeOf(context).toString();
    if (MobileShellScope.isHosted(context)) {
      // 托管态不渲染工位指标条、四列表格与分页条，改用原型传输页。
      return _HostedUploadQueue(
        l10n: l10n,
        localTasks: state.localUploadTasks,
        serverItems: serverQueue,
        loadedCount: math.min(
          state.uploadQueueMeta.totalElements,
          (state.uploadQueueMeta.page + 1) * state.uploadQueueMeta.size,
        ),
        totalCount: state.uploadQueueMeta.totalElements,
        busy: state.isBusy,
        onLoadNext:
            () => controller.showUploadQueue(
              page: state.uploadQueueMeta.page + 1,
            ),
        onPauseLocal: (task) async {
          controller.pauseLocalUploadTask(task.id);
        },
        onResumeLocal: (task) async {
          await controller.resumeLocalUploadTask(task.id);
        },
        onRemoveLocal: (task) async {
          await controller.removeLocalUploadTask(task.id);
        },
        onCancelServer: (item) async {
          await controller.deleteServerUploadSession(item);
        },
        onRebindServer:
            (item) =>
                _pickAndRebindServerUpload(context, item, controller, l10n),
        onRestartServer:
            (item) =>
                _pickAndRestartStaleUpload(context, item, controller, l10n),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          title: FileManagerSection.uploadQueue.labelOf(l10n),
          subtitle: FileManagerSection.uploadQueue.descriptionOf(l10n),
        ),
        const SizedBox(height: 16),
        _SubMetricStrip(
          cards: [
            _MetricCard(
              label: l10n.filesMetricUploading,
              value: localActive.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.success,
            ),
            _MetricCard(
              label: l10n.filesMetricQueued,
              value: serverActive.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricCompleted,
              value: completed.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricFailed,
              value: failed.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.error,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _SubTable.builder(
            columns: [
              _SubColumn(l10n.filesColumnName, flex: 3),
              _SubColumn(l10n.filesUploadOrigin, width: 72),
              _SubColumn(l10n.filesColumnSize, width: 96),
              _SubColumn(l10n.filesProgress, flex: 2),
              _SubColumn(l10n.filesColumnStatus, width: 96),
              _SubColumn(l10n.filesColumnUpdatedAt, width: 108),
              _SubColumn(l10n.filesColumnExpiresAt, width: 108),
              _SubColumn(l10n.filesFileActions, width: 140),
            ],
            rowCount: state.localUploadTasks.length + serverQueue.length,
            rowBuilder: (context, index) {
              final localTasks = state.localUploadTasks;
              if (index < localTasks.length) {
                final task = localTasks[index];
                return _SubRow(
                  cells: [
                    _SubNameCell(
                      name: task.fileName,
                      detail: task.message ?? task.status,
                      isFolder: false,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _StatusBadge(l10n.filesUploadOriginLocal),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: _SubMono(formatFileSize(task.sizeBytes)),
                    ),
                    _UploadProgressCell(
                      value: task.progress,
                      primary: '${(task.progress * 100).toInt()}%',
                      detail:
                          '${formatFileSize(task.uploadedBytes)} / '
                          '${formatFileSize(task.sizeBytes)}'
                          '${task.messageCurrent != null && task.messageTotal != null ? ' · ${task.messageCurrent}/${task.messageTotal}' : ''}',
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _StatusBadge(
                        _uploadStatusLabel(l10n, task.status),
                        tone: _uploadStatusTone(task.status),
                      ),
                    ),
                    _SubMono('—'),
                    _SubMono('—'),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (task.status == 'PAUSED')
                          _SubAction(
                            label: l10n.filesResumeUpload,
                            onTap:
                                enabled
                                    ? () => _runFileAction(
                                      context,
                                      () => controller.resumeLocalUploadTask(
                                        task.id,
                                      ),
                                    )
                                    : null,
                          )
                        else if (task.status == 'RUNNING' ||
                            task.status == 'UPLOADING' ||
                            task.status == 'PENDING' ||
                            task.status == 'QUEUED')
                          _SubAction(
                            label: l10n.filesPauseUpload,
                            onTap:
                                enabled
                                    ? () => _runFileAction(
                                      context,
                                      () async => controller
                                          .pauseLocalUploadTask(task.id),
                                    )
                                    : null,
                          ),
                        const SizedBox(width: 6),
                        _SubAction(
                          label: l10n.filesDeleteTask,
                          destructive: true,
                          onTap:
                              enabled
                                  ? () => _confirmAndRun(
                                    context,
                                    title: l10n.filesDeleteUploadTask,
                                    message: l10n.filesDeleteUploadTaskMessage,
                                    confirmLabel: l10n.filesDeleteTask,
                                    action:
                                        () => controller.removeLocalUploadTask(
                                          task.id,
                                        ),
                                  )
                                  : null,
                        ),
                      ],
                    ),
                  ],
                );
              }
              final item = serverQueue[index - localTasks.length];
              return _SubRow(
                cells: [
                  _SubNameCell(
                    name: item.fileName,
                    detail:
                        item.expiresAt == null
                            ? '—'
                            : DateFormat(
                              'yyyy-MM-dd HH:mm',
                              Localizations.localeOf(context).toString(),
                            ).format(item.expiresAt!),
                    isFolder: false,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusBadge(l10n.filesUploadOriginServer),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: _SubMono(formatFileSize(item.sizeBytes)),
                  ),
                  _UploadProgressCell(
                    value: item.progress,
                    primary: '${(item.progress * 100).toInt()}%',
                    detail:
                        '${item.uploadedParts}/${item.totalParts} '
                        '${l10n.filesUploadPartsUnit}',
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusBadge(
                      _uploadStatusLabel(l10n, item.status),
                      tone: _uploadStatusTone(item.status),
                    ),
                  ),
                  _SubMono(
                    item.updatedAt == null
                        ? '—'
                        : DateFormat(
                          'MM-dd HH:mm',
                          locale,
                        ).format(item.updatedAt!),
                  ),
                  _SubMono(
                    item.expiresAt == null
                        ? '—'
                        : DateFormat(
                          'yyyy-MM-dd',
                          locale,
                        ).format(item.expiresAt!),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.totalParts > 1 &&
                          !_isUploadSessionStale(item) &&
                          (item.status.toUpperCase() == 'CREATED' ||
                              item.status.toUpperCase() == 'UPLOADING'))
                        _SubAction(
                          label: l10n.filesRebindUpload,
                          onTap:
                              enabled
                                  ? () => _pickAndRebindServerUpload(
                                    context,
                                    item,
                                    controller,
                                    l10n,
                                  )
                                  : null,
                        ),
                      if (_isUploadSessionStale(item))
                        _SubAction(
                          label: l10n.filesRebindUploadRestart,
                          onTap:
                              enabled
                                  ? () => _pickAndRestartStaleUpload(
                                    context,
                                    item,
                                    controller,
                                    l10n,
                                  )
                                  : null,
                        ),
                      _SubAction(
                        label: l10n.filesCancel,
                        destructive: true,
                        onTap:
                            enabled &&
                                    !FileBrowserState.isTerminalUploadStatus(
                                      item.status,
                                    )
                                ? () => _runFileAction(
                                  context,
                                  () => controller.deleteServerUploadSession(
                                    item,
                                  ),
                                )
                                : null,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        WorkstationPaginationBar(
          currentPage: state.uploadQueueMeta.page,
          totalPages: state.uploadQueueMeta.totalPages,
          totalElements: state.uploadQueueMeta.totalElements,
          rowsPerPage: state.uploadQueueMeta.size,
          busy: state.isBusy,
          onPageChanged: (page) => controller.showUploadQueue(page: page),
          onRowsPerPageChanged:
              (size) => controller.showUploadQueue(page: 0, size: size),
        ),
      ],
    );
  }

  Future<void> _pickAndRebindServerUpload(
    BuildContext context,
    FileUploadQueueItem item,
    FileBrowserController controller,
    AppLocalizations l10n,
  ) async {
    if (_isUploadSessionStale(item)) {
      // 队列渲染后会话可能刚好到期：继续延期只会拿到后端「已过期」，改走新上传。
      await _pickAndRestartStaleUpload(context, item, controller, l10n);
      return;
    }
    final picked = await openFile();
    if (picked == null || !context.mounted) {
      return;
    }
    final size = await picked.length();
    if (!context.mounted) {
      return;
    }
    if (size != item.sizeBytes) {
      showOmniFeedback(
        context,
        l10n.filesRebindUploadSizeMismatch,
        severity: OmniFeedbackSeverity.error,
      );
      return;
    }
    if (picked.name != item.fileName) {
      final confirmed = await showFilesConfirmDialog(
        context,
        title: l10n.filesRebindUpload,
        message: l10n.filesRebindUploadNameMismatch,
        confirmLabel: l10n.filesRebindUpload,
      );
      if (!confirmed || !context.mounted) {
        return;
      }
    }
    await _runFileAction(
      context,
      () => controller.rebindServerUploadSession(item, picked),
    );
  }

  /// 会话已过期或已失败：无法续传，用重新选择的文件按当前目录开一次新上传。
  Future<void> _pickAndRestartStaleUpload(
    BuildContext context,
    FileUploadQueueItem item,
    FileBrowserController controller,
    AppLocalizations l10n,
  ) async {
    final picked = await openFile();
    if (picked == null || !context.mounted) {
      return;
    }
    final size = await picked.length();
    if (!context.mounted) {
      return;
    }
    final isSameFile = picked.name == item.fileName && size == item.sizeBytes;
    final confirmed = await showFilesConfirmDialog(
      context,
      title: l10n.filesRebindUploadRestart,
      message:
          isSameFile
              ? l10n.filesRebindUploadExpired
              : l10n.filesRebindUploadRestartMismatch,
      confirmLabel: l10n.filesRebindUploadRestart,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await _uploadFiles(context, controller, [picked]);
  }
}

/// 服务端会话是否已无法续传：状态终局，或状态未及更新但到期时间已过。
bool _isUploadSessionStale(FileUploadQueueItem item) {
  final status = item.status.toUpperCase();
  if (status == 'EXPIRED' || status == 'FAILED') {
    return true;
  }
  final expiresAt = item.expiresAt;
  return (status == 'CREATED' || status == 'UPLOADING') &&
      expiresAt != null &&
      expiresAt.isBefore(DateTime.now());
}
