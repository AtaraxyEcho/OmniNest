part of 'admin_users_page.dart';

/// 批量启用/禁用：确认后走后端逐项端点，失败项不中断其余用户；
/// 完成反馈复用任务批量口径（成功/失败计数），有逐项原因时再展开明细。
Future<void> _batchUpdateUserStatus(
  BuildContext context,
  WidgetRef ref,
  List<AdminUser> targets, {
  required bool disabling,
}) async {
  if (targets.isEmpty) {
    return;
  }
  final l10n = AppLocalizations.of(context);
  final confirmed = await showWorkstationConfirmDialog(
    context,
    title: disabling ? l10n.adminBatchDisableUsers : l10n.adminBatchEnableUsers,
    message:
        disabling
            ? l10n.adminBatchDisableConfirmMessage('${targets.length}')
            : l10n.adminBatchEnableConfirmMessage('${targets.length}'),
    confirmLabel: disabling ? l10n.adminDisable : l10n.adminEnabled,
    destructive: disabling,
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  try {
    final result = await ref
        .read(adminUserControllerProvider.notifier)
        .batchUpdateUserStatus(
          targets.map((user) => user.id).toList(),
          disabling ? AdminUserStatus.disabled : AdminUserStatus.active,
        );
    if (!context.mounted) {
      return;
    }
    showOmniFeedback(
      context,
      l10n.adminBatchCompleted(result.successCount, result.failedIds.length),
      severity:
          result.failedIds.isEmpty
              ? OmniFeedbackSeverity.success
              : OmniFeedbackSeverity.warning,
    );
    if (result.failureReasons.isNotEmpty) {
      await _showBatchFailureReasons(context, targets, result.failureReasons);
    }
  } catch (error) {
    if (context.mounted) {
      showOmniFeedback(
        context,
        describeUserFacingError(error, l10n: l10n).message,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }
}

/// 展示后端返回的逐项失败原因，避免管理端只看到失败数量。
Future<void> _showBatchFailureReasons(
  BuildContext context,
  List<AdminUser> targets,
  Map<String, String> reasons,
) async {
  final l10n = AppLocalizations.of(context);
  final rows = <Widget>[
    for (final target in targets)
      if (reasons.containsKey(target.id))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('${target.title}: ${reasons[target.id]}'),
        ),
  ];
  if (rows.isEmpty) {
    return;
  }
  await showWorkstationDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(l10n.adminTaskErrorSummary),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.coreClose),
            ),
          ],
        ),
  );
}
