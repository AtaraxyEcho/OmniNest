part of 'admin_operations_pages.dart';

/// 按客户端平台归类：web=Web、windows/macos/linux/desktop=PC、android/ios=移动端。
({int web, int pc, int mobile}) _countClientPlatforms(
  List<AdminSessionItem> items,
) {
  var web = 0;
  var pc = 0;
  var mobile = 0;
  for (final session in items) {
    switch (session.clientPlatform.toLowerCase()) {
      case 'web':
        web++;
      case 'windows' || 'macos' || 'linux' || 'desktop':
        pc++;
      case 'android' || 'ios':
        mobile++;
      default:
        break;
    }
  }
  return (web: web, pc: pc, mobile: mobile);
}

/// 会话详情弹窗：10 行键值，吊销会话的强制下线原因以绯红块呈现。
class _SessionDetailDialog extends StatelessWidget {
  const _SessionDetailDialog({required this.session});

  final AdminSessionItem session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final revokeReason = session.revokeReason ?? '';
    final revokedWithReason = session.isRevoked && revokeReason.isNotEmpty;
    return WorkstationDialogFrame(
      title: l10n.adminSessionDetailTitle,
      headerLabel: session.clientPlatform,
      width: 500,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailKeyValueRow(
            label: l10n.adminUsername,
            value: session.username ?? '-',
          ),
          _DetailKeyValueRow(
            label: l10n.adminSessionFieldDeviceId,
            value: session.deviceId ?? '-',
            mono: true,
          ),
          _DetailKeyValueRow(
            label: l10n.adminSessionDeviceName,
            value: session.deviceName ?? '-',
          ),
          _DetailKeyValueRow(
            label: l10n.adminFilterPlatform,
            value: session.clientPlatform,
          ),
          _DetailKeyValueRow(
            label: l10n.adminSessionIp,
            value: session.ipAddress,
            mono: true,
          ),
          _DetailKeyValueRow(
            label: l10n.adminSessionLoginTime,
            value: session.issuedAt,
            mono: true,
          ),
          _DetailKeyValueRow(
            label: l10n.adminSessionExpiresAt,
            value: session.expiresAt,
            mono: true,
          ),
          _DetailKeyValueRow(
            label: l10n.adminSessionLastActive,
            value: session.lastActiveAt,
            mono: true,
          ),
          _DetailKeyValueRow(
            label: l10n.adminRevokedLabel,
            value: session.revokedAt ?? '-',
          ),
          _DetailKeyValueRow(
            label: l10n.adminSessionRevokeReason,
            child:
                revokedWithReason
                    ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: 0.08),
                        border: Border.all(
                          color: scheme.error.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        revokeReason,
                        style: TextStyle(
                          fontFamily: AppTypography.monoFamily,
                          fontFamilyFallback: AppTypography.monoFamilyFallback,
                          fontSize: AppTypography.bodySmall,
                          height: 16 / 12,
                          color: scheme.onSurface,
                        ),
                      ),
                    )
                    : Text(
                      session.isRevoked ? revokeReason : '-',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                    ),
          ),
        ],
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coreClose),
        ),
      ],
    );
  }
}

class AdminSessionsPage extends ConsumerStatefulWidget {
  const AdminSessionsPage({super.key});

  @override
  ConsumerState<AdminSessionsPage> createState() => _AdminSessionsPageState();
}

class _AdminSessionsPageState extends ConsumerState<AdminSessionsPage> {
  int _pageSize = 10;

  /// 最近一次成功加载的会话页数据：翻页/筛选刷新期间沿用旧数据避免闪烁。
  AdminPage<AdminSessionItem>? _lastSessionsPage;
  static const _platforms = <String>[
    'ALL',
    'android',
    'ios',
    'web',
    'windows',
    'macos',
    'linux',
    'desktop',
  ];

  String _status = 'ALL';
  String _platform = 'ALL';
  String _query = '';
  int _page = 0;
  AdminListSort _sessionSort = const AdminListSort(
    columnKey: 'lastActiveAt',
    ascending: false,
  );
  final Set<int> _selectedSessions = <int>{};
  int _retentionDays = 30;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _query = ref.read(adminSearchProvider);
    ref.listenManual<String>(adminSearchProvider, (_, next) {
      _searchTimer?.cancel();
      _searchTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() {
          _query = next.trim();
          _page = 0;
        });
      });
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = (
      page: _page,
      size: _pageSize,
      status: _status,
      platform: _platform,
      query: _query,
      sort: _sessionSort.columnKey,
      dir: _sessionSort.ascending ? 'asc' : 'desc',
    );
    final sessionsAsync = ref.watch(adminSessionPageProvider(query));
    if (sessionsAsync.hasValue) {
      _lastSessionsPage = sessionsAsync.value;
    }
    final page = sessionsAsync.value ?? _lastSessionsPage;
    if (page == null) {
      return sessionsAsync.hasError
          ? Center(
            child: Text(AppLocalizations.of(context).adminLoadFailed('')),
          )
          : const Padding(
            padding: EdgeInsets.all(16),
            child: AdminListSkeleton(),
          );
    }
    return _buildPage(context, page, busy: sessionsAsync.isLoading);
  }

  Widget _buildPage(
    BuildContext context,
    AdminPage<AdminSessionItem> page, {
    required bool busy,
  }) {
    final l10n = AppLocalizations.of(context);
    final colors = context.adminColors;
    final activeCount = page.items.where((session) => session.isActive).length;
    final revokedCount =
        page.items.where((session) => session.isRevoked).length;
    final expiredCount =
        page.items.where((session) => session.isExpired).length;
    final platforms = _countClientPlatforms(page.items);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: l10n.adminSessionManagement,
          subtitle: l10n.adminSessionManagementSubtitle,
          trailing: AdminStatusPill(
            label:
                '${l10n.adminActiveSessions}: $activeCount / ${page.totalElements}',
            color: colors.success,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
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
                  value: _status,
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
                      setState(() {
                        _status = value;
                        _page = 0;
                        _selectedSessions.clear();
                      });
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
                  value: _platform,
                  items: [
                    for (final platform in _platforms)
                      AppDropdownItem(
                        value: platform,
                        label: platform == 'ALL' ? l10n.adminAll : platform,
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _platform = value;
                        _page = 0;
                        _selectedSessions.clear();
                      });
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
                  value: _retentionDays,
                  items: [
                    for (final days in const <int>[7, 30, 90, 365])
                      AppDropdownItem(
                        value: days,
                        label: l10n.adminRetentionDays('$days'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _retentionDays = value);
                  },
                ),
              ],
            ),
            FilledButton.tonalIcon(
              onPressed: _cleanupSessions,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(l10n.adminCleanup),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _MetricGrid(
          maxColumns: 4,
          cardExtent: 132,
          children: [
            AdminMetricCard(
              title: l10n.adminActiveSessions,
              value: activeCount.toString(),
              detail: l10n.adminCurrentPage,
              icon: Icons.online_prediction_outlined,
              accent: colors.success,
            ),
            AdminMetricCard(
              title: l10n.adminSessionMetricRevoked,
              value: revokedCount.toString(),
              detail: l10n.adminCurrentPage,
              icon: Icons.logout_rounded,
              accent: revokedCount == 0 ? colors.success : colors.error,
            ),
            AdminMetricCard(
              title: l10n.adminSessionStatusExpired,
              value: expiredCount.toString(),
              detail: l10n.adminCurrentPage,
              icon: Icons.hourglass_bottom_rounded,
              accent:
                  expiredCount == 0 ? colors.onSurfaceVariant : colors.warning,
            ),
            AdminMetricCard(
              title: l10n.adminSessionClientMix,
              value:
                  (platforms.web + platforms.pc + platforms.mobile).toString(),
              detail: l10n.adminCurrentPage,
              icon: Icons.devices_other_outlined,
              // 三个端型并排铺满 supporting 行，替代松散的折行 chips。
              supporting: [
                Row(
                  children: [
                    Expanded(
                      child: AdminMetricMiniStat(
                        label: l10n.adminSessionPlatformWeb,
                        value: '${platforms.web}',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AdminMetricMiniStat(
                        label: l10n.adminSessionPlatformPc,
                        value: '${platforms.pc}',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AdminMetricMiniStat(
                        label: l10n.adminSessionPlatformMobile,
                        value: '${platforms.mobile}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        AdminTableSection(
          title: l10n.adminSessionList,
          subtitle: l10n.adminSessionListSubtitle,
          children: [
            if (_selectedSessions.isNotEmpty) ...[
              _AdminBatchBar(
                count: _selectedSessions.length,
                actionLabel: l10n.adminBatchRevokeSessions,
                actionIcon: Icons.logout_rounded,
                onAction: () => _batchRevoke(page),
                onClear: () => setState(() => _selectedSessions.clear()),
              ),
              const SizedBox(height: 8),
            ],
            AdminDataTable(
              showIndex: true,
              indexBase: page.page * _pageSize,
              minTableWidth: 1320,
              // 最多两个 48px 图标按钮需 2×48 加余量，默认 168 偏宽。
              actionColumnWidth: 112,
              columns: [
                AdminListColumn(
                  key: 'username',
                  label: l10n.adminUsername,
                  minWidth: 208,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'device',
                  label: l10n.adminSessionDeviceName,
                ),
                AdminListColumn(
                  key: 'deviceId',
                  label: l10n.adminSessionFieldDeviceId,
                  minWidth: 110,
                ),
                AdminListColumn(
                  key: 'platform',
                  label: l10n.adminFilterPlatform,
                  minWidth: 96,
                ),
                AdminListColumn(
                  key: 'ip',
                  label: l10n.adminSessionIp,
                  minWidth: 130,
                ),
                AdminListColumn(
                  key: 'issuedAt',
                  label: l10n.adminSessionLoginTime,
                  minWidth: 150,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'lastActiveAt',
                  label: l10n.adminSessionLastActive,
                  minWidth: 150,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'expiresAt',
                  label: l10n.adminSessionExpiresAt,
                  minWidth: 150,
                ),
                AdminListColumn(
                  key: 'status',
                  label: l10n.adminFilterStatus,
                  minWidth: 100,
                ),
              ],
              sort: _sessionSort,
              onSort: (key, ascending) {
                setState(() {
                  _sessionSort = AdminListSort(
                    columnKey: key,
                    ascending: ascending,
                  );
                  _page = 0;
                  _selectedSessions.clear();
                });
              },
              showCheckboxes: true,
              isChecked: (index) => _selectedSessions.contains(index),
              isCheckDisabled: (index) => !page.items[index].isActive,
              onRowCheck:
                  (index, value) => setState(() {
                    value
                        ? _selectedSessions.add(index)
                        : _selectedSessions.remove(index);
                  }),
              onCheckAll: (value) {
                setState(() {
                  _selectedSessions.clear();
                  if (value) {
                    for (var i = 0; i < page.items.length; i++) {
                      if (page.items[i].isActive) _selectedSessions.add(i);
                    }
                  }
                });
              },
              allChecked:
                  page.items.any((item) => item.isActive) &&
                  _selectedSessions.length ==
                      page.items.where((item) => item.isActive).length,
              someChecked:
                  _selectedSessions.isNotEmpty &&
                  _selectedSessions.length <
                      page.items.where((item) => item.isActive).length,
              rowCount: page.items.length,
              emptyState: AdminListEmptyState(
                message:
                    _query.isEmpty && _status == 'ALL' && _platform == 'ALL'
                        ? l10n.adminNoSessions
                        : l10n.adminNoMatch,
              ),
              rowCellsBuilder: (context, index) {
                final session = page.items[index];
                return [
                  // 用户名为技术标识：统一 mono 字体；失活行叠删除线。
                  AdminCellText(
                    session.username ?? '-',
                    style: TextStyle(
                      fontFamily: AppTypography.monoFamily,
                      fontFamilyFallback: AppTypography.monoFamilyFallback,
                      fontWeight: FontWeight.w600,
                      decoration:
                          session.isInactive
                              ? TextDecoration.lineThrough
                              : null,
                      color:
                          session.isInactive
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : null,
                    ),
                  ),
                  AdminCellText(
                    session.deviceName ??
                        session.deviceId ??
                        session.clientPlatform,
                  ),
                  // 设备 ID 短码：mono 前 8 位，悬停展示完整值便于检索。
                  AdminCellText(
                    (session.deviceId ?? '').isEmpty
                        ? '-'
                        : (session.deviceId!.length >= 8
                            ? session.deviceId!.substring(0, 8)
                            : session.deviceId!),
                    tooltipMessage:
                        (session.deviceId ?? '').isEmpty
                            ? null
                            : session.deviceId,
                    style: TextStyle(
                      fontFamily: AppTypography.monoFamily,
                      fontFamilyFallback: AppTypography.monoFamilyFallback,
                      fontSize: AppTypography.labelSmall,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AdminCellText(session.clientPlatform),
                  AdminCellText(
                    session.ipAddress,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  AdminCellText(
                    session.issuedAt,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  AdminCellText(
                    session.lastActiveAt,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  AdminCellText(
                    session.expiresAt.isEmpty ? '-' : session.expiresAt,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  _sessionStatusTag(context, session),
                ];
              },
              actionsBuilder: (context, index) {
                final session = page.items[index];
                return [
                  AdminRowIconAction(
                    tooltip: l10n.adminSessionDetailTitle,
                    icon: Icons.info_outlined,
                    onTap: () => _showSessionDetail(context, session),
                  ),
                  if (session.isActive)
                    AdminRowIconAction(
                      tooltip: l10n.adminRevokeSession,
                      icon: Icons.logout_outlined,
                      color: context.adminColors.error,
                      onTap: () => _revokeSession(session),
                    ),
                ];
              },
            ),
            const SizedBox(height: 12),
            WorkstationPaginationBar(
              currentPage: page.page,
              totalPages: page.totalPages,
              totalElements: page.totalElements,
              rowsPerPage: _pageSize,
              busy: busy,
              onPageChanged:
                  (next) => setState(() {
                    _page = next;
                    _selectedSessions.clear();
                  }),
              onRowsPerPageChanged: _changePageSize,
            ),
          ],
        ),
      ],
    );
    final useExpanded =
        !ResponsiveBreakpoints.isCompact(MediaQuery.sizeOf(context).width) &&
        MediaQuery.sizeOf(context).height >= 620;
    return useExpanded ? content : SingleChildScrollView(child: content);
  }

  AdminStatusTag _sessionStatusTag(
    BuildContext context,
    AdminSessionItem session,
  ) {
    final l10n = AppLocalizations.of(context);
    if (session.isRevoked) {
      return AdminStatusTag(
        label: l10n.adminSessionStatusRevoked,
        tone: AdminTagTone.error,
      );
    }
    if (session.isExpired) {
      return AdminStatusTag(
        label: l10n.adminSessionStatusExpired,
        tone: AdminTagTone.neutral,
      );
    }
    return AdminStatusTag(
      label: l10n.adminSessionStatusActive,
      tone: AdminTagTone.success,
    );
  }

  void _showSessionDetail(BuildContext context, AdminSessionItem session) {
    showWorkstationDialog<void>(
      context: context,
      builder: (dialogContext) => _SessionDetailDialog(session: session),
    );
  }

  /// 调整每页条数：重置回第一页并清空批量选择。
  void _changePageSize(int size) {
    setState(() {
      _pageSize = size;
      _page = 0;
      _selectedSessions.clear();
    });
  }

  /// 批量强制下线选中的会话：破坏性确认后逐条执行，失败项跳过。
  Future<void> _batchRevoke(AdminPage<AdminSessionItem> page) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.adminBatchConfirmTitle,
      message: l10n.adminBatchConfirmMessage('${_selectedSessions.length}'),
      confirmLabel: l10n.adminBatchRevokeSessions,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ids = <String>[
      for (final index in _selectedSessions)
        if (index >= 0 &&
            index < page.items.length &&
            page.items[index].isActive)
          page.items[index].id,
    ];
    try {
      final result = await ref
          .read(adminOperationsActionsProvider)
          .batchRevokeSessions(ids);
      if (!mounted) return;
      setState(() => _selectedSessions.clear());
      showOmniFeedback(
        context,
        l10n.adminBatchCompleted(result.successCount, result.failedIds.length),
        severity: OmniFeedbackSeverity.warning,
      );
    } on Object {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminOperationFailed,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  /// 单个强制下线：破坏性确认文案包含目标设备名。
  Future<void> _revokeSession(AdminSessionItem session) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.adminConfirmKick,
      message: l10n.adminConfirmKickMessage(
        session.deviceName ?? session.clientPlatform,
      ),
      confirmLabel: l10n.adminRevokeSession,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(adminOperationsActionsProvider).revokeSession(session.id);
    } on Object {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminLoadFailed(''),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  /// 清理会话：弹窗内异步预估条数，确认后清理过期与已吊销会话。
  Future<void> _cleanupSessions() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationDialog<bool>(
      context: context,
      dismissible: false,
      builder:
          (dialogContext) => _CleanupConfirmDialog(
            targetLabel: l10n.adminCleanupTargetSessions,
            retentionDays: _retentionDays,
            kind: AdminCleanupPreviewKind.sessions,
            hintText: l10n.adminCleanupSessionsHint,
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final count = await ref
          .read(adminOperationsActionsProvider)
          .cleanupSessions(_retentionDays);
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminCleanupCompleted('$count'),
        severity: OmniFeedbackSeverity.success,
      );
    } on Object {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminLoadFailed(''),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }
}
