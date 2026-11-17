/// 任务队列页配套弹窗与状态映射：从 admin_operations_logs_tasks.dart
/// 拆出，控制单文件规模（>800 行规划拆分）。
part of 'admin_operations_pages.dart';

/// 任务状态语义色：DISCARDED 为中性终态，与排队/取消一致不可重试。
AdminTagTone _taskStatusTone(String status) => switch (status) {
  'COMPLETED' => AdminTagTone.success,
  'RUNNING' => AdminTagTone.info,
  'FAILED' || 'DLQ' => AdminTagTone.error,
  'RETRY_WAIT' => AdminTagTone.warning,
  _ => AdminTagTone.neutral,
};

/// 任务状态本地化标签；未知枚举回退原始值。
String _taskStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'RUNNING' => l10n.adminTaskStatusRunning,
      'COMPLETED' => l10n.adminTaskStatusCompleted,
      'DLQ' => l10n.adminTaskStatusDlq,
      'FAILED' => l10n.statusScanFailed,
      'CANCELLED' => l10n.statusScanCancelled,
      'QUEUED' => l10n.statusScanQueued,
      'RETRY_WAIT' => l10n.adminTaskStatusRetryWait,
      'DISCARDED' => l10n.adminTaskStatusDiscarded,
      _ => status,
    };

/// 任务详情弹窗：处理器、队列、状态、重试轮次与错误摘要。
class _TaskDetailDialog extends StatelessWidget {
  const _TaskDetailDialog({required this.item});

  final AdminTaskRecord item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final errorSummary = item.errorSummary ?? '';
    return WorkstationDialogFrame(
      title: l10n.adminTaskDetailTitle,
      headerLabel: item.id.length >= 8 ? item.id.substring(0, 8) : item.id,
      width: 620,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailKeyValueRow(
            label: l10n.adminTaskFieldHandler,
            value: item.taskType,
            mono: true,
          ),
          _DetailKeyValueRow(
            label: l10n.adminTaskFieldQueue,
            value: item.routingKey ?? '-',
            mono: true,
          ),
          _DetailKeyValueRow(
            label: l10n.adminTaskExecutionStatus,
            child: AdminStatusTag(
              label: _taskStatusLabel(l10n, item.status),
              tone: _taskStatusTone(item.status),
            ),
          ),
          _DetailKeyValueRow(
            label: l10n.adminTaskFieldRetryCount,
            value: '${item.retryCount} / 3',
            mono: true,
          ),
          _DetailKeyValueRow(
            label: l10n.adminTaskUpdatedAt,
            value: item.updatedAt,
            mono: true,
          ),
          if (errorSummary.isNotEmpty) ...[
            const SizedBox(height: 6),
            WorkstationDialogSectionLabel(l10n.adminTaskErrorSummary),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: 0.08),
                border: Border.all(color: scheme.error.withValues(alpha: 0.45)),
              ),
              child: Text(
                errorSummary,
                style: TextStyle(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontSize: AppTypography.bodySmall,
                  height: 16 / 12,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coreClose),
        ),
      ],
    );
  }
}
