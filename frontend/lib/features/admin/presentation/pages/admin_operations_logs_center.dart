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
              // 计数由 Tab 徽章承载，页头不再重复展示统计 Pill。
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
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
                      _TabCountBadge(
                        auditPage == null ? '-' : '${auditPage.totalElements}',
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.adminTabLoginLog),
                      const SizedBox(width: 8),
                      _TabCountBadge(
                        loginPage == null ? '-' : '${loginPage.totalElements}',
                      ),
                    ],
                  ),
                ),
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
                onDetail: _showAuditDetail,
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
      showOmniFeedback(
        context,
        l10n.adminCsvExported,
        severity: OmniFeedbackSeverity.success,
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

  /// 打开操作审计详情弹窗：元数据 + 变更快照 + 原始负载。
  Future<void> _showAuditDetail(AdminAuditLog item) async {
    if (!mounted) return;
    await showWorkstationDialog<void>(
      context: context,
      builder: (dialogContext) => _AuditDetailDialog(item: item),
    );
  }

  /// 清理当前 Tab 对应日志：工位弹窗内异步预估条数，确认后物理删除。
  Future<void> _cleanupCurrentLog() async {
    final l10n = AppLocalizations.of(context);
    final isAudit = _tabController.index == 0;
    final confirmed = await showWorkstationDialog<bool>(
      context: context,
      dismissible: false,
      builder:
          (dialogContext) => _CleanupConfirmDialog(
            targetLabel: isAudit ? l10n.adminTabAudit : l10n.adminTabLoginLog,
            retentionDays: _retentionDays,
            kind:
                isAudit
                    ? AdminCleanupPreviewKind.auditLogs
                    : AdminCleanupPreviewKind.loginAuditLogs,
            showExportHint: true,
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final actions = ref.read(adminOperationsActionsProvider);
      final count =
          isAudit
              ? await actions.cleanupAuditLogs(_retentionDays)
              : await actions.cleanupLoginAuditLogs(_retentionDays);
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

/// Tab 计数徽章：等宽数字 + 细线描边，未加载时显示 '-'。
class _TabCountBadge extends StatelessWidget {
  const _TabCountBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: AppTypography.labelSmall,
          height: 14 / 11,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 操作审计详情弹窗：元数据键值、旧值/新值变更快照与原始负载 JSON。
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
    required this.onDetail,
  });

  final AdminPage<AdminAuditLog>? page;
  final bool busy;
  final bool failed;
  final ValueChanged<int> onPageChanged;
  final AdminListSort sort;
  final void Function(String columnKey, bool ascending) onSort;
  final int pageSize;
  final ValueChanged<int> onRowsPerPageChanged;
  final ValueChanged<AdminAuditLog> onDetail;

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
            minTableWidth: 1200,
            actionColumnWidth: 96,
            onRowTap: (index) => onDetail(result.items[index]),
            columns: [
              AdminListColumn(
                key: 'action',
                label: l10n.adminFilterAction,
                minWidth: 118,
                sortable: true,
              ),
              AdminListColumn(
                key: 'actor',
                label: l10n.adminAuditActorColumn,
                minWidth: 120,
              ),
              AdminListColumn(
                key: 'actorId',
                label: l10n.adminAuditActorIdColumn,
                minWidth: 110,
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
                  adminAuditActionLabel(l10n, item.action),
                  tooltipMessage: item.action,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                AdminCellText(
                  (item.actorLabel ?? '').isEmpty ? '-' : item.actorLabel!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                // 操作账号 ID 短码：mono 前 8 位，悬停展示完整 UUID；
                // 便于跨表关联用户与审计日志检索。
                AdminCellText(
                  (item.actorUserId ?? '').isEmpty
                      ? '-'
                      : (item.actorUserId!.length >= 8
                          ? item.actorUserId!.substring(0, 8)
                          : item.actorUserId!),
                  tooltipMessage:
                      (item.actorUserId ?? '').isEmpty
                          ? null
                          : item.actorUserId,
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelSmall,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
            actionsBuilder:
                (context, index) => [
                  AdminRowIconAction(
                    tooltip: l10n.adminAuditDetailTitle,
                    icon: Icons.info_outlined,
                    onTap: () => onDetail(result.items[index]),
                  ),
                ],
          ),
          const SizedBox(height: 12),
          WorkstationPaginationBar(
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
            minTableWidth: 1080,
            columns: [
              AdminListColumn(
                key: 'username',
                label: l10n.adminUsername,
                minWidth: 160,
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
                minWidth: 92,
              ),
              AdminListColumn(
                key: 'client',
                label: l10n.adminLoginClientColumn,
                minWidth: 150,
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
                  _userAgentSummary(item.userAgent),
                  tooltipMessage: item.userAgent,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
          WorkstationPaginationBar(
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

/// 登录审计 User-Agent 摘要：识别主流浏览器与操作系统组合（如
/// "Chrome · Windows"），无法识别时回退截断原文；空值回退 "-"。
/// 判定顺序遵循 UA 串优先级惯例：Edg 最具体先判，Safari 依赖 Version/ 兜底。
String _userAgentSummary(String? userAgent) {
  if (userAgent == null || userAgent.isEmpty) {
    return '-';
  }
  String browser;
  if (userAgent.contains('Edg/')) {
    browser = 'Edge';
  } else if (userAgent.contains('Firefox/')) {
    browser = 'Firefox';
  } else if (userAgent.contains('Chrome/')) {
    browser = 'Chrome';
  } else if (userAgent.contains('Safari/') && userAgent.contains('Version/')) {
    browser = 'Safari';
  } else {
    browser = '';
  }
  String os;
  if (userAgent.contains('Windows')) {
    os = 'Windows';
  } else if (userAgent.contains('Android')) {
    os = 'Android';
  } else if (userAgent.contains('iPhone') || userAgent.contains('iPad')) {
    os = 'iOS';
  } else if (userAgent.contains('Mac OS X') ||
      userAgent.contains('Macintosh')) {
    os = 'macOS';
  } else if (userAgent.contains('Linux')) {
    os = 'Linux';
  } else {
    os = '';
  }
  if (browser.isEmpty && os.isEmpty) {
    return userAgent.length > 24 ? userAgent.substring(0, 24) : userAgent;
  }
  if (browser.isEmpty) {
    return os;
  }
  if (os.isEmpty) {
    return browser;
  }
  return '$browser · $os';
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
        // 样板形态：每个筛选下拉前置等宽小标，下拉本体仅承载取值。
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FilterPrefixLabel(label),
            const SizedBox(width: 8),
            AppDropdown<String>(
              width: AppControlTokens.filterFieldWidth,
              value: value,
              dense: true,
              items: [
                for (final option in options)
                  AppDropdownItem(value: option, label: optionLabel(option)),
              ],
              onChanged: (next) {
                if (next != null) onChanged(next);
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
          ],
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

/// 审计操作类型的本地化短标签；未收录的枚举回退原始值，
/// 由 [AdminCellText] 的 tooltip 保留完整名称。
String adminAuditActionLabel(AppLocalizations l10n, String action) {
  final labels = <String, String>{
    'ADMIN_CONFIG_UPDATE': l10n.adminAuditActionConfigUpdate,
    'ADMIN_EXTERNAL_STORAGE_CREATE': l10n.adminAuditActionExternalStorageCreate,
    'ADMIN_EXTERNAL_STORAGE_STATUS_UPDATE':
        l10n.adminAuditActionExternalStorageStatusUpdate,
    'ADMIN_EXTERNAL_STORAGE_DELETE': l10n.adminAuditActionExternalStorageDelete,
    'ADMIN_QUOTA_UPDATE': l10n.adminAuditActionQuotaUpdate,
    'ADMIN_ROLE_PERMISSIONS_UPDATE': l10n.adminAuditActionRolePermissionsUpdate,
    'ADMIN_TASK_RETRY': l10n.adminAuditActionTaskRetry,
    'ADMIN_USER_CREATE': l10n.adminAuditActionUserCreate,
    'ADMIN_USER_ROLES_UPDATE': l10n.adminAuditActionUserRolesUpdate,
    'ADMIN_USER_ROLE_UPDATE': l10n.adminAuditActionUserRoleUpdate,
    'ADMIN_USER_STATUS_UPDATE': l10n.adminAuditActionUserStatusUpdate,
    'ADMIN_USER_DELETE': l10n.adminAuditActionUserDelete,
    'ADMIN_SESSION_REVOKE': l10n.adminAuditActionSessionRevoke,
    'ADMIN_SESSION_CLEANUP': l10n.adminAuditActionSessionCleanup,
    'ADMIN_AUDIT_LOG_CLEANUP': l10n.adminAuditActionAuditLogCleanup,
    'ADMIN_LOGIN_AUDIT_CLEANUP': l10n.adminAuditActionLoginAuditCleanup,
  };
  return labels[action] ?? l10n.adminAuditActionUnknown;
}
