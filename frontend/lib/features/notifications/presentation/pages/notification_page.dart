import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/theme/workstation_scope.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/core/widgets/workstation_portal_link.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_action.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_type_l10n.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

/// 通知中心：建筑极简主义工位形态。
///
/// 结构：56px 顶栏（PORTAL 返回 / 标题 / 未读徽章 / 全部已读 / 清空 /
/// 设置 / 头像）+ 780px 居中内容列（筛选分段 + TOTAL 摘要 + 通知卡流 +
/// 直角分页条）。未读卡带强边框与左侧信号条，已读卡降为弱化底色。
class NotificationPage extends ConsumerStatefulWidget {
  const NotificationPage({super.key});

  @override
  ConsumerState<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends ConsumerState<NotificationPage> {
  static const int _pageSize = 20;
  static const double _contentMaxWidth = 812;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(notificationControllerProvider.notifier).load(size: _pageSize);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationControllerProvider);
    final unreadCount = ref.watch(unreadCountProvider);
    // 无 activity:write 的角色隐藏全部主动写入口，只保留浏览。
    final canManageActivity =
        ref.watch(userCapabilitiesProvider).canManageOwnActivity;

    // 画布色必须取 WorkstationScope 内的主题：在外层取会落到全局主题的
    // surface，页面背景就不是工位深黑画布。
    return WorkstationScope(
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: scheme.surface,
            body: Column(
              children: [
                _NotificationTopBar(
                  unreadCount: unreadCount,
                  canManage: canManageActivity,
                  hasItems: state.items.isNotEmpty,
                  onMarkAllRead: _markAllRead,
                  onClearAll: _clearAll,
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _contentMaxWidth,
                      ),
                      child: Column(
                        children: [
                          _FilterSummaryBar(
                            state: state,
                            unreadCount: unreadCount,
                            onFilterSelected: (filter) {
                              ref
                                  .read(notificationControllerProvider.notifier)
                                  .setFilter(filter, size: _pageSize);
                            },
                          ),
                          Expanded(
                            child:
                                state.isLoading && state.items.isEmpty
                                    ? Center(
                                      child: CircularProgressIndicator.adaptive(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : state.items.isEmpty
                                    ? const _EmptyState()
                                    : _NotificationFeed(
                                      scrollController: _scrollController,
                                      state: state,
                                      canManage: canManageActivity,
                                      onCardTap: _markRead,
                                      onDelete: _deleteNotification,
                                    ),
                          ),
                          _PaginationBar(
                            currentPage: state.currentPage,
                            total: state.total,
                            pageSize: _pageSize,
                            onPageSelected: _goToPage,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

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
        .goToPage(page, size: _pageSize);
    if (mounted && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
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
        showOmniFeedback(
          context,
          l10n.notificationDeleteFailed,
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
    } catch (_) {
      if (mounted) {
        showOmniFeedback(
          context,
          l10n.notificationClearFailed,
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }
}

/// 56px 工位顶栏。
class _NotificationTopBar extends StatelessWidget {
  const _NotificationTopBar({
    required this.unreadCount,
    required this.canManage,
    required this.hasItems,
    required this.onMarkAllRead,
    required this.onClearAll,
  });

  final int unreadCount;
  final bool canManage;
  final bool hasItems;
  final VoidCallback onMarkAllRead;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const WorkstationPortalLink(),
          const SizedBox(width: 12),
          SizedBox(
            height: 16,
            child: VerticalDivider(width: 1, color: scheme.outlineVariant),
          ),
          const SizedBox(width: 12),
          Text(
            l10n.notificationCenterTitle,
            style: TextStyle(
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                color: scheme.surfaceContainerLow,
              ),
              child: Text(
                '[${l10n.notificationUnreadCount(unreadCount)}]',
                style: TextStyle(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontSize: AppTypography.labelMicro,
                  letterSpacing: 0.8,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (canManage && unreadCount > 0) ...[
            WorkstationActionButton(
              label: l10n.notificationMarkAllRead,
              onPressed: onMarkAllRead,
            ),
            const SizedBox(width: 8),
          ],
          if (canManage && hasItems) ...[
            WorkstationIconButton(
              tooltip: l10n.notificationClearAll,
              icon: Icons.delete_outline_outlined,
              onPressed: onClearAll,
            ),
            const SizedBox(width: 8),
          ],
          WorkstationIconButton(
            tooltip: l10n.profileNotificationSettings,
            icon: Icons.settings_outlined,
            onPressed: () => context.go('/profile?section=notifications'),
          ),
          const SizedBox(width: 8),
          const UserAvatarMenu(),
        ],
      ),
    );
  }
}

/// 筛选分段与 TOTAL 等宽摘要。
class _FilterSummaryBar extends StatelessWidget {
  const _FilterSummaryBar({
    required this.state,
    required this.unreadCount,
    required this.onFilterSelected,
  });

  final NotificationState state;
  final int unreadCount;
  final ValueChanged<NotificationFilter> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final allCount =
        state.filter == NotificationFilter.all ? state.total : state.allTotal;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          _FilterButton(
            key: const ValueKey('notification-filter-all'),
            label: l10n.notificationFilterAll(allCount),
            active: state.filter == NotificationFilter.all,
            onTap: () => onFilterSelected(NotificationFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterButton(
            key: const ValueKey('notification-filter-unread'),
            label: l10n.notificationFilterUnread(unreadCount),
            active: state.filter == NotificationFilter.unread,
            onTap: () => onFilterSelected(NotificationFilter.unread),
          ),
          const Spacer(),
          Text(
            l10n.notificationTotalSummary(state.total),
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.labelSmall,
              letterSpacing: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 模板形态的独立筛选按钮：激活项强边框 + 容器底，未激活透明底仅细线。
class _FilterButton extends StatefulWidget {
  const _FilterButton({
    required this.label,
    required this.active,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_FilterButton> createState() => _FilterButtonState();
}

class _FilterButtonState extends State<_FilterButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.active;
    final foreground =
        active || _hovering ? scheme.onSurface : scheme.onSurfaceVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: AppControlTokens.isDesktopDensity ? 30.0 : 44.0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? scheme.surfaceContainerLow : Colors.transparent,
            border: Border.all(
              color:
                  active
                      ? scheme.outline
                      : _hovering
                      ? scheme.onSurface
                      : scheme.outlineVariant,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: AppTypography.labelMedium,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// 通知卡流。
class _NotificationFeed extends StatelessWidget {
  const _NotificationFeed({
    required this.scrollController,
    required this.state,
    required this.canManage,
    required this.onCardTap,
    required this.onDelete,
  });

  final ScrollController scrollController;
  final NotificationState state;
  final bool canManage;
  final ValueChanged<NotificationDto> onCardTap;
  final ValueChanged<NotificationDto> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: state.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final notification = state.items[index];
        return _NotificationCard(
          notification: notification,
          canManage: canManage,
          onTap: () => onCardTap(notification),
          onDelete: () => onDelete(notification),
        );
      },
    );
  }
}

/// 单条通知卡：未读带左侧信号条与强边框，已读降为弱化形态。
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.canManage,
    required this.onTap,
    required this.onDelete,
  });

  final NotificationDto notification;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  static const double _contentLeftPadding = 40;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isUnread = !notification.read;
    final bodyColor =
        isUnread
            ? scheme.onSurfaceVariant
            : scheme.onSurfaceVariant.withValues(alpha: 0.75);
    return Container(
      key: ValueKey('notification-card-${notification.id}'),
      decoration: BoxDecoration(
        // 色阶：背景 surface < 已读卡 surfaceContainerLow < 未读卡 surfaceContainer，
        // 未读最亮、已读次之，两档均浮于画布之上（模板 #141416/#0f0f11 关系）。
        color: isUnread ? scheme.surfaceContainer : scheme.surfaceContainerLow,
        border: Border.all(
          color: isUnread ? scheme.outline : scheme.outlineVariant,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canManage && isUnread ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      key: const ValueKey('notification-unread-signal'),
                      width: 6,
                      height: 24,
                      color: isUnread ? scheme.onSurface : Colors.transparent,
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      notificationTypeIcon(notification.type),
                      size: 18,
                      color: isUnread ? scheme.onSurface : bodyColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        notification.title ??
                            synthesizedNotificationText(notification, l10n) ??
                            l10n.notificationNoTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTypography.bodyLarge,
                          fontWeight:
                              isUnread ? FontWeight.w600 : FontWeight.w500,
                          color: isUnread ? scheme.onSurface : bodyColor,
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (canManage) ...[
                      const SizedBox(width: 8),
                      _CardDeleteButton(onPressed: onDelete),
                    ],
                  ],
                ),
                if (notification.message?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: _contentLeftPadding),
                    child: Text(
                      notification.message!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTypography.bodySmall,
                        height: 1.5,
                        color: bodyColor,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: _contentLeftPadding),
                  child: Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _formatTime(context, notification.createdAt),
                              style: TextStyle(
                                fontFamily: AppTypography.monoFamily,
                                fontFamilyFallback:
                                    AppTypography.monoFamilyFallback,
                                fontSize: AppTypography.labelSmall,
                                color: bodyColor,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                                color: scheme.surface,
                              ),
                              child: Text(
                                '[${notification.type.toUpperCase()}]',
                                style: TextStyle(
                                  fontFamily: AppTypography.monoFamily,
                                  fontFamilyFallback:
                                      AppTypography.monoFamilyFallback,
                                  fontSize: AppTypography.labelMicro,
                                  letterSpacing: 1.2,
                                  color: bodyColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (notificationActionFor(notification, l10n)
                          case final action?) ...[
                        const SizedBox(width: 10),
                        _NotificationActionLink(
                          action: action,
                          // 用户经动作链接前往目标页即视为已消费该通知，
                          // 跳转前先落已读（未读且具备写权限时）。
                          beforeNavigate: canManage && isUnread ? onTap : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime dateTime) {
    final l10n = AppLocalizations.of(context);
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return l10n.notificationTimeNow;
    if (diff.inHours < 1) return l10n.notificationTimeMinutes(diff.inMinutes);
    if (diff.inDays < 1) return l10n.notificationTimeHours(diff.inHours);
    if (diff.inDays < 7) return l10n.notificationTimeDays(diff.inDays);
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}-${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)} ${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
  }
}

/// 卡片元信息行右侧动作链接：`[标签 ->]` 下划线形态，悬停精准变色。
class _NotificationActionLink extends StatefulWidget {
  const _NotificationActionLink({required this.action, this.beforeNavigate});

  final NotificationAction action;

  /// 跳转前置回调：未读通知在此先标记已读再导航。
  final VoidCallback? beforeNavigate;

  @override
  State<_NotificationActionLink> createState() =>
      _NotificationActionLinkState();
}

class _NotificationActionLinkState extends State<_NotificationActionLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _hovering ? scheme.onSurface : scheme.onSurfaceVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.beforeNavigate?.call();
          context.go(widget.action.route);
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: AppControlTokens.isDesktopDensity ? 2.0 : 10.0,
          ),
          child: Text(
            '[${widget.action.label} ->]',
            style: TextStyle(fontSize: AppTypography.bodySmall, color: color),
          ),
        ),
      ),
    );
  }
}

/// 卡片右上角删除钮：28px 直角 hairline，悬停转主前景。
class _CardDeleteButton extends StatefulWidget {
  const _CardDeleteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_CardDeleteButton> createState() => _CardDeleteButtonState();
}

class _CardDeleteButtonState extends State<_CardDeleteButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = _hovering ? scheme.onSurface : scheme.onSurfaceVariant;
    return Tooltip(
      message: l10n.notificationDelete,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: SizedBox.square(
            dimension: AppControlTokens.isDesktopDensity ? 26.0 : 44.0,
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _hovering ? scheme.onSurface : scheme.outlineVariant,
                  ),
                ),
                child: Icon(Icons.close_rounded, size: 14, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部直角分页条：上一页 / 窗口页码 / 下一页。
class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.currentPage,
    required this.total,
    required this.pageSize,
    required this.onPageSelected,
  });

  final int currentPage;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    final totalPages = (total / pageSize).ceil();
    if (totalPages <= 1) {
      return const SizedBox(height: 20);
    }
    final l10n = AppLocalizations.of(context);
    final windowStart = (currentPage - 2).clamp(0, totalPages - 1);
    final windowEnd = (windowStart + 4).clamp(0, totalPages - 1);
    final start =
        windowEnd - windowStart < 4
            ? (windowEnd - 4).clamp(0, totalPages - 1)
            : windowStart;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageButton(
            label: l10n.notificationPrevPage,
            enabled: currentPage > 0,
            onPressed: () => onPageSelected(currentPage - 1),
          ),
          const SizedBox(width: 4),
          if (start > 0) ...[const _PageEllipsis(), const SizedBox(width: 4)],
          for (var page = start; page <= windowEnd; page++) ...[
            _PageButton(
              label: '${page + 1}',
              active: page == currentPage,
              enabled: true,
              onPressed: () => onPageSelected(page),
            ),
            const SizedBox(width: 4),
          ],
          if (windowEnd < totalPages - 1) ...[
            const _PageEllipsis(),
            const SizedBox(width: 4),
          ],
          _PageButton(
            label: l10n.notificationNextPage,
            enabled: currentPage < totalPages - 1,
            onPressed: () => onPageSelected(currentPage + 1),
          ),
        ],
      ),
    );
  }
}

class _PageEllipsis extends StatelessWidget {
  const _PageEllipsis();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 20,
      child: Text(
        '…',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: AppTypography.labelMedium,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PageButton extends StatefulWidget {
  const _PageButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.active = false,
  });

  final String label;
  final bool enabled;
  final bool active;
  final VoidCallback onPressed;

  @override
  State<_PageButton> createState() => _PageButtonState();
}

class _PageButtonState extends State<_PageButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.enabled;
    final active = widget.active;
    final border =
        active
            ? scheme.outline
            : _hovering && enabled
            ? scheme.onSurface
            : scheme.outlineVariant;
    final foreground =
        !enabled
            ? scheme.onSurfaceVariant.withValues(alpha: 0.45)
            : active || _hovering
            ? scheme.onSurface
            : scheme.onSurfaceVariant;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: AppControlTokens.isDesktopDensity ? 28.0 : 44.0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? scheme.surfaceContainerHigh : Colors.transparent,
            border: Border.all(color: border),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: AppTypography.labelMedium,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_outlined,
            size: 44,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.notificationEmpty,
            style: TextStyle(
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.notificationEmptyHint,
            style: TextStyle(
              fontSize: AppTypography.bodySmall,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
