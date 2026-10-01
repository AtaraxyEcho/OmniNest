part of 'admin_operations_pages.dart';

// 任务状态映射（_taskStatusLabel/_taskStatusTone）与任务详情弹窗
// （_TaskDetailDialog）拆分至 admin_operations_task_dialogs.dart。

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
    ref.listen<AsyncValue<AdminPage<AdminTaskRecord>>>(
      adminTaskPageProvider(query),
      (previous, next) {
        final value = next.value;
        if (value != null) {
          _lastTaskPage = value;
        }
      },
    );
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

  /// 批量重试选中的任务：工位确认弹窗后逐条执行，失败项跳过。
  Future<void> _batchRetry(AdminPage<AdminTaskRecord> page) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.adminBatchConfirmTitle,
      message: l10n.adminBatchConfirmMessage('${_selectedTasks.length}'),
      confirmLabel: l10n.coreConfirm,
    );
    if (!confirmed || !mounted) return;
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

  /// 批量取消选中的任务：仅排队/等待重试态生效，失败项跳过。
  Future<void> _batchCancel(AdminPage<AdminTaskRecord> page) async {
    final l10n = AppLocalizations.of(context);
    final targets = <String>[
      for (final index in _selectedTasks)
        if (index >= 0 &&
            index < page.items.length &&
            page.items[index].canCancel)
          page.items[index].id,
    ];
    if (targets.isEmpty) {
      setState(() => _selectedTasks.clear());
      return;
    }
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.adminBatchCancelTasks,
      message: l10n.adminBatchCancelConfirmMessage('${targets.length}'),
      confirmLabel: l10n.adminTaskCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final result = await ref
          .read(adminOperationsActionsProvider)
          .batchCancelTasks(targets);
      if (!mounted) return;
      setState(() => _selectedTasks.clear());
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
    final running = page.items.where((item) => item.status == 'RUNNING').length;
    final queued = page.items.where((item) => item.status == 'QUEUED').length;
    final retryWait =
        page.items.where((item) => item.status == 'RETRY_WAIT').length;
    final queuedReady = queued + retryWait;
    final failedStatus =
        page.items.where((item) => item.status == 'FAILED').length;
    final dlqOnPage = page.items.where((item) => item.status == 'DLQ').length;
    final failed = failedStatus + dlqOnPage;
    final dlqCount = dlqAsync.asData?.value.length ?? 0;
    final useExpanded =
        !ResponsiveBreakpoints.isCompact(MediaQuery.sizeOf(context).width) &&
        MediaQuery.sizeOf(context).height >= 620;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: l10n.adminBackgroundTasks,
          subtitle: l10n.adminBackgroundTasksSubtitle,
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminStatusPill(
                label: '${l10n.adminTotalTasks} ${page.totalElements}',
              ),
              IconButton.filledTonal(
                tooltip: l10n.adminRefresh,
                onPressed: () => ref.invalidate(adminTaskPageProvider),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
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
                'RETRY_WAIT',
                'RUNNING',
                'COMPLETED',
                'FAILED',
                'CANCELLED',
                'DLQ',
                'DISCARDED',
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
          maxColumns: 4,
          cardExtent: 132,
          children: [
            // 执行中卡不引入 Worker 活跃文案：该口径需要独立后端数据，
            // 此处仅用既有分页数据补齐其余卡片的 supporting 行。
            AdminMetricCard(
              title: l10n.adminRunningTasks,
              value: running.toString(),
              detail: l10n.adminCurrentPage,
              icon: Icons.play_circle_outline_rounded,
              accent: colors.info,
            ),
            AdminMetricCard(
              title: l10n.adminMetricQueuedReady,
              value: queuedReady.toString(),
              detail: l10n.adminCurrentPage,
              icon: Icons.schedule_rounded,
              accent: colors.warning,
              supporting: [
                AdminMetricMiniStat(
                  label: l10n.statusScanQueued,
                  value: queued.toString(),
                ),
                AdminMetricMiniStat(
                  label: l10n.adminTaskStatusRetryWait,
                  value: retryWait.toString(),
                ),
              ],
            ),
            AdminMetricCard(
              title: l10n.adminMetricDlq,
              value: dlqCount.toString(),
              detail: l10n.adminDlqMetricHint,
              icon: Icons.report_outlined,
              accent: dlqCount == 0 ? colors.success : colors.error,
            ),
            AdminMetricCard(
              title: l10n.adminFailedTasks,
              value: failed.toString(),
              detail: l10n.adminCurrentPage,
              icon: Icons.error_outline_rounded,
              accent: failed == 0 ? colors.success : colors.error,
              supporting: [
                AdminMetricMiniStat(
                  label: l10n.adminFailedTasks,
                  value: failedStatus.toString(),
                ),
                AdminMetricMiniStat(
                  label: l10n.adminTaskStatusDlq,
                  value: dlqOnPage.toString(),
                ),
              ],
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
            onCancel: _cancelTask,
            onDetail: _showTaskDetail,
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
                    if (page.items[i].canRetry || page.items[i].canCancel) {
                      _selectedTasks.add(i);
                    }
                  }
                }
              });
            },
            onBatchRetry: () => _batchRetry(page),
            onBatchCancel: () => _batchCancel(page),
            onClearSelection: () => setState(() => _selectedTasks.clear()),
          ),
          _DlqTab(
            query: _query,
            state: dlqAsync,
            onRetry: _retryDlq,
            onDiscard: _discardDlqTask,
          ),
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

  /// 打开任务详情弹窗。
  Future<void> _showTaskDetail(AdminTaskRecord item) async {
    if (!mounted) return;
    await showWorkstationDialog<void>(
      context: context,
      builder: (dialogContext) => _TaskDetailDialog(item: item),
    );
  }

  void _retryTask(String taskId) {
    unawaited(_retryTaskAsync(taskId));
  }

  Future<void> _retryTaskAsync(String taskId) async {
    try {
      await ref.read(adminOperationsActionsProvider).retryTask(taskId);
    } on Object {
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(context).adminLoadFailed(''),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  /// 取消排队/等待重试的任务：确认后调用 cancelTask。
  Future<void> _cancelTask(String taskId) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.adminTaskCancelConfirmTitle,
      message: l10n.adminTaskCancelConfirmMessage,
      confirmLabel: l10n.adminTaskCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(adminOperationsActionsProvider).cancelTask(taskId);
    } on Object {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminOperationFailed,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  /// 重试死信任务。
  Future<void> _retryDlq(String taskId) async {
    try {
      await ref.read(adminOperationsActionsProvider).retryDlq(taskId);
    } on Object {
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(context).adminLoadFailed(''),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  /// 丢弃死信任务：键入任务 ID 前 8 位短码的破坏性确认。
  Future<void> _discardDlqTask(AdminDlqTask item) async {
    final l10n = AppLocalizations.of(context);
    final phrase = item.id.length >= 8 ? item.id.substring(0, 8) : item.id;
    final confirmed = await showWorkstationDestructiveConfirm(
      context,
      title: l10n.adminTaskDiscardTitle,
      message: l10n.adminTaskDiscardMessage,
      confirmPhrase: phrase,
      confirmLabel: l10n.adminTaskDiscard,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(adminOperationsActionsProvider).discardDlqTask(item.id);
    } on Object {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.adminOperationFailed,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }
}

class _TaskListTab extends StatelessWidget {
  const _TaskListTab({
    required this.page,
    required this.onPageChanged,
    required this.onRetry,
    required this.onCancel,
    required this.onDetail,
    required this.pageSize,
    required this.onRowsPerPageChanged,
    required this.busy,
    required this.sort,
    required this.onSort,
    required this.selectedIndexes,
    required this.onRowCheck,
    required this.onCheckAll,
    required this.onBatchRetry,
    required this.onBatchCancel,
    required this.onClearSelection,
  });

  final AdminPage<AdminTaskRecord> page;
  final ValueChanged<int> onPageChanged;
  final void Function(String taskId) onRetry;

  /// 取消排队/等待重试任务。
  final void Function(String taskId) onCancel;

  /// 打开任务详情弹窗。
  final ValueChanged<AdminTaskRecord> onDetail;
  final int pageSize;
  final ValueChanged<int> onRowsPerPageChanged;
  final bool busy;
  final AdminListSort sort;
  final void Function(String columnKey, bool ascending) onSort;
  final Set<int> selectedIndexes;
  final void Function(int index, bool value) onRowCheck;
  final void Function(bool value) onCheckAll;
  final VoidCallback onBatchRetry;
  final VoidCallback onBatchCancel;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 可勾选 = 可重试或可取消：勾选同时服务批量重试与批量取消两个动作。
    final selectableCount =
        page.items.where((item) => item.canRetry || item.canCancel).length;
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
              secondaryActionLabel: l10n.adminBatchCancelTasks,
              secondaryActionIcon: Icons.close_rounded,
              onSecondaryAction: onBatchCancel,
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
              isCheckDisabled:
                  (index) =>
                      !page.items[index].canRetry &&
                      !page.items[index].canCancel,
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
              minTableWidth: 1480,
              columns: [
                AdminListColumn(
                  key: 'taskType',
                  label: l10n.adminFilterTaskType,
                  minWidth: 128,
                  sortable: true,
                ),
                AdminListColumn(key: 'description', label: l10n.adminTaskName),
                AdminListColumn(key: 'owner', label: l10n.adminTaskOwner),
                AdminListColumn(
                  key: 'progress',
                  label: l10n.adminProgress,
                  minWidth: 130,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'status',
                  label: l10n.adminTaskExecutionStatus,
                  minWidth: 100,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'retryCount',
                  label: l10n.adminTaskRetryCount,
                  minWidth: 88,
                  numeric: true,
                ),
                AdminListColumn(
                  key: 'error',
                  label: l10n.adminTaskErrorSummary,
                ),
                AdminListColumn(
                  key: 'createdAt',
                  label: l10n.adminTaskCreatedAt,
                  minWidth: 150,
                  sortable: true,
                ),
                AdminListColumn(
                  key: 'updatedAt',
                  label: l10n.adminTaskUpdatedAt,
                  minWidth: 150,
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
                  AdminCellText(item.taskType),
                  AdminCellText(
                    item.description.isEmpty ? item.id : item.description,
                  ),
                  AdminCellText(
                    item.ownerLabel?.isNotEmpty == true
                        ? item.ownerLabel!
                        : '-',
                  ),
                  // 直角 1px 细槽进度：与用户页配额槽同一形态，去除圆角残留。
                  SizedBox(
                    width: 110,
                    child: Row(
                      children: [
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                            child: FractionallySizedBox(
                              widthFactor: (item.progress / 100).clamp(
                                0.0,
                                1.0,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                child: const SizedBox(height: 3),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item.progress}%',
                          style: TextStyle(
                            fontFamily: AppTypography.monoFamily,
                            fontFamilyFallback:
                                AppTypography.monoFamilyFallback,
                            fontSize: AppTypography.labelSmall,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AdminStatusTag(
                    label: _taskStatusLabel(l10n, item.status),
                    tone: _taskStatusTone(item.status),
                  ),
                  // 重试轮次：mono 短码 x/3（任务默认最多重试 3 次）。
                  Text(
                    '${item.retryCount}/3',
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: AppTypography.monoFamily,
                      fontFamilyFallback: AppTypography.monoFamilyFallback,
                      fontSize: AppTypography.labelSmall,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AdminCellText(
                    item.errorSummary ?? '-',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    item.createdAt,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    item.updatedAt,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ];
              },
              actionsBuilder: (context, index) {
                final item = page.items[index];
                return [
                  AdminRowIconAction(
                    tooltip: l10n.adminTaskDetailTitle,
                    icon: Icons.info_outlined,
                    onTap: () => onDetail(item),
                  ),
                  if (item.canRetry)
                    AdminRowIconAction(
                      tooltip: l10n.adminRetry,
                      icon: Icons.replay_outlined,
                      onTap: () => onRetry(item.id),
                    ),
                  if (item.canCancel)
                    AdminRowIconAction(
                      tooltip: l10n.adminTaskCancel,
                      icon: Icons.block_outlined,
                      color: context.adminColors.error,
                      onTap: () => onCancel(item.id),
                    ),
                ];
              },
            ),
          const SizedBox(height: 12),
          WorkstationPaginationBar(
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

// 批量操作条（_AdminBatchBar）由任务与会话页共用，定义在
// admin_operations_pages.dart 共享组件区。

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
    return AppDropdown<String>(
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
    );
  }
}

class _DlqTab extends ConsumerStatefulWidget {
  const _DlqTab({
    required this.query,
    required this.state,
    required this.onRetry,
    required this.onDiscard,
  });

  final String query;
  final AsyncValue<List<AdminDlqTask>> state;

  /// 重试死信任务。
  final void Function(String taskId) onRetry;

  /// 丢弃死信任务（破坏性确认）。
  final void Function(AdminDlqTask item) onDiscard;

  @override
  ConsumerState<_DlqTab> createState() => _DlqTabState();
}

class _DlqTabState extends ConsumerState<_DlqTab> {
  /// 勾选索引基于过滤后列表：查询词或数据刷新变化时失效，须清空。
  final Set<int> _selected = <int>{};

  @override
  void didUpdateWidget(_DlqTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query && _selected.isNotEmpty) {
      setState(_selected.clear);
    }
  }

  /// 批量重试勾选的死信：确认后逐条执行，失败项跳过。
  Future<void> _batchRetry(List<AdminDlqTask> filtered) async {
    final l10n = AppLocalizations.of(context);
    final ids = <String>[
      for (final index in _selected)
        if (index >= 0 && index < filtered.length) filtered[index].id,
    ];
    if (ids.isEmpty) {
      return;
    }
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.adminBatchRetryTasks,
      message: l10n.adminBatchConfirmMessage('${ids.length}'),
      confirmLabel: l10n.coreConfirm,
    );
    if (!confirmed || !mounted) return;
    try {
      final result = await ref
          .read(adminOperationsActionsProvider)
          .batchRetryDlq(ids);
      if (!mounted) return;
      setState(_selected.clear);
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

  /// 批量丢弃勾选的死信（破坏性，终态不可重试）：数量确认兜底，
  /// 单行丢弃的短码口令在批量场景不可行，文案明确不可恢复。
  Future<void> _batchDiscard(List<AdminDlqTask> filtered) async {
    final l10n = AppLocalizations.of(context);
    final ids = <String>[
      for (final index in _selected)
        if (index >= 0 && index < filtered.length) filtered[index].id,
    ];
    if (ids.isEmpty) {
      return;
    }
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.adminTaskDiscard,
      message: l10n.adminBatchDiscardConfirmMessage('${ids.length}'),
      confirmLabel: l10n.adminTaskDiscard,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final result = await ref
          .read(adminOperationsActionsProvider)
          .batchDiscardDlq(ids);
      if (!mounted) return;
      setState(_selected.clear);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return widget.state.when(
      loading:
          () => const Padding(
            padding: EdgeInsets.all(16),
            child: AdminListSkeleton(),
          ),
      error: (_, _) => Center(child: Text(l10n.adminLoadFailed(''))),
      data: (items) {
        final filtered =
            widget.query.isEmpty
                ? items
                : items.where((item) {
                  return item.taskType.toLowerCase().contains(
                        widget.query.toLowerCase(),
                      ) ||
                      (item.errorSummary?.toLowerCase().contains(
                            widget.query.toLowerCase(),
                          ) ??
                          false);
                }).toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: AdminTableSection(
            title: l10n.adminDlq,
            subtitle: l10n.adminDlqSubtitle,
            children: [
              if (_selected.isNotEmpty) ...[
                _AdminBatchBar(
                  count: _selected.length,
                  actionLabel: l10n.adminBatchRetryTasks,
                  actionIcon: Icons.replay_rounded,
                  onAction: () => _batchRetry(filtered),
                  secondaryActionLabel: l10n.adminTaskDiscard,
                  secondaryActionIcon: Icons.delete_outline_rounded,
                  onSecondaryAction: () => _batchDiscard(filtered),
                  onClear: () => setState(_selected.clear),
                ),
                const SizedBox(height: 8),
              ],
              AdminDataTable(
                showCheckboxes: true,
                isChecked: (index) => _selected.contains(index),
                onRowCheck:
                    (index, value) => setState(() {
                      value ? _selected.add(index) : _selected.remove(index);
                    }),
                onCheckAll: (value) {
                  setState(() {
                    _selected.clear();
                    if (value) {
                      for (var i = 0; i < filtered.length; i++) {
                        _selected.add(i);
                      }
                    }
                  });
                },
                allChecked:
                    filtered.isNotEmpty && _selected.length == filtered.length,
                someChecked:
                    _selected.isNotEmpty && _selected.length < filtered.length,
                showIndex: true,
                minTableWidth: 980,
                // 两个 48px 图标按钮需 2×48 加余量，默认 168 偏宽。
                actionColumnWidth: 112,
                rowCount: filtered.length,
                emptyState: AdminListEmptyState(
                  // 无死信属健康态，与“筛选无匹配”区分，避免误读为异常。
                  message:
                      widget.query.isEmpty
                          ? l10n.adminDlqEmptyHealthy
                          : l10n.adminNoMatch,
                ),
                columns: [
                  AdminListColumn(
                    key: 'id',
                    label: l10n.adminTaskIdColumn,
                    minWidth: 120,
                  ),
                  AdminListColumn(
                    key: 'taskType',
                    label: l10n.adminFilterTaskType,
                  ),
                  AdminListColumn(
                    key: 'status',
                    label: l10n.adminTaskExecutionStatus,
                    minWidth: 92,
                  ),
                  AdminListColumn(
                    key: 'progress',
                    label: l10n.adminProgress,
                    minWidth: 76,
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
                  // 丢弃确认以任务 ID 前 8 位短码为口令，列表同步展示短码，
                  // 悬停可见完整 ID 便于日志检索。
                  final shortId =
                      item.id.length >= 8 ? item.id.substring(0, 8) : item.id;
                  return [
                    AdminCellText(
                      shortId,
                      tooltipMessage: item.id,
                      style: const TextStyle(
                        fontFamily: AppTypography.monoFamily,
                        fontFamilyFallback: AppTypography.monoFamilyFallback,
                      ),
                    ),
                    AdminCellText(
                      item.taskType,
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
                    // 错误摘要被截断时悬停展示全文并附带堆栈摘要；
                    // 富文案交给 AdminCellText 统一挂载，避免嵌套双 Tooltip。
                    AdminCellText(
                      item.errorSummary ?? l10n.adminNoErrorSummary,
                      style: Theme.of(context).textTheme.bodySmall,
                      tooltipMessage:
                          (item.errorSummary ?? l10n.adminNoErrorSummary) +
                          ((item.stackSummary == null ||
                                  item.stackSummary!.isEmpty)
                              ? ''
                              : '\n\n${item.stackSummary}'),
                    ),
                    AdminCellText(
                      item.updatedAt,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ];
                },
                actionsBuilder: (context, index) {
                  final item = filtered[index];
                  return [
                    AdminRowIconAction(
                      tooltip: l10n.adminRetry,
                      icon: Icons.replay_outlined,
                      onTap: () => widget.onRetry(item.id),
                    ),
                    AdminRowIconAction(
                      tooltip: l10n.adminTaskDiscard,
                      icon: Icons.delete_outline,
                      color: context.adminColors.error,
                      onTap: () => widget.onDiscard(item),
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
