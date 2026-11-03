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
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_page_mobile.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_time_format.dart';
part 'notification_page_cards.dart';

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
    // 移动壳层托管态（MobileHostedRoute 挂 scope）切换为移动形态：
    // 玻璃横幅 + 两档分段 + 分组发丝线列表，桌面工位路径零变化。
    if (MobileShellScope.isHosted(context)) {
      return const NotificationMobileView();
    }
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
                                    : state.loadFailed && state.items.isEmpty
                                    ? _LoadError(
                                      onRetry:
                                          () => ref
                                              .read(
                                                notificationControllerProvider
                                                    .notifier,
                                              )
                                              .load(size: _pageSize),
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

  Future<void> _markAllRead() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(notificationControllerProvider.notifier).markAllRead();
    } catch (_) {
      if (mounted) {
        showOmniFeedback(
          context,
          l10n.notificationMarkAllReadFailed,
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
          Flexible(
            child: Text(
              l10n.notificationCenterTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
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
          // 移动窄屏收纳：全部已读降为图标钮，清空/设置保留图标钮形态。
          if (canManage && unreadCount > 0) ...[
            WorkstationIconButton(
              tooltip: l10n.notificationMarkAllRead,
              icon: Icons.done_all_outlined,
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
