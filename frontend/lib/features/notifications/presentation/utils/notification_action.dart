import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';

/// 通知卡动作链接：目标路由 + 本地化标签。
class NotificationAction {
  const NotificationAction({required this.label, required this.route});

  final String label;
  final String route;
}

/// 按通知类型解析动作链接。
///
/// 服务端 metadata 各调用方载荷不一（taskId / shareId 等），跳转先按
/// 类型级默认目标路由；未知类型返回 null（不渲染链接）。
NotificationAction? notificationActionFor(
  NotificationDto notification,
  AppLocalizations l10n,
) {
  return switch (notification.type) {
    'TASK_COMPLETED' || 'TASK_FAILED' => NotificationAction(
      label: l10n.notificationActionViewFiles,
      route: '/files',
    ),
    'SHARE_ACCESS' || 'SHARE_ACCESSED' => NotificationAction(
      label: l10n.notificationActionViewShares,
      route: '/files',
    ),
    'MEDIA_SCRAPED' => NotificationAction(
      label: l10n.notificationActionOpenMedia,
      route: '/video',
    ),
    'QUOTA_WARNING' => NotificationAction(
      label: l10n.notificationActionViewFiles,
      route: '/files',
    ),
    'NEW_DEVICE_LOGIN' || 'PASSWORD_CHANGED' => NotificationAction(
      label: l10n.notificationActionManageSessions,
      route: '/profile?section=security',
    ),
    _ => null,
  };
}
