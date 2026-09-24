import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/widgets/hover_scale.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';

/// 通知入口与未读数量。任务队列不在普通用户视野内，由管理端按归属人处理。
class NotificationIcon extends ConsumerWidget {
  const NotificationIcon({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadCountProvider);
    final colors = context.globalColors;
    return HoverScale(
      child: IconButton(
        tooltip: AppLocalizations.of(context).notificationTitle,
        onPressed: () => context.push('/notifications'),
        // 悬停反馈统一由 HoverScale 缩放承担，屏蔽默认置色蒙层。
        hoverColor: Colors.transparent,
        icon: Badge(
          isLabelVisible: unreadCount > 0,
          label: Text(
            unreadCount > 99 ? '99+' : '$unreadCount',
            style: TextStyle(
              // ignore: font_size_whitelist
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: colors.onError,
            ),
          ),
          backgroundColor: colors.error,
          child: Icon(
            Icons.notifications_none_rounded,
            size: size,
            color: color,
          ),
        ),
      ),
    );
  }
}
