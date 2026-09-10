part of 'file_browser_page.dart';

class _InlineUploadQueueCard extends StatefulWidget {
  const _InlineUploadQueueCard({
    required this.tasks,
    required this.onOpenQueue,
  });

  final List<FileUploadClientTask> tasks;
  final VoidCallback onOpenQueue;

  @override
  State<_InlineUploadQueueCard> createState() => _InlineUploadQueueCardState();
}

class _InlineUploadQueueCardState extends State<_InlineUploadQueueCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tasks = widget.tasks;
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final progress = _uploadTasksProgress(tasks);
    final percentText = '${(progress * 100).round()}%';
    final visibleTasks = tasks.take(4).toList();
    final hiddenCount = tasks.length - visibleTasks.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: context.filesColors.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.tertiary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cloud_upload_outlined,
                    color: context.filesColors.tertiary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.filesUploadQueue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.filesUploadProcessing(tasks.length, percentText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(
                          color: context.filesColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: widget.onOpenQueue,
                  icon: Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(l10n.filesViewAll),
                ),
                IconButton(
                  tooltip:
                      _expanded
                          ? l10n.filesCollapseQueue
                          : l10n.filesExpandQueue,
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 14),
              for (final task in visibleTasks) ...[
                _InlineUploadTaskRow(task: task),
                if (task != visibleTasks.last) const SizedBox(height: 10),
              ],
              if (hiddenCount > 0) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.filesMoreInQueue(hiddenCount),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.filesColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _InlineUploadTaskRow extends StatefulWidget {
  const _InlineUploadTaskRow({required this.task});

  final FileUploadClientTask task;

  @override
  State<_InlineUploadTaskRow> createState() => _InlineUploadTaskRowState();
}

class _InlineUploadTaskRowState extends State<_InlineUploadTaskRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = widget.task.status.toUpperCase();
    final failed = status == 'FAILED';
    final paused = status == 'PAUSED';
    final accent =
        failed
            ? context.filesColors.error
            : paused
            ? context.filesColors.primary
            : context.filesColors.tertiary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color:
              _hovering
                  ? Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.62)
                  : Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                _hovering ? accent.withValues(alpha: 0.28) : Colors.transparent,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(_uploadTaskIcon(status), color: accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.task.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${(widget.task.progress * 100).round()}%',
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(
                            color: context.filesColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    LinearProgressIndicator(
                      value: widget.task.progress,
                      minHeight: 6,
                      color: accent,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${_uploadTaskStatusLabel(status, l10n)} · '
                      '${formatFileSize(widget.task.uploadedBytes)} / ${formatFileSize(widget.task.sizeBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.filesColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double _uploadTasksProgress(List<FileUploadClientTask> tasks) {
  final totalBytes = tasks.fold<int>(
    0,
    (total, task) => total + task.sizeBytes,
  );
  if (totalBytes <= 0) {
    return 0;
  }
  final uploadedBytes = tasks.fold<int>(
    0,
    (total, task) => total + task.uploadedBytes,
  );
  return (uploadedBytes / totalBytes).clamp(0, 1);
}

IconData _uploadTaskIcon(String status) {
  return switch (status) {
    'FAILED' => Icons.error_outline_rounded,
    'PAUSED' => Icons.pause_circle_outline_rounded,
    'QUEUED' => Icons.schedule_rounded,
    _ => Icons.cloud_upload_outlined,
  };
}

String _uploadTaskStatusLabel(String status, AppLocalizations l10n) {
  return switch (status) {
    'QUEUED' => l10n.filesStatusQueued,
    'UPLOADING' => l10n.filesStatusUploading,
    'PAUSED' => l10n.filesStatusPaused,
    'FAILED' => l10n.filesStatusFailed,
    'CONFLICT' => l10n.filesStatusConflict,
    'CREATED' => l10n.filesStatusCreated,
    _ => status,
  };
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: WorkbenchPanel(
        padding: const EdgeInsets.all(18),
        backgroundColor: context.filesColors.surfaceContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.filesColors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Icon(icon, color: color),
              ],
            ),
            const Spacer(),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.filesColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileToolbar extends ConsumerWidget {
  const _FileToolbar({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final isNarrow = MediaQuery.of(context).size.width < 600;
    final viewToggle = ToggleButtons(
      isSelected: [
        state.viewMode == FileBrowserViewMode.list,
        state.viewMode == FileBrowserViewMode.grid,
      ],
      onPressed:
          enabled
              ? (index) => controller.setViewMode(
                index == 0
                    ? FileBrowserViewMode.list
                    : FileBrowserViewMode.grid,
              )
              : null,
      borderRadius: BorderRadius.circular(MobileLayoutTokens.radius),
      constraints: const BoxConstraints(
        minWidth: MobileLayoutTokens.minimumTarget,
        minHeight: MobileLayoutTokens.minimumTarget,
      ),
      children: const [
        Icon(Icons.view_list_rounded, size: 18),
        Icon(Icons.grid_view_rounded, size: 18),
      ],
    );
    return Row(
      children: [
        if (isNarrow) ...[
          Expanded(
            child: PopupMenuButton<FileBrowserSortBy>(
              tooltip: l10n.filesSortBy,
              onSelected: enabled ? (sort) => controller.setSortBy(sort) : null,
              itemBuilder:
                  (context) => [
                    CheckedPopupMenuItem(
                      value: FileBrowserSortBy.name,
                      checked: state.sortBy == FileBrowserSortBy.name,
                      child: Text(l10n.filesSortName),
                    ),
                    CheckedPopupMenuItem(
                      value: FileBrowserSortBy.updatedAt,
                      checked: state.sortBy == FileBrowserSortBy.updatedAt,
                      child: Text(l10n.filesSortTime),
                    ),
                    CheckedPopupMenuItem(
                      value: FileBrowserSortBy.size,
                      checked: state.sortBy == FileBrowserSortBy.size,
                      child: Text(l10n.filesSortSize),
                    ),
                  ],
              child: Container(
                height: MobileLayoutTokens.minimumTarget,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: context.mobileColors.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(
                    MobileLayoutTokens.radius,
                  ),
                  border: Border.all(color: context.mobileColors.outline),
                ),
                child: Row(
                  children: [
                    Icon(Icons.sort_rounded, size: 19),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        switch (state.sortBy) {
                          FileBrowserSortBy.name => l10n.filesSortName,
                          FileBrowserSortBy.updatedAt => l10n.filesSortTime,
                          FileBrowserSortBy.size => l10n.filesSortSize,
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.mobileColors.textPrimary,
                          fontSize: AppTypography.bodyMedium,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.expand_more_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          viewToggle,
        ] else ...[
          SegmentedButton<FileBrowserSortBy>(
            segments: [
              ButtonSegment(
                value: FileBrowserSortBy.name,
                label: Text(l10n.filesSortName),
              ),
              ButtonSegment(
                value: FileBrowserSortBy.updatedAt,
                label: Text(l10n.filesSortTime),
              ),
              ButtonSegment(
                value: FileBrowserSortBy.size,
                label: Text(l10n.filesSortSize),
              ),
            ],
            selected: {state.sortBy},
            onSelectionChanged:
                enabled
                    ? (selection) => controller.setSortBy(selection.first)
                    : null,
          ),
          const Spacer(),
          viewToggle,
        ],
      ],
    );
  }
}

class _FileCategoryFilter extends ConsumerWidget {
  const _FileCategoryFilter({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    const categories = [
      FileBrowserFileCategory.all,
      FileBrowserFileCategory.image,
      FileBrowserFileCategory.video,
      FileBrowserFileCategory.audio,
    ];
    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final category in categories) ...[
              if (category != categories.first) const SizedBox(width: 8),
              _CategoryCapsule(
                label: category.labelOf(l10n),
                icon: category.icon,
                isActive: state.fileCategory == category,
                enabled: enabled,
                onTap:
                    () => unawaited(
                      _runFileAction(
                        context,
                        () => controller.setFileCategory(category),
                      ),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 窄屏排序/类型筛选入口：存在激活筛选时显示圆点，点按展开底部筛选面板。
class _FileFilterButton extends ConsumerWidget {
  const _FileFilterButton({required this.state});

  final FileBrowserState state;

  bool get _filterActive =>
      state.sortBy != FileBrowserSortBy.name ||
      state.fileCategory != FileBrowserFileCategory.all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: l10n.filesFilterSort,
          onPressed: state.isBusy ? null : () => _showFilterSheet(context, ref),
          icon: const Icon(Icons.tune_rounded, size: 20),
        ),
        if (_filterActive)
          Positioned(
            top: 9,
            right: 9,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: context.filesColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    const categories = [
      FileBrowserFileCategory.all,
      FileBrowserFileCategory.image,
      FileBrowserFileCategory.video,
      FileBrowserFileCategory.audio,
    ];
    final sorts = <FileBrowserSortBy, String>{
      FileBrowserSortBy.name: l10n.filesSortName,
      FileBrowserSortBy.updatedAt: l10n.filesSortTime,
      FileBrowserSortBy.size: l10n.filesSortSize,
    };
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            top: false,
            child: Consumer(
              builder: (context, sheetRef, _) {
                final current =
                    sheetRef.watch(fileBrowserControllerProvider).asData?.value;
                if (current == null) {
                  return const SizedBox.shrink();
                }
                final enabled = !current.isBusy;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Text(
                        l10n.filesFilterSort,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in sorts.entries)
                            _CategoryCapsule(
                              label: entry.value,
                              icon: Icons.sort_rounded,
                              isActive: current.sortBy == entry.key,
                              enabled: enabled,
                              onTap: () async {
                                controller.setSortBy(entry.key);
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final category in categories)
                            _CategoryCapsule(
                              label: category.labelOf(l10n),
                              icon: category.icon,
                              isActive: current.fileCategory == category,
                              enabled: enabled,
                              onTap:
                                  () => unawaited(
                                    _runFileAction(
                                      sheetContext,
                                      () =>
                                          controller.setFileCategory(category),
                                    ),
                                  ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ),
    );
  }
}

/// 窄屏列表/网格视图切换按钮（单钮往复，展示目标视图图标）。
class _FileViewToggleButton extends ConsumerWidget {
  const _FileViewToggleButton({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final isList = state.viewMode == FileBrowserViewMode.list;
    return IconButton(
      tooltip: AppLocalizations.of(context).filesSwitchView,
      onPressed:
          enabled
              ? () => controller.setViewMode(
                isList ? FileBrowserViewMode.grid : FileBrowserViewMode.list,
              )
              : null,
      icon: Icon(
        isList ? Icons.grid_view_rounded : Icons.view_list_rounded,
        size: 20,
      ),
    );
  }
}

class _CategoryCapsule extends StatefulWidget {
  const _CategoryCapsule({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_CategoryCapsule> createState() => _CategoryCapsuleState();
}

class _CategoryCapsuleState extends State<_CategoryCapsule>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _bounceAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _bounceController.forward().then((_) => _bounceController.reverse());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.filesColors;
    return AnimatedBuilder(
      animation: _bounceAnimation,
      builder:
          (context, child) =>
              Transform.scale(scale: _bounceAnimation.value, child: child),
      child: GestureDetector(
        onTap: widget.enabled ? _handleTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color:
                widget.isActive
                    ? c.primary.withValues(alpha: 0.15)
                    : c.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
            border:
                widget.isActive
                    ? Border.all(color: c.primary.withValues(alpha: 0.3))
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.isActive ? c.primary : c.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight:
                      widget.isActive ? FontWeight.w600 : FontWeight.w400,
                  color: widget.isActive ? c.primary : c.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Breadcrumbs extends ConsumerWidget {
  const _Breadcrumbs({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final c = context.filesColors;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: c.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(
              tooltip: AppLocalizations.of(context).filesGoToParent,
              onPressed:
                  enabled && state.breadcrumbs.isNotEmpty
                      ? () => unawaited(
                        _runFileAction(context, controller.goToParent),
                      )
                      : null,
              icon: Icon(Icons.arrow_upward_rounded, size: 19),
            ),
            _SpaceToggle(
              currentSpaceType: state.spaceType,
              enabled: enabled,
              compact: false,
              onChanged: (value) {
                if (value != state.spaceType) {
                  unawaited(
                    _runFileAction(
                      context,
                      () => controller.switchSpace(value),
                    ),
                  );
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: c.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
            TextButton.icon(
              onPressed:
                  enabled && state.breadcrumbs.isNotEmpty
                      ? () => unawaited(
                        _runFileAction(context, controller.goToRoot),
                      )
                      : null,
              icon: Icon(Icons.home_outlined, size: 17),
              label: Text(AppLocalizations.of(context).filesRootDirectory),
            ),
            for (var index = 0; index < state.breadcrumbs.length; index++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: c.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
              if (index == state.breadcrumbs.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    state.breadcrumbs[index].name,
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w700,
                      color: c.primary,
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed:
                      enabled
                          ? () => unawaited(
                            _runFileAction(
                              context,
                              () => controller.goToBreadcrumb(index),
                            ),
                          )
                          : null,
                  child: Text(
                    state.breadcrumbs[index].name,
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w400,
                      color: c.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 面包屑内的空间滑动切换器。
///
/// 两个紧凑胶囊：个人空间 / 共享空间，点击切换，当前选中项高亮。
class _SpaceToggle extends StatelessWidget {
  const _SpaceToggle({
    required this.currentSpaceType,
    required this.enabled,
    required this.onChanged,
    this.compact = true,
  });

  final String currentSpaceType;
  final bool enabled;
  final ValueChanged<String> onChanged;

  /// true = 移动端紧凑样式，false = 桌面端稍大样式。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.filesColors;
    final isShared = currentSpaceType == 'SHARED';
    final height = compact ? 26.0 : 30.0;
    final gap = compact ? 2.0 : 3.0;

    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SpacePill(
            icon: Icons.lock_outline,
            label: l10n.importToPersonalSpace,
            selected: !isShared,
            enabled: enabled,
            onTap: () => onChanged('PERSONAL'),
            colors: c,
            compact: compact,
          ),
          SizedBox(width: gap),
          _SpacePill(
            icon: Icons.people_outline,
            label: l10n.importToSharedSpace,
            selected: isShared,
            enabled: enabled,
            onTap: () => onChanged('SHARED'),
            colors: c,
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _SpacePill extends StatelessWidget {
  const _SpacePill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.colors,
    this.compact = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final FilesColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 12.0 : 14.0;
    final fontSize = compact ? 11.0 : 12.5;
    final hPad = compact ? 8.0 : 12.0;
    final vPad = compact ? 3.0 : 4.0;
    final gap = compact ? 3.0 : 5.0;
    final radius = compact ? 6.0 : 8.0;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: selected ? colors.surfaceContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                  : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: iconSize,
              color:
                  selected
                      ? colors.primary
                      : colors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            SizedBox(width: gap),
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color:
                    selected
                        ? colors.primary
                        : colors.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
