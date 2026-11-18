part of 'admin_operations_pages.dart';

/// 会话分区的桌面排版与移动筛选条。

/// 会话分区的桌面排版（样例 `Admin.tsx` 的 Sessions）：一张卡 + 状态/平台/保留期
/// 筛选 + 会话行（用户、设备、平台、最后活跃、状态、动作）+ 翻页条。
class _DesktopSessionsPanel extends StatelessWidget {
  const _DesktopSessionsPanel({
    required this.page,
    this.embedded = false,
    required this.searchController,
    required this.onSearch,
    required this.busy,
    required this.status,
    required this.platform,
    required this.platforms,
    required this.retentionDays,
    required this.onStatus,
    required this.onPlatform,
    required this.onRetention,
    required this.onCleanup,
    required this.onDetail,
    required this.onRevoke,
    required this.onPage,
  });

  final AdminPage<AdminSessionItem> page;
  final bool embedded;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final bool busy;
  final String status;
  final String platform;
  final List<String> platforms;
  final int retentionDays;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onPlatform;
  final ValueChanged<int> onRetention;
  final VoidCallback onCleanup;
  final ValueChanged<AdminSessionItem> onDetail;
  final ValueChanged<AdminSessionItem> onRevoke;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final activeCount = page.items.where((item) => item.isActive).length;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (embedded)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: DesktopTextField(
                  controller: searchController,
                  hint: l10n.adminSessionSearchHint,
                  prefixIcon: DesktopIcons.search,
                  height: 36,
                  onChanged: onSearch,
                ),
              ),
              DesktopButton(
                label: l10n.adminCleanup,
                icon: DesktopIcons.trash,
                variant: DesktopButtonVariant.ghost,
                onPressed: busy ? null : onCleanup,
              ),
            ],
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DesktopChipButton(
              label: l10n.adminAll,
              selected: status == 'ALL',
              onTap: () => onStatus('ALL'),
            ),
            for (final value in const ['ACTIVE', 'REVOKED', 'EXPIRED'])
              DesktopChipButton(
                label: _statusLabel(l10n, value),
                selected: status == value,
                onTap: () => onStatus(value),
              ),
            const SizedBox(width: 10),
            DesktopChipButton(
              label: l10n.adminAll,
              selected: platform == 'ALL',
              onTap: () => onPlatform('ALL'),
            ),
            for (final value in platforms.where((item) => item != 'ALL'))
              DesktopChipButton(
                label: value,
                selected: platform == value,
                onTap: () => onPlatform(value),
              ),
            const SizedBox(width: 10),
            for (final days in const [7, 30, 90, 365])
              DesktopChipButton(
                label: l10n.adminRetentionDays('$days'),
                selected: retentionDays == days,
                onTap: () => onRetention(days),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${l10n.adminActiveSessions}: $activeCount / ${page.totalElements}',
          style: DesktopType.caption(skin.text3),
        ),
        const SizedBox(height: 4),
        if (page.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                l10n.adminNoSessions,
                style: DesktopType.caption(skin.text3),
              ),
            ),
          )
        else
          for (var i = 0; i < page.items.length; i++)
            _DesktopSessionRow(
              session: page.items[i],
              first: i == 0,
              onDetail: () => onDetail(page.items[i]),
              onRevoke: () => onRevoke(page.items[i]),
            ),
        AdminPager(
          page: page.page,
          totalPages: page.totalPages,
          summary: l10n.adminSessionList,
          onPageChanged: onPage,
        ),
      ],
    );
    if (embedded) return content;
    return AdminCard(
      title: l10n.adminSessionList,
      count: page.totalElements,
      subtitle: l10n.adminSessionListSubtitle,
      action: DesktopButton(
        label: l10n.adminCleanup,
        icon: DesktopIcons.trash,
        variant: DesktopButtonVariant.soft,
        onPressed: busy ? null : onCleanup,
      ),
      childGap: 14,
      child: content,
    );
  }
}

String _statusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'ACTIVE' => l10n.adminSessionStatusActive,
    // 筛选 chip 用短标签：行内状态是「Force-signed out」，chip 放不下也不该重复。
    'REVOKED' => l10n.adminRevokedCount,
    _ => l10n.adminSessionStatusExpired,
  };
}

class _DesktopSessionRow extends StatelessWidget {
  const _DesktopSessionRow({
    required this.session,
    required this.first,
    required this.onDetail,
    required this.onRevoke,
  });

  final AdminSessionItem session;
  final bool first;
  final VoidCallback onDetail;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final inactive = session.isInactive;
    final name = session.username ?? '—';
    final device =
        session.deviceName ?? session.deviceId ?? session.clientPlatform;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          _DesktopLetterAvatar(text: name, dim: inactive),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.mono(skin.text).copyWith(
                    decoration: inactive ? TextDecoration.lineThrough : null,
                    color: inactive ? skin.text3 : skin.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$device · ${session.ipAddress}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.caption(skin.text3),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: _DesktopPill(
              label: session.clientPlatform,
              tone: skin.text2,
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              _shortDateTime(session.lastActiveAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopType.numeric(skin.text3),
            ),
          ),
          SizedBox(
            width: 130,
            child: _DesktopPill(
              label: _sessionStateLabel(l10n, session),
              tone:
                  session.isRevoked
                      ? skin.bad
                      : session.isExpired
                      ? skin.text3
                      : skin.ok,
            ),
          ),
          SizedBox(
            width: 72,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                DesktopIconButton(
                  icon: DesktopIcons.eye,
                  size: 28,
                  iconSize: 14,
                  tooltip: l10n.adminSessionDetailTitle,
                  onPressed: onDetail,
                ),
                if (session.isActive)
                  DesktopIconButton(
                    icon: DesktopIcons.close,
                    size: 28,
                    iconSize: 14,
                    color: skin.bad,
                    tooltip: l10n.adminRevokeSession,
                    onPressed: onRevoke,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _sessionStateLabel(AppLocalizations l10n, AdminSessionItem session) {
  if (session.isRevoked) {
    return l10n.adminSessionStatusRevoked;
  }
  if (session.isExpired) {
    return l10n.adminSessionStatusExpired;
  }
  return l10n.adminSessionStatusActive;
}

/// 会话筛选条（移动/平板口径）：状态、平台、保留期三个紧凑下拉 + 清理入口。
/// 桌面托管态用上面的 chip 行，不读这个组件。
class _SessionFilterBar extends StatelessWidget {
  const _SessionFilterBar({
    required this.status,
    required this.platform,
    required this.retentionDays,
    required this.platforms,
    required this.onStatus,
    required this.onPlatform,
    required this.onRetention,
    required this.onCleanup,
  });

  final String status;
  final String platform;
  final int retentionDays;
  final List<String> platforms;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onPlatform;
  final ValueChanged<int> onRetention;
  final VoidCallback onCleanup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // 样板形态：等宽小标前缀 + 紧凑下拉，宽度统一走 AppControlTokens。
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FilterPrefixLabel(l10n.adminFilterStatus),
            const SizedBox(width: 8),
            AppDropdown<String>(
              width: AppControlTokens.filterFieldCompactWidth,
              dense: true,
              value: status,
              items: [
                AppDropdownItem(
                  value: 'ALL',
                  label: l10n.adminSessionAllStatuses,
                ),
                AppDropdownItem(
                  value: 'ACTIVE',
                  label: l10n.adminSessionActiveOnly,
                ),
                AppDropdownItem(
                  value: 'REVOKED',
                  label: l10n.adminSessionRevokedOnly,
                ),
                AppDropdownItem(
                  value: 'EXPIRED',
                  label: l10n.adminSessionExpiredOnly,
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onStatus(value);
                }
              },
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FilterPrefixLabel(l10n.adminFilterPlatform),
            const SizedBox(width: 8),
            AppDropdown<String>(
              width: AppControlTokens.filterFieldCompactWidth,
              dense: true,
              value: platform,
              items: [
                for (final item in platforms)
                  AppDropdownItem(
                    value: item,
                    label: item == 'ALL' ? l10n.adminAll : item,
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onPlatform(value);
                }
              },
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FilterPrefixLabel(l10n.adminFilterRetention),
            const SizedBox(width: 8),
            AppDropdown<int>(
              width: AppControlTokens.filterFieldCompactWidth,
              dense: true,
              value: retentionDays,
              items: [
                for (final days in const <int>[7, 30, 90, 365])
                  AppDropdownItem(
                    value: days,
                    label: l10n.adminRetentionDays('$days'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onRetention(value);
                }
              },
            ),
          ],
        ),
        FilledButton.tonalIcon(
          onPressed: onCleanup,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: Text(l10n.adminCleanup),
        ),
      ],
    );
  }
}
