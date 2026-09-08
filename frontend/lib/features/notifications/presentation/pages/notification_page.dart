import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_type_l10n.dart';

class NotificationPage extends ConsumerStatefulWidget {
  const NotificationPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  ConsumerState<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends ConsumerState<NotificationPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(notificationControllerProvider.notifier).load();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(notificationControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.globalColors;
    final notifications = ref.watch(notificationControllerProvider).items;
    final unreadCount = ref.watch(unreadCountProvider);
    final content =
        notifications.isEmpty
            ? _EmptyState(colors: colors)
            : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return _NotificationTile(
                  notification: notification,
                  colors: colors,
                  onTap: () {
                    if (!notification.read) {
                      ref
                          .read(notificationControllerProvider.notifier)
                          .markRead(notification.id);
                    }
                  },
                  onDelete: () => _deleteNotification(notification),
                );
              },
            );
    if (widget.embedded) {
      return ColoredBox(
        color: colors.surfaceContainerLowest,
        child: Column(
          children: [
            if (notifications.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (notifications.any((notification) => !notification.read))
                      TextButton.icon(
                        onPressed: _markAllRead,
                        icon: const Icon(Icons.done_all_rounded, size: 18),
                        label: Text(l10n.notificationMarkAllRead),
                      ),
                    IconButton(
                      onPressed: _clearAll,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      tooltip: l10n.notificationClearAll,
                    ),
                  ],
                ),
              ),
            Expanded(child: content),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colors.surface.withValues(alpha: 0.86),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            // 从模块内进入时返回来源模块，直达打开时回 Portal。
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/portal');
            }
          },
        ),
        title: Text(
          unreadCount > 0
              ? l10n.notificationTitleWithCount(unreadCount)
              : l10n.notificationTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (notifications.any((n) => !n.read))
            TextButton(
              onPressed: _markAllRead,
              child: Text(l10n.notificationMarkAllRead),
            ),
          if (notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: l10n.notificationClearAll,
              onPressed: _clearAll,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.profileNotificationSettings,
            onPressed: () => context.go('/profile'),
          ),
          const SizedBox(width: 8),
          const UserAvatarMenu(),
          const SizedBox(width: 8),
        ],
      ),
      body: content,
    );
  }

  Future<void> _markAllRead() {
    return ref.read(notificationControllerProvider.notifier).markAllRead();
  }

  Future<void> _deleteNotification(NotificationDto notification) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(notificationControllerProvider.notifier)
          .deleteNotification(notification.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.notificationDeleteFailed)));
      }
    }
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.notificationClearConfirmTitle),
            content: Text(l10n.notificationClearConfirmMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.coreCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.notificationClearAll),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(notificationControllerProvider.notifier).clearAll();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.notificationClearFailed)));
      }
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.colors,
    required this.onTap,
    required this.onDelete,
  });

  final NotificationDto notification;
  final GlobalThemeColors colors;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isUnread = !notification.read;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color:
            isUnread
                ? colors.primaryContainer.withValues(alpha: 0.08)
                : colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isUnread
                  ? colors.primaryContainer.withValues(alpha: 0.2)
                  : colors.outlineVariant.withValues(alpha: 0.12),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isUnread ? colors.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(
            notification.title ?? l10n.notificationNoTitle,
            style: TextStyle(
              fontSize: AppTypography.bodyLarge,
              fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
              color: colors.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (notification.message != null &&
                  notification.message!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  notification.message!,
                  style: TextStyle(
                    fontSize: AppTypography.bodySmall,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _formatTime(context, notification.createdAt),
                    style: TextStyle(
                      fontSize: AppTypography.labelSmall,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.72),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _typeColor(
                        notification.type,
                      ).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _typeLabel(context, notification.type),
                      style: TextStyle(
                        fontSize: AppTypography.labelSmall,
                        fontWeight: FontWeight.w600,
                        color: _typeColor(notification.type),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing: IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            tooltip: l10n.notificationDelete,
          ),
        ),
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime dateTime) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return l10n.notificationTimeNow;
    if (diff.inHours < 1) return l10n.notificationTimeMinutes(diff.inMinutes);
    if (diff.inDays < 1) return l10n.notificationTimeHours(diff.inHours);
    if (diff.inDays < 7) return l10n.notificationTimeDays(diff.inDays);
    return '${dateTime.month}/${dateTime.day}';
  }

  Color _typeColor(String type) {
    return switch (type) {
      'TASK_COMPLETED' => colors.success,
      'TASK_FAILED' => colors.error,
      'SHARE_ACCESS' || 'SHARE_ACCESSED' => colors.info,
      'SYSTEM_MESSAGE' => colors.secondary,
      'MEDIA_SCRAPED' => colors.tertiary,
      'QUOTA_WARNING' || 'PASSWORD_CHANGED' => colors.warning,
      'NEW_DEVICE_LOGIN' => colors.success,
      _ => colors.onSurfaceVariant,
    };
  }

  String _typeLabel(BuildContext context, String type) {
    final l10n = AppLocalizations.of(context);
    return notificationTypeLabel(type, l10n);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors});

  final GlobalThemeColors colors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 64,
            color: colors.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.notificationEmpty,
            style: TextStyle(
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.notificationEmptyHint,
            style: TextStyle(
              fontSize: AppTypography.bodyMedium,
              color: colors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
