part of 'notification_page.dart';

/// 通知卡片族：单条卡、动作链接与删除按钮。
///
/// 它们自带 State 与局部交互，不依赖页面状态机，因此从页面文件拆出。
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
    return formatNotificationTime(context, dateTime);
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
          // 方式判定收在 helper 里：目标是四空间之一时 push 会撞壳层的重复
          // page key 断言，其余目标继续 push 才能返回通知中心。
          navigateNotificationAction(context, widget.action.route);
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

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.notificationLoadFailed,
            style: TextStyle(
              fontSize: AppTypography.bodyMedium,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
        ],
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
