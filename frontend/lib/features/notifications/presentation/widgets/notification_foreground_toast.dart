import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/router.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/features/notifications/application/notification_foreground_presenter.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_type_l10n.dart';

/// 根部挂载的前台通知提示：实时通知到达时经全局反馈门面展示顶部居中
/// 提示条，点击「查看」跳转通知中心。
///
/// 呈现完全不经 ScaffoldMessenger/SnackBar：桌面端各分支页与被推入的
/// 根级页面会同时注册多个根 Scaffold，同一条 SnackBar 被多处挂载，而
/// SnackBar 的 Hero tag 由内容字符串派生，路由切换的 Hero 遍历会命中
/// 多个同名 Hero 触发断言；门面自管的 Overlay 体系不参与 Hero。同文案
/// 通知由门面按键合并并重置计时，不同通知按门面堆叠上限共存。通知页
/// 打开期间抑制（同屏冗余）。是否弹出、是否带正文、是否出声一律取服务端
/// 通知偏好，本地快照仅作首帧缓存。
class NotificationForegroundToast extends ConsumerWidget {
  const NotificationForegroundToast({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(notificationForegroundEventsStreamProvider, (previous, next) {
      final notification = next.asData?.value;
      if (notification == null) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      unawaited(_present(context, ref, notification));
    });
    return child;
  }

  Future<void> _present(
    BuildContext context,
    WidgetRef ref,
    NotificationDto notification,
  ) async {
    // 横幅真值取服务端通知偏好：必须等偏好读出再判定，读不到才按默认放行。
    // 本地快照只是首帧缓存，不能用设备级 SharedPreferences 另立一套开关。
    NotificationPreferences? prefs;
    try {
      prefs = await ref.read(notificationPreferencesProvider.future);
    } on Object {
      prefs = null;
    }
    if (!context.mounted) {
      return;
    }
    if (prefs != null &&
        !prefs.presentsBannerFor(notification.type, at: DateTime.now())) {
      return;
    }
    // Toast 挂在 MaterialApp.builder，位于 GoRouter 之上，GoRouter.of 会抛
    // 「No GoRouter found」；优先用当前 context，否则回退应用级路由实例。
    final GoRouter router =
        GoRouter.maybeOf(context) ?? ref.read(appRouterProvider);
    if (router.routeInformationProvider.value.uri.path == '/notifications') {
      return;
    }
    final l10n = AppLocalizations.of(context);
    // 关闭预览只报「有新通知」，不带正文；查看入口保留。
    final title =
        (prefs?.showPreview ?? true)
            ? notification.title ??
                notification.message ??
                synthesizedNotificationText(notification, l10n) ??
                ''
            : l10n.notificationContentHidden;
    if (title.isEmpty) {
      return;
    }
    // 提示音跟随通知偏好（默认开启）；用系统提示声，Web 平台为静音空实现。
    if (prefs?.sound ?? true) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    showOmniFeedback(
      context,
      title,
      actionLabel: AppLocalizations.of(context).notificationForegroundToastView,
      // push：通知是打断，看完要能回到被打断的那一页。
      onAction: () => router.push('/notifications'),
    );
  }
}
