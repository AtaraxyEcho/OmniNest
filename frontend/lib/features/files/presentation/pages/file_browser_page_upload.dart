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
    final colors = context.filesColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Icon(
                    Icons.cloud_upload_outlined,
                    size: 16,
                    color: colors.onSurfaceVariant,
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
    final colors = context.filesColors;
    final accent =
        failed
            ? colors.error
            : paused
            ? colors.warning
            : colors.success;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: MotionToken.fast,
        decoration: BoxDecoration(
          color:
              _hovering
                  ? colors.surfaceContainerHigh
                  : colors.surfaceContainerLow,
          border: Border.all(
            color:
                _hovering
                    ? accent.withValues(alpha: 0.5)
                    : colors.outlineVariant,
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
                      minHeight: 2,
                      color: accent,
                      backgroundColor: colors.outlineVariant,
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
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor =
        isDark
            ? FilesWorkstationPalette.outlineDark
            : FilesWorkstationPalette.outlineLight;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelMicro,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w500,
                    color: labelColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTypography.headlineSmall,
              height: 30 / AppTypography.headlineSmall,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.labelSmall,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

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

/// 直角筛选 chip：1px 边界常驻，激活纯靠变色，杜绝尺寸跳变。
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

class _CategoryCapsuleState extends State<_CategoryCapsule> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.filesColors;
    final active = widget.isActive;
    final foreground =
        active
            ? c.onSurface
            : _hovering && widget.enabled
            ? c.onSurface
            : c.onSurfaceVariant;
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: MotionToken.fast,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? c.surfaceContainerHigh : c.surfaceContainerLow,
            border: Border.all(color: c.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: foreground),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: foreground,
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _CrumbButton(
            icon: Icons.home_outlined,
            label: AppLocalizations.of(context).filesRootDirectory,
            enabled: enabled && state.breadcrumbs.isNotEmpty,
            onTap:
                () => unawaited(_runFileAction(context, controller.goToRoot)),
          ),
          for (var index = 0; index < state.breadcrumbs.length; index++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '/',
                style: TextStyle(
                  fontSize: AppTypography.labelMedium,
                  color: c.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            if (index == state.breadcrumbs.length - 1)
              Text(
                state.breadcrumbs[index].name,
                style: TextStyle(
                  fontSize: AppTypography.labelMedium,
                  fontWeight: FontWeight.w600,
                  color: c.onSurface,
                ),
              )
            else
              _CrumbButton(
                label: state.breadcrumbs[index].name,
                enabled: enabled,
                onTap:
                    () => unawaited(
                      _runFileAction(
                        context,
                        () => controller.goToBreadcrumb(index),
                      ),
                    ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CrumbButton extends StatefulWidget {
  const _CrumbButton({
    this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData? icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_CrumbButton> createState() => _CrumbButtonState();
}

class _CrumbButtonState extends State<_CrumbButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.filesColors;
    final foreground =
        _hovering && widget.enabled ? c.onSurface : c.onSurfaceVariant;
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 14, color: foreground),
              const SizedBox(width: 4),
            ],
            Text(
              widget.label,
              style: TextStyle(
                fontSize: AppTypography.labelMedium,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
