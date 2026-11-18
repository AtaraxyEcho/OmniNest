part of 'admin_operations_pages.dart';

/// 日志分区的桌面排版、页签条与移动筛选条。

/// 日志页签条（移动/平板口径）：从日志中心抽到本 part，页面留出行数余量。
class _LogTabBar extends StatelessWidget {
  const _LogTabBar({
    required this.controller,
    required this.auditCount,
    required this.loginCount,
  });

  final TabController controller;
  final int? auditCount;
  final int? loginCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TabBar(
      controller: controller,
      labelColor: context.adminColors.primary,
      unselectedLabelColor: context.adminColors.onSurfaceVariant,
      indicatorColor: context.adminColors.primary,
      tabs: [
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.adminTabAudit),
              const SizedBox(width: 8),
              _TabCountBadge(auditCount == null ? '-' : '$auditCount'),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.adminTabLoginLog),
              const SizedBox(width: 8),
              _TabCountBadge(loginCount == null ? '-' : '$loginCount'),
            ],
          ),
        ),
      ],
    );
  }
}

/// 日志分区的桌面排版（样例 `Admin.tsx` 的 System logs / Sign-in audit）：
/// 一张卡里是分段页签、动作/结果 chips、日志行与翻页条。
class _DesktopLogsPanel extends StatelessWidget {
  const _DesktopLogsPanel({
    required this.auditPage,
    required this.loginPage,
    required this.tabIndex,
    this.showTabs = true,
    this.embedded = false,
    required this.searchController,
    required this.onSearch,
    required this.auditFilter,
    required this.loginFilter,
    required this.filterOptions,
    required this.auditError,
    required this.loginError,
    required this.onTab,
    required this.onFilter,
    required this.onPage,
    required this.onAuditDetail,
    required this.onCleanup,
    required this.onExport,
    required this.onRetry,
  });

  final AdminPage<AdminAuditLog>? auditPage;
  final AdminPage<AdminLoginAuditItem>? loginPage;
  final int tabIndex;
  final bool showTabs;
  final bool embedded;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final String auditFilter;
  final String loginFilter;
  final List<String> filterOptions;
  final String? auditError;
  final String? loginError;
  final ValueChanged<int> onTab;
  final ValueChanged<String> onFilter;
  final ValueChanged<int> onPage;
  final ValueChanged<AdminAuditLog> onAuditDetail;
  final VoidCallback onCleanup;
  final VoidCallback onExport;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final auditMode = tabIndex == 0;
    final page = auditMode ? auditPage : loginPage;
    final error = auditMode ? auditError : loginError;
    final filter = auditMode ? auditFilter : loginFilter;
    final options =
        auditMode ? filterOptions : const <String>['ALL', 'SUCCESS', 'FAILED'];

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
                  hint: l10n.adminLoginAuditSearchHint,
                  prefixIcon: DesktopIcons.search,
                  height: 36,
                  onChanged: onSearch,
                ),
              ),
              DesktopButton(
                label: l10n.adminListExportCsv,
                icon: DesktopIcons.download,
                variant: DesktopButtonVariant.ghost,
                onPressed: onExport,
              ),
              DesktopButton(
                label: l10n.adminCleanup,
                icon: DesktopIcons.trash,
                variant: DesktopButtonVariant.ghost,
                onPressed: onCleanup,
              ),
            ],
          ),
        if (showTabs) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: DesktopSeg<int>(
              options: const [0, 1],
              value: tabIndex,
              small: true,
              labelOf:
                  (value) =>
                      value == 0
                          ? '${l10n.adminTabAudit} · ${auditPage?.totalElements ?? '-'}'
                          : '${l10n.adminTabLoginLog} · ${loginPage?.totalElements ?? '-'}',
              onChanged: onTab,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final value in options.take(14))
              DesktopChipButton(
                label: _logFilterLabel(l10n, value),
                selected: filter == value,
                onTap: () => onFilter(value),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Text(error, style: DesktopType.caption(skin.bad)),
                const SizedBox(height: 6),
                DesktopLink(label: l10n.coreRetry, onPressed: onRetry),
              ],
            ),
          )
        else if (page == null || page.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                l10n.adminNoMatch,
                style: DesktopType.caption(skin.text3),
              ),
            ),
          )
        else if (auditMode)
          for (var i = 0; i < auditPage!.items.length; i++)
            _DesktopAuditRow(
              log: auditPage!.items[i],
              first: i == 0,
              onTap: () => onAuditDetail(auditPage!.items[i]),
            )
        else
          for (var i = 0; i < loginPage!.items.length; i++)
            _DesktopLoginRow(log: loginPage!.items[i], first: i == 0),
        AdminPager(
          page: page?.page ?? 0,
          totalPages: page?.totalPages ?? 1,
          summary: auditMode ? l10n.adminTabAudit : l10n.adminTabLoginLog,
          onPageChanged: onPage,
        ),
      ],
    );
    if (embedded) return content;
    return AdminCard(
      title: l10n.adminLogCenter,
      subtitle: l10n.adminLogCenterSubtitle,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DesktopButton(
            label: l10n.adminListExportCsv,
            icon: DesktopIcons.download,
            variant: DesktopButtonVariant.soft,
            onPressed: onExport,
          ),
          const SizedBox(width: 6),
          DesktopButton(
            label: l10n.adminCleanup,
            variant: DesktopButtonVariant.ghost,
            onPressed: onCleanup,
          ),
        ],
      ),
      childGap: 14,
      child: content,
    );
  }
}

String _logFilterLabel(AppLocalizations l10n, String value) {
  return switch (value) {
    'ALL' => l10n.adminAll,
    'SUCCESS' => l10n.adminLoginSuccess,
    'FAILED' => l10n.adminLoginFailed,
    _ => adminAuditActionLabel(l10n, value),
  };
}

class _DesktopAuditRow extends StatelessWidget {
  const _DesktopAuditRow({
    required this.log,
    required this.first,
    required this.onTap,
  });

  final AdminAuditLog log;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final actor = log.actorLabel ?? '—';
    // 样例 `.log-row`：`138 62 96 minmax(0,1fr) 16` + gap 12 + padding 8/12，
    // 单行读完「何时 / 哪类资源 / 做了什么 / 谁做的」再点开详情。
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: hovered ? skin.raise2 : null,
                border:
                    first ? null : Border(top: BorderSide(color: skin.line)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 138,
                    child: Text(
                      _shortDateTime(log.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.numeric(skin.text3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 62,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _DesktopPill(
                        label: log.resourceType,
                        tone: skin.text2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 96,
                    child: Text(
                      adminAuditActionLabel(l10n, log.action),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.rowTitle(skin.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      [
                        actor,
                        if (log.description.isNotEmpty) log.description,
                        if (log.ipAddress.isNotEmpty) log.ipAddress,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.caption(skin.text3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(DesktopIcons.chevron, size: 16, color: skin.text3),
                ],
              ),
            ),
          ),
    );
  }
}

class _DesktopLoginRow extends StatelessWidget {
  const _DesktopLoginRow({required this.log, required this.first});

  final AdminLoginAuditItem log;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final ok = log.loginResult.toUpperCase() == 'SUCCESS';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          _DesktopLetterAvatar(text: log.username),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.rowTitle(skin.text),
                ),
                const SizedBox(height: 2),
                Text(
                  '${log.clientPlatform} · ${log.ipAddress}'
                  '${log.failureReason == null ? '' : ' · ${log.failureReason}'}',
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
              label: ok ? l10n.adminLoginSuccess : l10n.adminLoginFailed,
              tone: ok ? skin.ok : skin.bad,
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              _shortDateTime(log.createdAt),
              style: DesktopType.numeric(skin.text3),
            ),
          ),
        ],
      ),
    );
  }
}

/// 日志筛选条（移动/平板口径）：动作/结果下拉 + 保留期 + 清理/导出。
class _LogFilterBar extends StatelessWidget {
  const _LogFilterBar({
    required this.auditMode,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.retentionDays,
    required this.onRetentionChanged,
    required this.onCleanup,
    required this.onExport,
  });

  final bool auditMode;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final int retentionDays;
  final ValueChanged<int> onRetentionChanged;
  final VoidCallback onCleanup;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _AdminRecordFilterBar(
      key: ValueKey<bool>(auditMode),
      label: auditMode ? l10n.adminFilterAction : l10n.adminFilterStatus,
      value: value,
      options: options,
      optionLabel: (value) => _logFilterLabel(l10n, value),
      onChanged: onChanged,
      retentionDays: retentionDays,
      onRetentionChanged: onRetentionChanged,
      onCleanup: onCleanup,
      onExport: onExport,
    );
  }
}
