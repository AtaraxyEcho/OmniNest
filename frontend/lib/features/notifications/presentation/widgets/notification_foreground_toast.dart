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
import 'package:omninest/features/notifications/presentation/utils/notification_type_l10n.dart';

/// 根部挂载的前台通知提示：实时通知到达时经全局反馈门面展示顶部居中
/// 提示条，点击「查看」跳转通知中心。
///
/// 呈现完全不经 ScaffoldMessenger/SnackBar：桌面端各分支页与被推入的
/// 根级页面会同时注册多个根 Scaffold，同一条 SnackBar 被多处挂载，而
/// SnackBar 的 Hero tag 由内容字符串派生，路由切换的 Hero 遍历会命中
/// 多个同名 Hero 触发断言；门面自管的 Overlay 体系不参与 Hero。同文案
/// 通知由门面按键合并并重置计时，不同通知按门面堆叠上限共存。通知页
/// 打开期间抑制（同屏冗余）。开关为设备级本地偏好，默认开启。
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
      _present(context, ref, notification);
    });
    return child;
  }

  void _present(
    BuildContext context,
    WidgetRef ref,
    NotificationDto notification,
  ) {
    final enabled =
        ref.read(notificationForegroundToastEnabledProvider).asData?.value ??
        true;
    if (!enabled) {
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
    final title =
        notification.title ??
        notification.message ??
        synthesizedNotificationText(notification, l10n) ??
        '';
    if (title.isEmpty) {
      return;
    }
    // 提示音跟随通知偏好（默认开启）；用系统提示声，Web 平台为静音空实现。
    final soundEnabled =
        ref.read(notificationPreferencesProvider).asData?.value.sound ?? true;
    if (soundEnabled) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    showOmniFeedback(
      context,
      title,
      actionLabel: AppLocalizations.of(context).notificationForegroundToastView,
      onAction: () => router.go('/notifications'),
    );
  }
}
