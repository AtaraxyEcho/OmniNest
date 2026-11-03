part of 'notification_page.dart';

/// 通知列表的写操作：已读标记、翻页复位、批量已读、单条删除与清空。
///
/// 失败提示统一走 `failureToast`：保留动作文案，能映射出错误码的原因拼在后面，
/// 未映射的意外异常不把 toString 抛到界面上。
extension _NotificationPageActions on _NotificationPageState {
  void _markRead(NotificationDto notification) {
    if (!notification.read) {
      ref
          .read(notificationControllerProvider.notifier)
          .markRead(notification.id);
    }
  }

  Future<void> _goToPage(int page) async {
    await ref
        .read(notificationControllerProvider.notifier)
        .goToPage(page, size: _NotificationPageState._pageSize);
    if (mounted && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _markAllRead() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(notificationControllerProvider.notifier).markAllRead();
    } catch (error) {
      if (mounted) {
        showOmniFeedback(
          context,
          failureToast(l10n, l10n.notificationMarkAllReadFailed, error),
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }

  Future<void> _deleteNotification(NotificationDto notification) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(notificationControllerProvider.notifier)
          .deleteNotification(notification.id);
    } catch (error) {
      if (mounted) {
        showOmniFeedback(
          context,
          failureToast(l10n, l10n.notificationDeleteFailed, error),
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.notificationClearConfirmTitle,
      message: l10n.notificationClearConfirmMessage,
      confirmLabel: l10n.notificationClearAll,
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await ref.read(notificationControllerProvider.notifier).clearAll();
    } catch (error) {
      if (mounted) {
        showOmniFeedback(
          context,
          failureToast(l10n, l10n.notificationClearFailed, error),
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }
}
