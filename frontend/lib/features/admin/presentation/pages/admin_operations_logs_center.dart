/// 日志中心：操作审计与登录审计列表。
part of 'admin_operations_pages.dart';

class AdminLogsPage extends ConsumerStatefulWidget {
  const AdminLogsPage({super.key});

  @override
  ConsumerState<AdminLogsPage> createState() => _AdminLogsPageState();
}

class _AdminLogsPageState extends ConsumerState<AdminLogsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Timer? _searchTimer;
  String _query = '';
  String _auditAction = 'ALL';
  String _loginResult = 'ALL';
  int _auditPage = 0;
  int _loginPage = 0;
  int _pageSize = 10;

  /// 最近一次成功加载的审计/登录页数据：刷新期间沿用旧数据避免闪烁。
  AdminPage<AdminAuditLog>? _lastAuditPage;
  AdminPage<AdminLoginAuditItem>? _lastLoginPage;
  AdminListSort _auditSort = const AdminListSort(
    columnKey: 'createdAt',
    ascending: false,
  );
  AdminListSort _loginSort = const AdminListSort(
    columnKey: 'createdAt',
    ascending: false,
  );
  int _retentionDays = 30;

  @override
  void initState() {
    super.initState();
    _query = ref.read(adminSearchProvider);
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_handleTabChanged);
    ref.listenManual<String>(adminSearchProvider, (_, next) {
      _searchTimer?.cancel();
      _searchTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() {
          _query = next.trim();
          _auditPage = 0;
          _loginPage = 0;
        });
      });
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!_tabController.indexIsChanging && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auditQuery = (
      page: _auditPage,
      size: _pageSize,
      action: _auditAction,
      query: _query,
      sort: _auditSort.columnKey,
      dir: _auditSort.ascending ? 'asc' : 'desc',
    );
    final loginQuery = (
      page: _loginPage,
      size: _pageSize,
      result: _loginResult,
      platform: 'ALL',
      query: _query,
      sort: _loginSort.columnKey,
      dir: _loginSort.ascending ? 'asc' : 'desc',
    );
    final auditAsync = ref.watch(adminLogPageProvider(auditQuery));
    final loginAsync = ref.watch(adminLoginAuditPageProvider(loginQuery));
    if (auditAsync.hasValue) {
      _lastAuditPage = auditAsync.value;
    }
    if (loginAsync.hasValue) {
      _lastLoginPage = loginAsync.value;
    }
    final auditPage = auditAsync.value ?? _lastAuditPage;
    final loginPage = loginAsync.value ?? _lastLoginPage;
    final currentTotal =
        _tabController.index == 0
            ? auditPage?.totalElements ?? 0
            : loginPage?.totalElements ?? 0;
    final currentOptions =
        <String>{
            'ALL',
            ...?auditPage?.items.map((item) => item.action),
            if (_auditAction != 'ALL') _auditAction,
          }.toList()
          ..sort();

    return LayoutBuilder(
      builder: (context, constraints) {
        final l10n = AppLocalizations.of(context);
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminPageHeader(
              title: l10n.adminLogCenter,
              subtitle: l10n.adminLogCenterSubtitle,
              trailing: AdminStatusPill(
                label: l10n.adminAuditCount('$currentTotal'),
              ),
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              labelColor: context.adminColors.primary,
              unselectedLabelColor: context.adminColors.onSurfaceVariant,
              indicatorColor: context.adminColors.primary,
              tabs: [
                Tab(text: l10n.adminTabAudit),
                Tab(text: l10n.adminTabLoginLog),
              ],
            ),
            const SizedBox(height: 16),
            _AdminRecordFilterBar(
              key: ValueKey<int>(_tabController.index),
              label:
                  _tabController.index == 0
                      ? l10n.adminFilterAction
                      : l10n.adminFilterStatus,
              value: _tabController.index == 0 ? _auditAction : _loginResult,
              options:
                  _tabController.index == 0
                      ? currentOptions
                      : const <String>['ALL', 'SUCCESS', 'FAILED'],
              optionLabel: (value) {
                if (value == 'ALL') return l10n.adminAll;
                if (value == 'SUCCESS') return l10n.adminLoginSuccess;
                if (value == 'FAILED') return l10n.adminLoginFailed;
                return value;
              },
              onChanged: (value) {
                setState(() {
                  if (_tabController.index == 0) {
                    _auditAction = value;
                    _auditPage = 0;
                  } else {
                    _loginResult = value;
                    _loginPage = 0;
                  }
                });
              },
              retentionDays: _retentionDays,
              onRetentionChanged:
                  (value) => setState(() => _retentionDays = value),
              onCleanup: _cleanupCurrentLog,
              onExport: _exportCurrentPageAsCsv,
            ),
            const SizedBox(height: 16),
            _buildTabView(
              _AuditLogTab(
                page: auditPage,
                busy: auditAsync.isLoading,
                failed: auditAsync.hasError && auditPage == null,
                onPageChanged: (page) => setState(() => _auditPage = page),
                pageSize: _pageSize,
                onRowsPerPageChanged: _changePageSize,
                sort: _auditSort,
                onSort: (key, ascending) {
                  setState(() {
                    _auditSort = AdminListSort(
                      columnKey: key,
                      ascending: ascending,
                    );
                    _auditPage = 0;
                  });
                },
              ),
              _LoginAuditLogTab(
                page: loginPage,
                busy: loginAsync.isLoading,
                failed: loginAsync.hasError && loginPage == null,
                onPageChanged: (page) => setState(() => _loginPage = page),
                pageSize: _pageSize,
                onRowsPerPageChanged: _changePageSize,
                sort: _loginSort,
                onSort: (key, ascending) {
                  setState(() {
                    _loginSort = AdminListSort(
                      columnKey: key,
                      ascending: ascending,
                    );
                    _loginPage = 0;
                  });
                },
              ),
              useExpanded: _useExpanded(constraints),
            ),
          ],
        );
        return _useExpanded(constraints)
            ? content
            : SingleChildScrollView(child: content);
      },
    );
  }

  bool _useExpanded(BoxConstraints constraints) {
    return !ResponsiveBreakpoints.isCompact(MediaQuery.sizeOf(context).width) &&
        (!constraints.hasBoundedHeight || constraints.maxHeight >= 620);
  }

  Widget _buildTabView(
    Widget audit,
    Widget login, {
    required bool useExpanded,
  }) {
    final tabView = TabBarView(
      controller: _tabController,
      children: [audit, login],
    );
    return useExpanded
        ? Expanded(child: tabView)
        : SizedBox(height: 520, child: tabView);
  }

  /// 调整每页条数：重置两个 Tab 回第一页。
  void _changePageSize(int size) {
    setState(() {
      _pageSize = size;
      _auditPage = 0;
      _loginPage = 0;
    });
  }

  /// 将当前激活 Tab 的当前页导出为 CSV 文件。
  Future<void> _exportCurrentPageAsCsv() async {
    final l10n = AppLocalizations.of(context);
    final isAudit = _tabController.index == 0;
    final suggestedName =
        isAudit ? 'omninest-audit-logs.csv' : 'omninest-login-audits.csv';
    try {
      final csv = isAudit ? _buildAuditCsv(l10n) : _buildLoginCsv(l10n);
      final savedPath = await saveAdminCsvToDisk(
        suggestedName: suggestedName,
        csv: csv,
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.adminCsvExported)));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.adminOperationFailed)));
    }
  }

  String _buildAuditCsv(AppLocalizations l10n) {
    // 导出与当前可见页一致：直接使用缓存的最近成功页数据。
    final items = _lastAuditPage?.items ?? const <AdminAuditLog>[];
    return adminCsvDocument(
      header: [
        l10n.adminFilterAction,
        l10n.adminLogContent,
        l10n.adminResourceType,
        l10n.adminSessionIp,
        l10n.adminLogTime,
      ],
      rows: [
        for (final item in items)
          [
            item.action,
            item.description.isEmpty ? item.action : item.description,
            item.resourceType,
            item.ipAddress,
            item.createdAt,
          ],
      ],
    );
  }

  String _buildLoginCsv(AppLocalizations l10n) {
    final items = _lastLoginPage?.items ?? const <AdminLoginAuditItem>[];
    return adminCsvDocument(
      header: [
        l10n.adminUsername,
        l10n.adminFilterStatus,
        l10n.adminFilterPlatform,
        l10n.adminSessionIp,
        l10n.adminLoginFailureReason,
        l10n.adminLogTime,
      ],
      rows: [
        for (final item in items)
          [
            item.username,
            item.loginResult == 'SUCCESS'
                ? l10n.adminLoginSuccess
                : l10n.adminLoginFailed,
            item.clientPlatform,
            item.ipAddress,
            item.failureReason ?? '',
            item.createdAt,
          ],
      ],
    );
  }

  Future<void> _cleanupCurrentLog() async {
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
      final actions = ref.read(adminOperationsActionsProvider);
      final count =
          _tabController.index == 0
              ? await actions.cleanupAuditLogs(_retentionDays)
              : await actions.cleanupLoginAuditLogs(_retentionDays);
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

class _AuditLogTab extends StatelessWidget {
  const _AuditLogTab({
    required this.page,
    required this.busy,
    required this.failed,
    required this.onPageChanged,
    required this.sort,
    required this.onSort,
    required this.pageSize,
    required this.onRowsPerPageChanged,
  });

  final AdminPage<AdminAuditLog>? page;
  final bool busy;
  final bool failed;
  final ValueChanged<int> onPageChanged;
  final AdminListSort sort;
  final void Function(String columnKey, bool ascending) onSort;
  final int pageSize;
  final ValueChanged<int> onRowsPerPageChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = page;
    if (result == null) {
      return failed
          ? Center(child: Text(l10n.adminLoadFailed('')))
          : const Padding(
            padding: EdgeInsets.all(16),
            child: AdminListSkeleton(),
          );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: AdminTableSection(
        title: l10n.adminRecentAudit,
        subtitle: l10n.adminRecentAuditSubtitle,
        children: [
          AdminDataTable(
            showIndex: true,
            indexBase: result.page * pageSize,
            minTableWidth: 960,
            maxTableWidth: 1060,
            columns: [
              AdminListColumn(
                key: 'action',
                label: l10n.adminFilterAction,
                minWidth: 160,
                sortable: true,
              ),
              AdminListColumn(
                key: 'content',
                label: l10n.adminLogContent,
                flex: 2,
              ),
              AdminListColumn(
                key: 'resourceType',
                label: l10n.adminResourceType,
                minWidth: 110,
              ),
              AdminListColumn(
                key: 'ip',
                label: l10n.adminSessionIp,
                minWidth: 130,
              ),
              AdminListColumn(
                key: 'createdAt',
                label: l10n.adminLogTime,
                minWidth: 150,
                sortable: true,
              ),
            ],
            sort: sort,
            onSort: onSort,
            rowCount: result.items.length,
            emptyState: AdminListEmptyState(message: l10n.adminNoAuditLogs),
            rowCellsBuilder: (context, index) {
              final item = result.items[index];
              return [
                AdminCellText(
                  item.action,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                AdminCellText(
                  item.description.isEmpty ? item.action : item.description,
                ),
                AdminCellText(item.resourceType),
                AdminCellText(
                  item.ipAddress,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                AdminCellText(
                  item.createdAt,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ];
            },
          ),
          const SizedBox(height: 12),
          AdminListPaginationBar(
            currentPage: result.page,
            totalPages: result.totalPages,
            totalElements: result.totalElements,
            rowsPerPage: pageSize,
            onPageChanged: onPageChanged,
            onRowsPerPageChanged: onRowsPerPageChanged,
            busy: busy,
          ),
        ],
      ),
    );
  }
}

class _LoginAuditLogTab extends StatelessWidget {
  const _LoginAuditLogTab({
    required this.page,
    required this.busy,
    required this.failed,
    required this.onPageChanged,
    required this.sort,
    required this.onSort,
    required this.pageSize,
    required this.onRowsPerPageChanged,
  });

  final AdminPage<AdminLoginAuditItem>? page;
  final bool busy;
  final bool failed;
  final ValueChanged<int> onPageChanged;
  final AdminListSort sort;
  final void Function(String columnKey, bool ascending) onSort;
  final int pageSize;
  final ValueChanged<int> onRowsPerPageChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = page;
    if (result == null) {
      return failed
          ? Center(child: Text(l10n.adminLoadFailed('')))
          : const Padding(
            padding: EdgeInsets.all(16),
            child: AdminListSkeleton(),
          );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: AdminTableSection(
        title: l10n.adminLoginLog,
        subtitle: l10n.adminLoginLogSubtitle,
        children: [
          AdminDataTable(
            showIndex: true,
            indexBase: result.page * pageSize,
            minTableWidth: 960,
            maxTableWidth: 1060,
            columns: [
              // 用户名改为 S 档：与失败原因按 1:2 分配剩余宽度，避免长屏下过宽。
              AdminListColumn(
                key: 'username',
                label: l10n.adminUsername,
                sortable: true,
              ),
              AdminListColumn(
                key: 'result',
                label: l10n.adminFilterStatus,
                minWidth: 100,
              ),
              AdminListColumn(
                key: 'platform',
                label: l10n.adminFilterPlatform,
                minWidth: 100,
              ),
              AdminListColumn(
                key: 'ip',
                label: l10n.adminSessionIp,
                minWidth: 130,
              ),
              AdminListColumn(
                key: 'failureReason',
                label: l10n.adminLoginFailureReason,
                flex: 2,
              ),
              AdminListColumn(
                key: 'createdAt',
                label: l10n.adminLogTime,
                minWidth: 150,
                sortable: true,
              ),
            ],
            sort: sort,
            onSort: onSort,
            rowCount: result.items.length,
            emptyState: AdminListEmptyState(message: l10n.adminNoLoginLogs),
            rowCellsBuilder: (context, index) {
              final item = result.items[index];
              final success = item.loginResult == 'SUCCESS';
              return [
                AdminCellText(
                  item.username,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                AdminStatusTag(
                  label:
                      success ? l10n.adminLoginSuccess : l10n.adminLoginFailed,
                  tone: success ? AdminTagTone.success : AdminTagTone.error,
                ),
                AdminCellText(item.clientPlatform),
                AdminCellText(
                  item.ipAddress,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                AdminCellText(
                  item.failureReason ?? '-',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                AdminCellText(
                  item.createdAt,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ];
            },
          ),
          const SizedBox(height: 12),
          AdminListPaginationBar(
            currentPage: result.page,
            totalPages: result.totalPages,
            totalElements: result.totalElements,
            rowsPerPage: pageSize,
            onPageChanged: onPageChanged,
            onRowsPerPageChanged: onRowsPerPageChanged,
            busy: busy,
          ),
        ],
      ),
    );
  }
}

class _AdminRecordFilterBar extends StatelessWidget {
  const _AdminRecordFilterBar({
    required this.label,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
    required this.retentionDays,
    required this.onRetentionChanged,
    required this.onCleanup,
    required this.onExport,
    super.key,
  });

  final String label;
  final String value;
  final List<String> options;
  final String Function(String value) optionLabel;
  final ValueChanged<String> onChanged;
  final int retentionDays;
  final ValueChanged<int> onRetentionChanged;
  final VoidCallback onCleanup;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppDropdown<String>(
          width: AppControlTokens.filterFieldWidth,
          value: value,
          dense: true,
          label: label,
          items: [
            for (final option in options)
              AppDropdownItem(value: option, label: optionLabel(option)),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
        AppDropdown<int>(
          width: AppControlTokens.filterFieldCompactWidth,
          value: retentionDays,
          dense: true,
          items: [
            for (final days in const <int>[7, 30, 90, 365])
              AppDropdownItem(
                value: days,
                label: l10n.adminRetentionDays('$days'),
              ),
          ],
          onChanged: (next) {
            if (next != null) onRetentionChanged(next);
          },
        ),
        FilledButton.tonalIcon(
          onPressed: onCleanup,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: Text(l10n.adminCleanup),
        ),
        FilledButton.tonalIcon(
          onPressed: onExport,
          icon: const Icon(Icons.file_download_outlined),
          label: Text(l10n.adminListExportCsv),
        ),
      ],
    );
  }
}
