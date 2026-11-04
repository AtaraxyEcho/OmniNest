part of 'file_browser_page.dart';

/// 托管态上传队列：原型 `.transfer-page`——三格摘要 + 进度行。
///
/// 本地分片任务与服务端上传会话合并展示，两者都提供真实字节与进度；摘要
/// 不预估剩余时间等取不到的数据。宿主分区体自带纵向滚动（下发无界高约束），
/// 因此这里只出内容：不套滚动体、不用 Expanded，横排也不取 stretch。
class _HostedUploadQueue extends StatelessWidget {
  const _HostedUploadQueue({
    required this.l10n,
    required this.localTasks,
    required this.serverItems,
    required this.loadedCount,
    required this.totalCount,
    required this.busy,
    required this.onLoadNext,
    this.onPauseLocal,
    this.onResumeLocal,
    this.onRemoveLocal,
    this.onCancelServer,
    this.onRebindServer,
    this.onRestartServer,
  });

  final AppLocalizations l10n;
  final List<FileUploadClientTask> localTasks;
  final List<FileUploadQueueItem> serverItems;
  final int loadedCount;
  final int totalCount;
  final bool busy;
  final VoidCallback onLoadNext;
  final Future<void> Function(FileUploadClientTask task)? onPauseLocal;
  final Future<void> Function(FileUploadClientTask task)? onResumeLocal;
  final Future<void> Function(FileUploadClientTask task)? onRemoveLocal;
  final Future<void> Function(FileUploadQueueItem item)? onCancelServer;
  final Future<void> Function(FileUploadQueueItem item)? onRebindServer;
  final Future<void> Function(FileUploadQueueItem item)? onRestartServer;

  static MobileStatusTone _toneOf(String status) {
    return switch (status.toUpperCase()) {
      'FAILED' ||
      'ERROR' ||
      'CANCELED' ||
      'CANCELLED' => MobileStatusTone.danger,
      'PAUSED' || 'PENDING' || 'EXPIRED' => MobileStatusTone.warning,
      _ => MobileStatusTone.calm,
    };
  }

  int get _activeCount {
    return localTasks
            .where(
              (task) => !FileBrowserState.isTerminalUploadStatus(task.status),
            )
            .length +
        serverItems
            .where(
              (item) => !FileBrowserState.isTerminalUploadStatus(item.status),
            )
            .length;
  }

  Widget? _localActions(BuildContext context, FileUploadClientTask task) {
    final status = task.status.toUpperCase();
    final actions = <Widget>[];
    if (status == 'QUEUED' ||
        status == 'UPLOADING' ||
        status == 'PENDING' ||
        status == 'RUNNING') {
      actions.add(
        MobileTransferAction(
          icon: Icons.pause_rounded,
          tooltip: l10n.filesPauseUpload,
          onTap:
              busy || onPauseLocal == null ? null : () => onPauseLocal!(task),
        ),
      );
    } else if (status == 'PAUSED' || status == 'FAILED') {
      actions.add(
        MobileTransferAction(
          icon: Icons.play_arrow_rounded,
          tooltip: l10n.filesResumeUpload,
          onTap:
              busy || onResumeLocal == null ? null : () => onResumeLocal!(task),
        ),
      );
    }
    actions.add(
      status == 'COMPLETED'
          ? MobileTransferAction(
            icon: Icons.delete_outline_rounded,
            tooltip: l10n.filesDeleteTask,
            onTap:
                busy || onRemoveLocal == null
                    ? null
                    : () => onRemoveLocal!(task),
          )
          : MobileTransferAction(
            icon: Icons.close_rounded,
            tooltip: l10n.filesCancel,
            destructive: true,
            onTap:
                busy || onRemoveLocal == null
                    ? null
                    : () => _confirmAndRemoveLocal(context, task),
          ),
    );
    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }

  Future<void> _confirmAndRemoveLocal(
    BuildContext context,
    FileUploadClientTask task,
  ) async {
    final confirmed = await showFilesConfirmDialog(
      context,
      title: l10n.filesDeleteUploadTask,
      message: l10n.filesDeleteUploadTaskMessage,
      confirmLabel: l10n.filesDeleteTask,
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await onRemoveLocal?.call(task);
  }

  Widget? _serverActions(BuildContext context, FileUploadQueueItem item) {
    final status = item.status.toUpperCase();
    final isStale = _isUploadSessionStale(item);
    final actions = <Widget>[
      if (item.totalParts > 1 &&
          !isStale &&
          (status == 'CREATED' || status == 'UPLOADING') &&
          onRebindServer != null)
        MobileTransferAction(
          icon: Icons.file_open_outlined,
          tooltip: l10n.filesRebindUpload,
          onTap: busy ? null : () => onRebindServer!(item),
        ),
      if (isStale && onRestartServer != null)
        MobileTransferAction(
          icon: Icons.upload_file_outlined,
          tooltip: l10n.filesRebindUploadRestart,
          onTap: busy ? null : () => onRestartServer!(item),
        ),
      if (!FileBrowserState.isTerminalUploadStatus(item.status) &&
          onCancelServer != null)
        MobileTransferAction(
          icon: Icons.close_rounded,
          tooltip: l10n.filesCancel,
          destructive: true,
          onTap: busy ? null : () => _confirmAndCancelServer(context, item),
        ),
    ];
    return actions.isEmpty
        ? null
        : Row(mainAxisSize: MainAxisSize.min, children: actions);
  }

  Future<void> _confirmAndCancelServer(
    BuildContext context,
    FileUploadQueueItem item,
  ) async {
    final confirmed = await showFilesConfirmDialog(
      context,
      title: l10n.filesCancelUploadSessionTitle,
      message: l10n.filesCancelUploadSessionMessage,
      confirmLabel: l10n.filesCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await onCancelServer?.call(item);
  }

  int _countByStatus(String status) {
    final upper = status.toUpperCase();
    return localTasks
            .where((task) => task.status.toUpperCase() == upper)
            .length +
        serverItems.where((item) => item.status.toUpperCase() == upper).length;
  }

  @override
  Widget build(BuildContext context) {
    final hasMore = loadedCount < totalCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HostedSectionMetaRow(
          text: l10n.filesUploadQueueDesc,
          action:
              hasMore
                  ? _HostedPillAction(
                    icon: Icons.expand_more_rounded,
                    label: l10n.filesUploadQueueLoadMore(
                      '$loadedCount',
                      '$totalCount',
                    ),
                    onTap: onLoadNext,
                  )
                  : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileTransferSummary(
                entries: [
                  MobileTransferSummaryEntry(
                    value: '$_activeCount',
                    label: l10n.filesUploadQueueSummaryActive,
                  ),
                  MobileTransferSummaryEntry(
                    value: '${_countByStatus('COMPLETED')}',
                    label: l10n.filesUploadQueueSummaryCompleted,
                  ),
                  MobileTransferSummaryEntry(
                    value: '${_countByStatus('FAILED')}',
                    label: l10n.filesUploadQueueSummaryFailed,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (localTasks.isEmpty && serverItems.isEmpty)
                EnvEmptyState(
                  icon: OmniIcons.queue,
                  title: l10n.filesUploadQueueEmptyTitle,
                  message: l10n.filesUploadQueueEmptyMessage,
                )
              else ...[
                for (final task in localTasks)
                  MobileTransferRow(
                    icon: OmniIcons.queue,
                    title: task.fileName,
                    detail:
                        '${formatFileSize(task.uploadedBytes)} / '
                        '${formatFileSize(task.sizeBytes)}',
                    progress: task.progress,
                    statusLabel: _uploadStatusLabel(l10n, task.status),
                    tone: _toneOf(task.status),
                    trailingActions: _localActions(context, task),
                  ),
                for (final item in serverItems)
                  MobileTransferRow(
                    icon: OmniIcons.queue,
                    title: item.fileName,
                    detail:
                        '${formatFileSize((item.sizeBytes * item.progress).round())} / '
                        '${formatFileSize(item.sizeBytes)}',
                    progress: item.progress,
                    statusLabel: _uploadStatusLabel(l10n, item.status),
                    tone: _toneOf(item.status),
                    trailingActions: _serverActions(context, item),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
