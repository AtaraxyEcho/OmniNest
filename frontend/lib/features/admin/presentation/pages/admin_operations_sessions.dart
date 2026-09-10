part of 'admin_operations_pages.dart';

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
            AppDropdown<String>(
              width: AppControlTokens.filterFieldWidth,
              dense: true,
              label: l10n.adminFilterStatus,
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
            AppDropdown<String>(
              width: AppControlTokens.filterFieldWidth,
              dense: true,
              label: l10n.adminFilterPlatform,
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
            FilledButton.tonalIcon(
              onPressed: _cleanupSessions,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(l10n.adminCleanup),
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
              minTableWidth: 980,
              columns: [
                AdminListColumn(
                  key: 'username',
                  label: l10n.adminUsername,
                  flex: 2,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'device',
                  label: l10n.adminSessionDeviceName,
                  flex: 2,
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
                  Text(
                    session.username ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration:
                          session.isInactive
                              ? TextDecoration.lineThrough
                              : null,
                    ),
                  ),
                  Text(
                    session.deviceName ??
                        session.deviceId ??
                        session.clientPlatform,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    session.ipAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    session.issuedAt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    session.lastActiveAt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  _sessionStatusTag(context, session),
                ];
              },
              actionsBuilder: (context, index) {
                final session = page.items[index];
                return [
                  IconButton(
                    tooltip: l10n.adminSessionDetailTitle,
                    icon: const Icon(Icons.info_outline_rounded, size: 20),
                    onPressed: () => _showSessionDetail(context, session),
                  ),
                  if (session.isActive)
                    IconButton(
                      tooltip: l10n.adminRevokeSession,
                      icon: Icon(
                        Icons.logout_rounded,
                        size: 20,
                        color: context.adminColors.error,
                      ),
                      onPressed: () => _revokeSession(session),
                    ),
                ];
              },
            ),
            const SizedBox(height: 12),
            AdminListPaginationBar(
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
    final l10n = AppLocalizations.of(context);
    final rows = <(String, String)>[
      (l10n.adminUsername, session.username ?? '-'),
      (l10n.adminSessionFieldDeviceId, session.deviceId ?? '-'),
      (l10n.adminSessionDeviceName, session.deviceName ?? '-'),
      (l10n.adminFilterPlatform, session.clientPlatform),
      (l10n.adminSessionIp, session.ipAddress),
      (l10n.adminSessionLoginTime, session.issuedAt),
      (l10n.adminSessionExpiresAt, session.expiresAt),
      (l10n.adminSessionLastActive, session.lastActiveAt),
      (l10n.adminRevokedLabel, session.revokedAt ?? '-'),
      (l10n.adminSessionRevokeReason, session.revokeReason ?? '-'),
    ];
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.adminSessionDetailTitle),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (label, value) in rows) ...[
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.adminColors.onSurfaceVariant,
                      ),
                    ),
                    Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.coreClose),
              ),
            ],
          ),
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

  /// 批量强制下线选中的会话：确认后逐条执行，失败项跳过。
  Future<void> _batchRevoke(AdminPage<AdminSessionItem> page) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.adminBatchConfirmTitle),
            content: Text(
              l10n.adminBatchConfirmMessage('${_selectedSessions.length}'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.coreCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.coreConfirm),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.adminBatchCompleted(
              result.successCount,
              result.failedIds.length,
            ),
          ),
        ),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.adminOperationFailed)));
    }
  }

  Future<void> _revokeSession(AdminSessionItem session) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.adminConfirmKick),
            content: Text(
              l10n.adminConfirmKickMessage(
                session.deviceName ?? session.clientPlatform,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.coreCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.coreConfirm),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(adminOperationsActionsProvider).revokeSession(session.id);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.adminLoadFailed(''))));
    }
  }

  Future<void> _cleanupSessions() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.adminCleanupConfirmTitle),
            content: Text(l10n.adminCleanupConfirmMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.coreCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.adminCleanup),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final count = await ref
          .read(adminOperationsActionsProvider)
          .cleanupSessions(_retentionDays);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminCleanupCompleted('$count'))),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.adminLoadFailed(''))));
    }
  }
}
