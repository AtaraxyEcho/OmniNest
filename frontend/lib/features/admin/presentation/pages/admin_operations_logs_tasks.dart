part of 'admin_operations_pages.dart';

class AdminTasksPage extends ConsumerStatefulWidget {
  const AdminTasksPage({super.key});

  @override
  ConsumerState<AdminTasksPage> createState() => _AdminTasksPageState();
}

class _AdminTasksPageState extends ConsumerState<AdminTasksPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Timer? _searchTimer;
  String _query = '';
  String _status = 'ALL';
  String _taskType = 'ALL';
  int _page = 0;
  int _pageSize = 10;

  /// 最近一次成功加载的任务页数据：翻页/筛选刷新期间沿用旧数据避免闪烁。
  AdminPage<AdminTaskRecord>? _lastTaskPage;
  AdminListSort _taskSort = const AdminListSort(
    columnKey: 'updatedAt',
    ascending: false,
  );
  final Set<int> _selectedTasks = <int>{};

  @override
  void initState() {
    super.initState();
    _query = ref.read(adminSearchProvider);
    _tabController = TabController(length: 2, vsync: this);
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
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = (
      page: _page,
      size: _pageSize,
      status: _status,
      taskType: _taskType,
      query: _query,
      sort: _taskSort.columnKey,
      dir: _taskSort.ascending ? 'asc' : 'desc',
    );
    final taskAsync = ref.watch(adminTaskPageProvider(query));
    final dlqAsync = ref.watch(adminDlqProvider);
    if (taskAsync.hasValue) {
      _lastTaskPage = taskAsync.value;
    }
    final page = taskAsync.value ?? _lastTaskPage;
    if (page == null) {
      return taskAsync.hasError
          ? Center(
            child: Text(AppLocalizations.of(context).adminLoadFailed('')),
          )
          : const Padding(
            padding: EdgeInsets.all(16),
            child: AdminListSkeleton(),
          );
    }
    return _buildPage(context, page, dlqAsync, busy: taskAsync.isLoading);
  }

  /// 调整每页条数：重置回第一页并清空批量选择。
  void _changePageSize(int size) {
    setState(() {
      _pageSize = size;
      _page = 0;
      _selectedTasks.clear();
    });
  }

  /// 批量重试选中的任务：确认后逐条执行，失败项跳过。
  Future<void> _batchRetry(AdminPage<AdminTaskRecord> page) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.adminBatchConfirmTitle),
            content: Text(
              l10n.adminBatchConfirmMessage('${_selectedTasks.length}'),
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
      for (final index in _selectedTasks)
        if (index >= 0 &&
            index < page.items.length &&
            page.items[index].canRetry)
          page.items[index].id,
    ];
    try {
      final result = await ref
          .read(adminOperationsActionsProvider)
          .batchRetryTasks(ids);
      if (!mounted) return;
      setState(() => _selectedTasks.clear());
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

  Widget _buildPage(
    BuildContext context,
    AdminPage<AdminTaskRecord> page,
    AsyncValue<List<AdminDlqTask>> dlqAsync, {
    required bool busy,
  }) {
    final l10n = AppLocalizations.of(context);
    final colors = context.adminColors;
    final taskTypes =
        <String>{
            'ALL',
            ...page.items.map((item) => item.taskType),
            if (_taskType != 'ALL') _taskType,
          }.toList()
          ..sort();
    final failed = page.items.where((item) => item.status == 'FAILED').length;
    final running = page.items.where((item) => item.status == 'RUNNING').length;
    final useExpanded =
        !ResponsiveBreakpoints.isCompact(MediaQuery.sizeOf(context).width) &&
        MediaQuery.sizeOf(context).height >= 620;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: l10n.adminBackgroundTasks,
          subtitle: l10n.adminBackgroundTasksSubtitle,
          trailing: IconButton.filledTonal(
            tooltip: l10n.adminRefresh,
            onPressed: () => ref.invalidate(adminTaskPageProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _TaskFilter(
              label: l10n.adminFilterStatus,
              value: _status,
              options: const [
                'ALL',
                'QUEUED',
                'RUNNING',
                'COMPLETED',
                'FAILED',
                'CANCELLED',
                'DLQ',
              ],
              optionLabel: (value) => value == 'ALL' ? l10n.adminAll : value,
              onChanged:
                  (value) => setState(() {
                    _status = value;
                    _page = 0;
                    _selectedTasks.clear();
                  }),
            ),
            _TaskFilter(
              label: l10n.adminFilterTaskType,
              value: _taskType,
              options: taskTypes,
              optionLabel: (value) => value == 'ALL' ? l10n.adminAll : value,
              onChanged:
                  (value) => setState(() {
                    _taskType = value;
                    _page = 0;
                    _selectedTasks.clear();
                  }),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _MetricGrid(
          children: [
            AdminMetricCard(
              title: l10n.adminTotalTasks,
              value: page.totalElements.toString(),
              detail: l10n.adminRecentTasks,
              icon: Icons.pending_actions_outlined,
            ),
            AdminMetricCard(
              title: l10n.adminRunningTasks,
              value: running.toString(),
              detail: l10n.adminCurrentPage,
              icon: Icons.play_circle_outline_rounded,
              accent: colors.info,
            ),
            AdminMetricCard(
              title: l10n.adminFailedTasks,
              value: failed.toString(),
              detail: l10n.adminCurrentPage,
              icon: Icons.error_outline_rounded,
              accent: failed == 0 ? colors.success : colors.error,
            ),
          ],
        ),
        const SizedBox(height: 20),
        TabBar(
          controller: _tabController,
          labelColor: colors.primary,
          unselectedLabelColor: colors.onSurfaceVariant,
          indicatorColor: colors.primary,
          tabs: [Tab(text: l10n.adminTaskList), Tab(text: l10n.adminDlq)],
        ),
        const SizedBox(height: 12),
        _buildTabView(
          _TaskListTab(
            page: page,
            onPageChanged:
                (value) => setState(() {
                  _page = value;
                  _selectedTasks.clear();
                }),
            onRetry: _retryTask,
            pageSize: _pageSize,
            onRowsPerPageChanged: _changePageSize,
            busy: busy,
            sort: _taskSort,
            onSort: (key, ascending) {
              setState(() {
                _taskSort = AdminListSort(columnKey: key, ascending: ascending);
                _page = 0;
                _selectedTasks.clear();
              });
            },
            selectedIndexes: _selectedTasks,
            onRowCheck:
                (index, value) => setState(() {
                  value
                      ? _selectedTasks.add(index)
                      : _selectedTasks.remove(index);
                }),
            onCheckAll: (value) {
              setState(() {
                _selectedTasks.clear();
                if (value) {
                  for (var i = 0; i < page.items.length; i++) {
                    if (page.items[i].canRetry) _selectedTasks.add(i);
                  }
                }
              });
            },
            onBatchRetry: () => _batchRetry(page),
            onClearSelection: () => setState(() => _selectedTasks.clear()),
          ),
          _DlqTab(query: _query, state: dlqAsync),
          useExpanded: useExpanded,
        ),
      ],
    );
    return useExpanded ? content : SingleChildScrollView(child: content);
  }

  Widget _buildTabView(Widget tasks, Widget dlq, {required bool useExpanded}) {
    final tabView = TabBarView(
      controller: _tabController,
      children: [tasks, dlq],
    );
    return useExpanded
        ? Expanded(child: tabView)
        : SizedBox(height: 520, child: tabView);
  }

  void _retryTask(String taskId) {
    unawaited(_retryTaskAsync(taskId));
  }

  Future<void> _retryTaskAsync(String taskId) async {
    try {
      await ref.read(adminOperationsActionsProvider).retryTask(taskId);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).adminLoadFailed('')),
        ),
      );
    }
  }
}

class _TaskListTab extends StatelessWidget {
  const _TaskListTab({
    required this.page,
    required this.onPageChanged,
    required this.onRetry,
    required this.pageSize,
    required this.onRowsPerPageChanged,
    required this.busy,
    required this.sort,
    required this.onSort,
    required this.selectedIndexes,
    required this.onRowCheck,
    required this.onCheckAll,
    required this.onBatchRetry,
    required this.onClearSelection,
  });

  final AdminPage<AdminTaskRecord> page;
  final ValueChanged<int> onPageChanged;
  final void Function(String taskId) onRetry;
  final int pageSize;
  final ValueChanged<int> onRowsPerPageChanged;
  final bool busy;
  final AdminListSort sort;
  final void Function(String columnKey, bool ascending) onSort;
  final Set<int> selectedIndexes;
  final void Function(int index, bool value) onRowCheck;
  final void Function(bool value) onCheckAll;
  final VoidCallback onBatchRetry;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    AdminTagTone taskStatusToneFor(String status) => switch (status) {
      'COMPLETED' => AdminTagTone.success,
      'RUNNING' => AdminTagTone.info,
      'FAILED' || 'DLQ' => AdminTagTone.error,
      _ => AdminTagTone.neutral,
    };

    String taskStatusLabelFor(AppLocalizations l10n, String status) =>
        switch (status) {
          'RUNNING' => l10n.adminTaskStatusRunning,
          'COMPLETED' => l10n.adminTaskStatusCompleted,
          'DLQ' => l10n.adminTaskStatusDlq,
          'FAILED' => l10n.statusScanFailed,
          'CANCELLED' => l10n.statusScanCancelled,
          'QUEUED' => l10n.statusScanQueued,
          _ => status,
        };

    final selectableCount = page.items.where((item) => item.canRetry).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: AdminTableSection(
        title: l10n.adminTaskList,
        subtitle: l10n.adminTaskListSubtitle,
        children: [
          if (selectedIndexes.isNotEmpty) ...[
            _AdminBatchBar(
              count: selectedIndexes.length,
              actionLabel: l10n.adminBatchRetryTasks,
              actionIcon: Icons.replay_rounded,
              onAction: onBatchRetry,
              onClear: onClearSelection,
            ),
            const SizedBox(height: 8),
          ],
          if (page.items.isEmpty)
            AdminListEmptyState(message: l10n.adminNoBackgroundTasks)
          else
            AdminDataTable(
              showCheckboxes: true,
              isChecked: (index) => selectedIndexes.contains(index),
              isCheckDisabled: (index) => !page.items[index].canRetry,
              onRowCheck: onRowCheck,
              onCheckAll: onCheckAll,
              allChecked:
                  selectableCount > 0 &&
                  selectedIndexes.length == selectableCount,
              someChecked:
                  selectedIndexes.isNotEmpty &&
                  selectedIndexes.length < selectableCount,
              showIndex: true,
              indexBase: page.page * pageSize,
              minTableWidth: 1040,
              columns: [
                AdminListColumn(
                  key: 'taskType',
                  label: l10n.adminFilterTaskType,
                  sortable: true,
                ),
                AdminListColumn(key: 'description', label: l10n.adminTaskName),
                AdminListColumn(
                  key: 'progress',
                  label: l10n.adminProgress,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'status',
                  label: l10n.adminTaskExecutionStatus,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'error',
                  label: l10n.adminTaskErrorSummary,
                ),
                AdminListColumn(
                  key: 'updatedAt',
                  label: l10n.adminTaskUpdatedAt,
                  sortable: true,
                ),
              ],
              sort: sort,
              onSort: onSort,
              rowCount: page.items.length,
              emptyState: AdminListEmptyState(
                message: l10n.adminNoBackgroundTasks,
              ),
              rowCellsBuilder: (context, index) {
                final item = page.items[index];
                return [
                  Text(
                    item.taskType,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    item.description.isEmpty ? item.id : item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(
                    width: 110,
                    child: Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: item.progress / 100,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item.progress}%',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  AdminStatusTag(
                    label: taskStatusLabelFor(l10n, item.status),
                    tone: taskStatusToneFor(item.status),
                  ),
                  Tooltip(
                    message: item.errorSummary ?? '-',
                    child: Text(
                      item.errorSummary ?? '-',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    item.updatedAt,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ];
              },
              actionsBuilder:
                  (context, index) =>
                      page.items[index].canRetry
                          ? [
                            IconButton(
                              tooltip: l10n.adminRetry,
                              icon: const Icon(Icons.replay_rounded, size: 20),
                              onPressed: () => onRetry(page.items[index].id),
                            ),
                          ]
                          : const [],
            ),
          const SizedBox(height: 12),
          AdminListPaginationBar(
            currentPage: page.page,
            totalPages: page.totalPages,
            totalElements: page.totalElements,
            rowsPerPage: pageSize,
            onRowsPerPageChanged: onRowsPerPageChanged,
            busy: busy,
            onPageChanged: onPageChanged,
          ),
        ],
      ),
    );
  }
}

/// 列表页批量操作条：已选数量、取消选择与主操作按钮。
class _AdminBatchBar extends StatelessWidget {
  const _AdminBatchBar({
    required this.count,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.onClear,
  });

  final int count;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Text(
          l10n.adminListSelectedCount('$count'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const Spacer(),
        TextButton(
          onPressed: onClear,
          child: Text(l10n.adminBatchClearSelection),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: onAction,
          icon: Icon(actionIcon, size: 18),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

class _TaskFilter extends StatelessWidget {
  const _TaskFilter({
    required this.label,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final String Function(String) optionLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: AppDropdown<String>(
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
    );
  }
}

class _DlqTab extends StatelessWidget {
  const _DlqTab({required this.query, required this.state});

  final String query;
  final AsyncValue<List<AdminDlqTask>> state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return state.when(
      loading:
          () => const Padding(
            padding: EdgeInsets.all(16),
            child: AdminListSkeleton(),
          ),
      error: (_, _) => Center(child: Text(l10n.adminLoadFailed(''))),
      data: (items) {
        final filtered =
            query.isEmpty
                ? items
                : items.where((item) {
                  return item.taskType.toLowerCase().contains(
                        query.toLowerCase(),
                      ) ||
                      (item.errorSummary?.toLowerCase().contains(
                            query.toLowerCase(),
                          ) ??
                          false);
                }).toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: AdminTableSection(
            title: l10n.adminDlq,
            subtitle: l10n.adminDlqSubtitle,
            children: [
              AdminDataTable(
                showIndex: true,
                minTableWidth: 860,
                rowCount: filtered.length,
                emptyState: AdminListEmptyState(
                  message:
                      query.isEmpty ? l10n.adminNoDlqTasks : l10n.adminNoMatch,
                ),
                columns: [
                  AdminListColumn(
                    key: 'taskType',
                    label: l10n.adminFilterTaskType,
                    flex: 2,
                  ),
                  AdminListColumn(
                    key: 'status',
                    label: l10n.adminTaskExecutionStatus,
                    minWidth: 110,
                  ),
                  AdminListColumn(
                    key: 'progress',
                    label: l10n.adminProgress,
                    minWidth: 100,
                  ),
                  AdminListColumn(
                    key: 'error',
                    label: l10n.adminTaskErrorSummary,
                    flex: 3,
                  ),
                  AdminListColumn(
                    key: 'updatedAt',
                    label: l10n.adminTaskUpdatedAt,
                    minWidth: 150,
                  ),
                ],
                rowCellsBuilder: (context, index) {
                  final item = filtered[index];
                  return [
                    Text(
                      item.taskType,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    AdminStatusTag(
                      label: item.status,
                      tone: AdminTagTone.error,
                    ),
                    Text(
                      '${item.progress}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      item.errorSummary ?? l10n.adminNoErrorSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      item.updatedAt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ];
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
