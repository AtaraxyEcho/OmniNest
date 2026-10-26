part of 'admin_operations_pages.dart';

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
        severity:
            result.failedIds.isEmpty
                ? OmniFeedbackSeverity.success
                : OmniFeedbackSeverity.warning,
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
        severity:
            result.failedIds.isEmpty
                ? OmniFeedbackSeverity.success
                : OmniFeedbackSeverity.warning,
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
