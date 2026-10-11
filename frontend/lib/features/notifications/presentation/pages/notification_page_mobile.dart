import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_action.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_time_format.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_type_l10n.dart';

/// 通知中心移动形态（对齐样例 module-overlay）：玻璃横幅 + All/Unread
/// 两档分段 + 全部已读 + 按天分组发丝线列表（图标胶囊 + 未读点 +
/// 动作胶囊），滚动到底自动追加加载下一页。
///
/// 由 [NotificationPage] 在 MobileShellScope 托管态分流渲染；路由经
/// MobileHostedRoute 挂 scope，使页内工位弹窗（清空确认等）走底部面板。
class NotificationMobileView extends ConsumerStatefulWidget {
  const NotificationMobileView({super.key});

  @override
  ConsumerState<NotificationMobileView> createState() =>
      _NotificationMobileViewState();
}

class _NotificationMobileViewState
    extends ConsumerState<NotificationMobileView> {
  static const int _pageSize = 20;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(notificationControllerProvider.notifier).load(size: _pageSize);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.extentAfter < 240) {
      ref
          .read(notificationControllerProvider.notifier)
          .loadMore(size: _pageSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(notificationControllerProvider);
    final unreadCount = ref.watch(unreadCountProvider);
    final canManage = ref.watch(userCapabilitiesProvider).canManageOwnActivity;
    return MobilePageSurface(
      exposeBackdrop: true,
      backdropOpacity: 0.92,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          // 平板宽度内容列按壳层 chrome 同宽封顶居中（与音乐甲板同语言）。
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MobileModuleHeader(
                    title: l10n.notificationCenterTitle,
                    subtitle:
                        unreadCount > 0
                            ? l10n.notificationUnreadCount(unreadCount)
                            : l10n.notificationSubtitleAllRead,
                    onBack: () => context.pop(),
                    actions: [
                      MobileGlassIconButton(
                        tooltip: l10n.profileNotificationSettings,
                        icon: Icons.settings_outlined,
                        onPressed: () => context.go('/profile/notifications'),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: MobileSegmentedControl<NotificationFilter>(
                      values: const [
                        NotificationFilter.all,
                        NotificationFilter.unread,
                      ],
                      selected: state.filter,
                      labelBuilder:
                          (filter) => switch (filter) {
                            NotificationFilter.all =>
                              AppLocalizations.of(
                                context,
                              ).notificationFilterAllLabel,
                            NotificationFilter.unread =>
                              AppLocalizations.of(
                                context,
                              ).notificationFilterUnreadLabel,
                          },
                      onSelected: (filter) {
                        ref
                            .read(notificationControllerProvider.notifier)
                            .setFilter(filter, size: _pageSize);
                      },
                    ),
                  ),
                  if (canManage && unreadCount > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                      child: _NotificationSummaryRow(
                        unreadLabel: l10n.notificationUnreadCount(unreadCount),
                        onMarkAllRead:
                            () =>
                                ref
                                    .read(
                                      notificationControllerProvider.notifier,
                                    )
                                    .markAllRead(),
                      ),
                    ),
                  Expanded(child: _buildBody(context, state, canManage)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    NotificationState state,
    bool canManage,
  ) {
    final env = context.env;
    if (state.isLoading && state.items.isEmpty) {
      return Center(
        child: CircularProgressIndicator.adaptive(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(env.inkMuted),
        ),
      );
    }
    if (state.items.isEmpty) {
      final l10n = AppLocalizations.of(context);
      return EnvEmptyState(
        icon: OmniIcons.bell,
        title: l10n.notificationEmpty,
        message: l10n.notificationEmptyHint,
      );
    }
    final entries = _NotificationListEntry.build(context, state.items);
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        20,
        6,
        20,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: entries.length + (state.isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= entries.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
            ),
          );
        }
        final entry = entries[index];
        final notification = entry.notification;
        if (notification == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 2),
            child: Text(
              entry.groupLabel!,
              style: TextStyle(
                fontSize: 9, // ignore: font_size_whitelist
                height: 1.45,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: env.groupLabelInk,
              ),
            ),
          );
        }
        return _NotificationMobileRow(
          notification: notification,
          canManage: canManage,
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
}

/// 样例 .notif-summary：左侧未读计数眉标 + 右侧「全部已读」胶囊
/// （白 7% 底、白 9% 描边、r12、对勾图标）。
class _NotificationSummaryRow extends StatelessWidget {
  const _NotificationSummaryRow({
    required this.unreadLabel,
    required this.onMarkAllRead,
  });

  final String unreadLabel;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    final env = context.env;
    final l10n = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          Expanded(
            child: Text(
              unreadLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9, // ignore: font_size_whitelist
                height: 1.45,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: env.groupLabelInk,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: env.line07,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: env.line09),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onMarkAllRead,
              child: Container(
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(Icons.check_rounded, size: 14, color: env.ink),
                    const SizedBox(width: 5),
                    Text(
                      l10n.notificationMarkAllRead,
                      style: TextStyle(
                        fontSize: 9, // ignore: font_size_whitelist
                        color: env.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组行模型：通知流按样例两档（今天/更早）插入分组眉标。
class _NotificationListEntry {
  const _NotificationListEntry({this.notification, this.groupLabel});

  final NotificationDto? notification;
  final String? groupLabel;

  static List<_NotificationListEntry> build(
    BuildContext context,
    List<NotificationDto> items,
  ) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entries = <_NotificationListEntry>[];
    String? lastGroup;
    for (final item in items) {
      final created = DateTime(
        item.createdAt.year,
        item.createdAt.month,
        item.createdAt.day,
      );
      final String group =
          created == today
              ? l10n.notificationGroupToday
              : l10n.notificationGroupEarlier;
      if (group != lastGroup) {
        entries.add(_NotificationListEntry(groupLabel: group));
        lastGroup = group;
      }
      entries.add(_NotificationListEntry(notification: item));
    }
    return entries;
  }
}

/// 单条通知（样例 .notif-row）：42px 圆角方形图标 + 主体列（标题 12/
/// 正文 9/动作链接）+ 右侧时间戳竖列（未读点在下），行高不小于 68，
/// 发丝线分隔，已读整行 55% 透明度；末滑删除（具备写权限时），点击
/// 整行标记已读。
class _NotificationMobileRow extends StatelessWidget {
  const _NotificationMobileRow({
    required this.notification,
    required this.canManage,
    required this.onTap,
    required this.onDelete,
  });

  final NotificationDto notification;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final env = context.env;
    final l10n = AppLocalizations.of(context);
    final isUnread = !notification.read;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: env.line07)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: env.accentInk.withValues(alpha: 0.08),
            ),
            child: Icon(
              notificationTypeIcon(notification.type),
              size: 19,
              color: env.accentInk,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title ??
                      synthesizedNotificationText(notification, l10n) ??
                      l10n.notificationNoTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: env.ink,
                  ),
                ),
                if (notification.message?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    notification.message!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9, // ignore: font_size_whitelist
                      height: 1.45,
                      color: env.inkMuted,
                    ),
                  ),
                ],
                if (notificationActionFor(notification, l10n)
                    case final action?) ...[
                  const SizedBox(height: 2),
                  _NotificationActionLink(
                    action: action,
                    beforeNavigate: canManage && isUnread ? onTap : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                formatNotificationTime(context, notification.createdAt),
                style: TextStyle(
                  fontSize: 8, // ignore: font_size_whitelist
                  color: env.ink40,
                ),
              ),
              if (isUnread) ...[
                const SizedBox(height: 7),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: env.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: env.accent.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    final dimmedRow = isUnread ? row : Opacity(opacity: 0.55, child: row);
    if (!canManage) {
      return dimmedRow;
    }
    return Dismissible(
      key: ValueKey<String>('mobile-notification-${notification.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Color(0x1FE2A1A1),
          border: Border(
            top: BorderSide(color: env.line09),
            bottom: BorderSide(color: env.line07),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.delete_outline_rounded,
              size: 19,
              color: Color(0xFFE2A1A1),
            ),
            const SizedBox(width: 7),
            Text(
              AppLocalizations.of(context).notificationDelete,
              style: const TextStyle(
                fontSize: 11, // ignore: font_size_whitelist
                fontWeight: FontWeight.w700,
                color: Color(0xFFE2A1A1),
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      child: dimmedRow,
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    if (MobileShellScope.isHosted(context)) {
      return showMobileConfirmSheet(
        context,
        title: l10n.notificationDelete,
        message: l10n.notificationDeleteConfirmMessage,
        confirmLabel: l10n.notificationDelete,
        destructive: true,
      );
    }
    return showWorkstationConfirmDialog(
      context,
      title: l10n.notificationDelete,
      message: l10n.notificationDeleteConfirmMessage,
      confirmLabel: l10n.notificationDelete,
      destructive: true,
    );
  }
}

/// 动作链接（样例 .notif-action）：酸绿文字 + 小箭头，无底色。
class _NotificationActionLink extends StatelessWidget {
  const _NotificationActionLink({required this.action, this.beforeNavigate});

  final NotificationAction action;
  final VoidCallback? beforeNavigate;

  @override
  Widget build(BuildContext context) {
    final env = context.env;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          beforeNavigate?.call();
          // push 而不是 go：go 会换掉整条栈，从通知跳进目标页后系统返回
          // 直接退出应用（与系统通知点击的 push 行为保持一致）。
          context.push(action.route);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 26),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                action.label,
                style: TextStyle(
                  fontSize: 9, // ignore: font_size_whitelist
                  fontWeight: FontWeight.w600,
                  color: env.accentInk,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 14, color: env.accentInk),
            ],
          ),
        ),
      ),
    );
  }
}
