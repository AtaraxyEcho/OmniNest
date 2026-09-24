import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/notifications/application/notification_foreground_presenter.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';

/// 根部挂载的前台通知提示：实时通知到达时展示轻量 SnackBar，点击跳转
/// 通知中心。通知页与通知与任务中心打开期间抑制（同屏冗余）；提示展示期间
/// 新到达合并为最新一条（重置计时并更新内容）。开关为设备级本地偏好，
/// 默认开启。
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
    final router = GoRouter.of(context);
    final path = router.routeInformationProvider.value.uri.path;
    if (path == '/notifications') {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final title = notification.title ?? notification.message ?? '';
    if (title.isEmpty) {
      return;
    }
    // 提示音跟随通知偏好（默认开启）；用系统提示音，Web 平台为静音空实现。
    final soundEnabled =
        ref.read(notificationPreferencesProvider).asData?.value.sound ?? true;
    if (soundEnabled) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(title),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: l10n.notificationForegroundToastView,
          onPressed: () => router.go('/notifications'),
        ),
      ),
    );
  }
}
