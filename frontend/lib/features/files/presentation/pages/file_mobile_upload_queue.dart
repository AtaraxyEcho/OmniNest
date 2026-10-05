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
  });

  final AppLocalizations l10n;
  final List<FileUploadClientTask> localTasks;
  final List<FileUploadQueueItem> serverItems;
  final int loadedCount;
  final int totalCount;
  final bool busy;
  final VoidCallback onLoadNext;

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
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
