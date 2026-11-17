import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
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

/// 通知动作的跳转方式。
///
/// 目标是壳层四空间之一（分支路由）时必须 `go`：通知中心与工具页都挂在
/// `StatefulShellRoute` 之外的根级导航上，`push` 一条分支路由会让 go_router
/// 再压入**第二个**壳层页面，Navigator 在 `_debugCheckDuplicatedPageKeys`
/// 断言 `!keyReservation.contains(key)` 并让整棵内容树失去渲染（实测：断言抛出后
/// chrome、目标分支与来源页三者都不在树上）。四空间是同级目标，按导航规程走 go。
/// 其余目标（模块页 `/video`、`/profile` 这类根级路由）继续 push，保住系统返回
/// 能落回通知中心。
void navigateNotificationAction(BuildContext context, String route) {
  final location = route.split('?').first;
  const shellBranchLocations = <String>{
    '/portal',
    '/library',
    '/reader',
    '/files',
  };
  if (shellBranchLocations.contains(location)) {
    context.go(route);
    return;
  }
  context.push(route);
}
