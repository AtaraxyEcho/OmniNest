part of 'admin_operations_pages.dart';

/// 任务分区的桌面排版与工位指标条。

/// 任务指标条（移动/平板口径）：从任务页抽到本 part，页面只保留一行调用，
/// 让页面在 800 行闸门下仍有空间加桌面分支。
class _TaskMetrics extends StatelessWidget {
  const _TaskMetrics({
    required this.running,
    required this.queued,
    required this.retryWait,
    required this.failedStatus,
    required this.dlqOnPage,
    required this.dlqCount,
  });

  final int running;
  final int queued;
  final int retryWait;
  final int failedStatus;
  final int dlqOnPage;
  final int dlqCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.adminColors;
    final queuedReady = queued + retryWait;
    final failed = failedStatus + dlqOnPage;
    return _MetricGrid(
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
    );
  }
}

/// 任务分区的桌面排版（样例 `Admin.tsx` 的 Tasks / Dead letters）：
/// 一张卡里是分段页签、状态/类型 chips 与任务行，底部翻页条。
class _DesktopTasksPanel extends StatelessWidget {
  const _DesktopTasksPanel({
    required this.page,
    required this.dlq,
    required this.status,
    required this.taskType,
    required this.taskTypes,
    required this.query,
    required this.searchController,
    required this.onSearch,
    required this.tabIndex,
    this.showTabs = true,
    this.embedded = false,
    required this.busy,
    required this.onFilters,
    required this.onTab,
    required this.onPage,
    required this.onRefresh,
    required this.onExport,
    required this.onDiscardAllDlq,
    required this.onRetry,
    required this.onCancel,
    required this.onDetail,
    required this.onRetryDlq,
    required this.onDiscardDlq,
  });

  final AdminPage<AdminTaskRecord> page;
  final AsyncValue<List<AdminDlqTask>> dlq;
  final String status;
  final String taskType;
  final List<String> taskTypes;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final int tabIndex;
  final bool showTabs;
  final bool embedded;
  final bool busy;
  final void Function(String status, String taskType) onFilters;
  final ValueChanged<int> onTab;
  final ValueChanged<int> onPage;
  final VoidCallback onRefresh;
  final VoidCallback onExport;
  final VoidCallback onDiscardAllDlq;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onCancel;
  final ValueChanged<AdminTaskRecord> onDetail;
  final ValueChanged<String> onRetryDlq;
  final ValueChanged<AdminDlqTask> onDiscardDlq;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final allDlqItems = dlq.value ?? const <AdminDlqTask>[];
    final normalizedQuery = query.toLowerCase();
    final dlqItems = allDlqItems
        .where((task) {
          return normalizedQuery.isEmpty ||
              task.taskType.toLowerCase().contains(normalizedQuery) ||
              (task.errorSummary ?? '').toLowerCase().contains(
                normalizedQuery,
              ) ||
              task.id.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (embedded)
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 6,
              children: [
                if (tabIndex == 0)
                  DesktopButton(
                    label: l10n.adminListExportCsv,
                    icon: DesktopIcons.download,
                    variant: DesktopButtonVariant.ghost,
                    onPressed: onExport,
                  )
                else
                  DesktopButton(
                    label: l10n.adminDlqDiscardAll,
                    icon: DesktopIcons.trash,
                    variant: DesktopButtonVariant.ghost,
                    onPressed: allDlqItems.isEmpty ? null : onDiscardAllDlq,
                  ),
                DesktopIconButton(
                  icon: DesktopIcons.restore,
                  tooltip: l10n.adminRefresh,
                  onPressed: busy ? null : onRefresh,
                ),
              ],
            ),
          ),
        if (showTabs)
          Align(
            alignment: Alignment.centerLeft,
            child: DesktopSeg<int>(
              options: const [0, 1],
              value: tabIndex,
              small: true,
              labelOf:
                  (value) => value == 0 ? l10n.adminTaskList : l10n.adminDlq,
              onChanged: onTab,
            ),
          ),
        if (tabIndex == 0) ...[
          if (showTabs) const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: DesktopTextField(
                  controller: searchController,
                  hint:
                      tabIndex == 0
                          ? l10n.adminTaskSearchHint
                          : l10n.adminDlqSearchHint,
                  prefixIcon: DesktopIcons.search,
                  height: 36,
                  onChanged: onSearch,
                ),
              ),
              for (final value in const [
                'ALL',
                'ACTIVE',
                'SUCCEEDED',
                'FAILED',
                'CANCELLED',
              ])
                DesktopChipButton(
                  label: switch (value) {
                    'ALL' => l10n.adminAll,
                    'ACTIVE' => l10n.adminActive,
                    'SUCCEEDED' => l10n.adminTaskFilterSucceeded,
                    'FAILED' => l10n.adminFailedTasks,
                    _ => l10n.filesStatusCancelled,
                  },
                  selected: status == value,
                  onTap: () => onFilters(value, taskType),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.adminFilterTaskType,
                    style: DesktopType.caption(skin.text3),
                  ),
                  const SizedBox(width: 8),
                  DesktopSelect<String>(
                    value: taskType,
                    variant: DesktopSelectVariant.small,
                    options: [
                      for (final value in taskTypes)
                        DesktopSelectOption(
                          value: value,
                          label: value == 'ALL' ? l10n.adminAll : value,
                        ),
                    ],
                    onChanged: (value) => onFilters(status, value),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (page.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  l10n.adminNoMatch,
                  style: DesktopType.caption(skin.text3),
                ),
              ),
            )
          else
            for (var i = 0; i < page.items.length; i++)
              _DesktopTaskRow(
                task: page.items[i],
                first: i == 0,
                onRetry: () => onRetry(page.items[i].id),
                onCancel: () => onCancel(page.items[i].id),
                onDetail: () => onDetail(page.items[i]),
              ),
          AdminPager(
            page: page.page,
            totalPages: page.totalPages,
            summary: l10n.adminTotalTasks,
            onPageChanged: onPage,
          ),
        ] else ...[
          if (showTabs) const SizedBox(height: 12),
          if (dlqItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  allDlqItems.isEmpty
                      ? l10n.adminDlqEmptyHealthy
                      : l10n.adminNoMatch,
                  style: DesktopType.caption(skin.text3),
                ),
              ),
            )
          else
            for (var i = 0; i < dlqItems.length; i++)
              _DesktopDlqRow(
                task: dlqItems[i],
                first: i == 0,
                onRetry: () => onRetryDlq(dlqItems[i].id),
                onDiscard: () => onDiscardDlq(dlqItems[i]),
              ),
        ],
      ],
    );
    if (embedded) return content;
    return AdminCard(
      title: l10n.adminBackgroundTasks,
      count: page.totalElements,
      subtitle: l10n.adminBackgroundTasksSubtitle,
      action: DesktopIconButton(
        icon: DesktopIcons.restore,
        tooltip: l10n.adminRefresh,
        onPressed: busy ? null : onRefresh,
      ),
      childGap: 14,
      child: content,
    );
  }
}

class _DesktopTaskRow extends StatelessWidget {
  const _DesktopTaskRow({
    required this.task,
    required this.first,
    required this.onRetry,
    required this.onCancel,
    required this.onDetail,
  });

  final AdminTaskRecord task;
  final bool first;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final status = task.status.toUpperCase();
    final statusLabel = switch (status) {
      'RUNNING' => l10n.adminTaskStatusRunning,
      'COMPLETED' => l10n.adminTaskFilterSucceeded,
      'FAILED' => l10n.adminFailedTasks,
      'CANCELLED' => l10n.filesStatusCancelled,
      'QUEUED' => l10n.adminQueued,
      'RETRY_WAIT' => l10n.adminTaskStatusRetryWait,
      'DLQ' => l10n.adminTaskStatusDlq,
      _ => status,
    };
    final tone =
        status == 'FAILED' || status == 'DLQ'
            ? skin.bad
            : status == 'COMPLETED'
            ? skin.ok
            : status == 'RUNNING'
            ? skin.accent
            : status == 'RETRY_WAIT'
            ? skin.warm
            : skin.text3;
    final meta = <String>[
      task.taskType,
      if (task.ownerLabel != null && task.ownerLabel!.isNotEmpty)
        '@${task.ownerLabel}',
      _shortDateTime(task.updatedAt),
    ].join(' · ');

    return GestureDetector(
      onTap: onDetail,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: skin.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                status == 'COMPLETED'
                    ? DesktopIcons.check
                    : status == 'FAILED' || status == 'DLQ'
                    ? DesktopIcons.info
                    : status == 'RUNNING'
                    ? DesktopIcons.retry
                    : DesktopIcons.clock,
                size: 14,
                color: tone,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.description.isEmpty ? task.taskType : task.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.rowTitle(skin.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    task.errorSummary ?? meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.caption(
                      task.errorSummary == null ? skin.text3 : skin.bad,
                    ),
                  ),
                  if (status == 'RUNNING') ...[
                    const SizedBox(height: 6),
                    _DesktopProgress(value: task.progress / 100),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _DesktopPill(label: statusLabel, tone: tone),
            const SizedBox(width: 8),
            if (task.canRetry)
              DesktopButton(
                label: l10n.adminRetry,
                variant: DesktopButtonVariant.soft,
                onPressed: onRetry,
              ),
            if (task.canCancel) ...[
              if (task.canRetry) const SizedBox(width: 6),
              DesktopButton(
                label: l10n.adminTaskCancel,
                variant: DesktopButtonVariant.ghost,
                onPressed: onCancel,
              ),
            ],
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _DesktopDlqRow extends StatelessWidget {
  const _DesktopDlqRow({
    required this.task,
    required this.first,
    required this.onRetry,
    required this.onDiscard,
  });

  final AdminDlqTask task;
  final bool first;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.taskType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.rowTitle(skin.text),
                ),
                const SizedBox(height: 2),
                Text(
                  '${task.errorSummary ?? ''} · ${_shortDateTime(task.updatedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.caption(skin.bad),
                ),
              ],
            ),
          ),
          DesktopButton(
            label: l10n.adminRetry,
            variant: DesktopButtonVariant.soft,
            onPressed: onRetry,
          ),
          const SizedBox(width: 6),
          DesktopButton(
            label: l10n.adminTaskDiscard,
            variant: DesktopButtonVariant.ghost,
            onPressed: onDiscard,
          ),
        ],
      ),
    );
  }
}
