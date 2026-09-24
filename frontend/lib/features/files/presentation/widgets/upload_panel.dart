import 'package:flutter/material.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/presentation/widgets/file_upload_task_message.dart';

class UploadPanel extends StatelessWidget {
  const UploadPanel({
    required this.localTasks,
    required this.enabled,
    required this.onPauseLocalTask,
    required this.onResumeLocalTask,
    required this.onRemoveLocalTask,
    this.onResolveConflict,
    super.key,
  });

  final List<FileUploadClientTask> localTasks;
  final bool enabled;
  final void Function(String taskId) onPauseLocalTask;
  final Future<void> Function(String taskId) onResumeLocalTask;
  final Future<void> Function(String taskId) onRemoveLocalTask;
  final Future<void> Function(String taskId)? onResolveConflict;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _PanelSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: Icons.sync_rounded,
            title: l10n.filesUploadQueue,
            subtitle: l10n.filesUploadQueueDesc,
          ),
          const SizedBox(height: 18),
          if (localTasks.isEmpty)
            const _UploadEmptyState()
          else
            _UploadQueueGrid(
              localTasks: localTasks,
              enabled: enabled,
              onPauseLocalTask: onPauseLocalTask,
              onResumeLocalTask: onResumeLocalTask,
              onRemoveLocalTask: onRemoveLocalTask,
              onResolveConflict: onResolveConflict,
            ),
        ],
      ),
    );
  }
}

class _UploadQueueGrid extends StatelessWidget {
  const _UploadQueueGrid({
    required this.localTasks,
    required this.enabled,
    required this.onPauseLocalTask,
    required this.onResumeLocalTask,
    required this.onRemoveLocalTask,
    this.onResolveConflict,
  });

  final List<FileUploadClientTask> localTasks;
  final bool enabled;
  final void Function(String taskId) onPauseLocalTask;
  final Future<void> Function(String taskId) onResumeLocalTask;
  final Future<void> Function(String taskId) onRemoveLocalTask;
  final Future<void> Function(String taskId)? onResolveConflict;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failedTasks =
        localTasks
            .where(
              (task) => task.status == 'FAILED' || task.status == 'CONFLICT',
            )
            .toList();
    final runningTasks =
        localTasks
            .where(
              (task) => task.status != 'FAILED' && task.status != 'CONFLICT',
            )
            .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 780 ? 2 : 1;
        final children = [
          _QueueLane(
            title: l10n.filesLocalUpload,
            subtitle: l10n.filesUploadTaskCount(runningTasks.length),
            emptyText: l10n.filesNoLocalUpload,
            children: [
              for (final task in runningTasks.take(8))
                _LocalTaskItem(
                  task: task,
                  enabled: enabled,
                  onPause: onPauseLocalTask,
                  onResume: onResumeLocalTask,
                  onRemove: onRemoveLocalTask,
                ),
            ],
          ),
          _QueueLane(
            title: l10n.filesFailedTasks,
            subtitle: l10n.filesUploadTaskCount(failedTasks.length),
            emptyText: l10n.filesNoFailedTasks,
            children: [
              for (final task in failedTasks.take(8))
                _LocalTaskItem(
                  task: task,
                  enabled: enabled,
                  onPause: onPauseLocalTask,
                  onResume: onResumeLocalTask,
                  onRemove: onRemoveLocalTask,
                  onResolveConflict: onResolveConflict,
                ),
            ],
          ),
        ];
        if (columns == 1) {
          return Column(
            children: [
              for (final child in children) ...[
                child,
                const SizedBox(height: 14),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final child in children) ...[
              Expanded(child: child),
              if (child != children.last) const SizedBox(width: 14),
            ],
          ],
        );
      },
    );
  }
}

class _QueueLane extends StatefulWidget {
  const _QueueLane({
    required this.title,
    required this.subtitle,
    required this.emptyText,
    required this.children,
  });

  final String title;
  final String subtitle;
  final String emptyText;
  final List<Widget> children;

  @override
  State<_QueueLane> createState() => _QueueLaneState();
}

class _QueueLaneState extends State<_QueueLane> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color:
              _hovering
                  ? context.filesColors.surfaceContainerHigh.withValues(
                    alpha: 0.58,
                  )
                  : context.filesColors.surfaceContainerHigh.withValues(
                    alpha: 0.42,
                  ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                _hovering
                    ? context.filesColors.outlineVariant.withValues(alpha: 0.40)
                    : context.filesColors.outlineVariant.withValues(
                      alpha: 0.24,
                    ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    widget.subtitle,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.filesColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.children.isEmpty)
                _LaneEmpty(text: widget.emptyText)
              else
                for (final child in widget.children) ...[
                  child,
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LaneEmpty extends StatefulWidget {
  const _LaneEmpty({required this.text});

  final String text;

  @override
  State<_LaneEmpty> createState() => _LaneEmptyState();
}

class _LaneEmptyState extends State<_LaneEmpty> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 26),
        decoration: BoxDecoration(
          color:
              _hovering
                  ? context.filesColors.surface.withValues(alpha: 0.50)
                  : context.filesColors.surface.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          widget.text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.filesColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _LocalTaskItem extends StatelessWidget {
  const _LocalTaskItem({
    required this.task,
    required this.enabled,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
    this.onResolveConflict,
  });

  final FileUploadClientTask task;
  final bool enabled;
  final void Function(String taskId) onPause;
  final Future<void> Function(String taskId) onResume;
  final Future<void> Function(String taskId) onRemove;
  final Future<void> Function(String taskId)? onResolveConflict;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canPause = task.status == 'UPLOADING' || task.status == 'QUEUED';
    final canResume = task.status == 'PAUSED' || task.status == 'FAILED';
    final isConflict = task.status == 'CONFLICT';
    final message = localizedFileUploadTaskMessage(task, l10n);
    return _TaskCard(
      title: task.fileName,
      subtitle:
          message.isEmpty
              ? _statusLabel(task.status, l10n)
              : '${_statusLabel(task.status, l10n)} · $message',
      progress: task.progress,
      trailing:
          '${formatFileSize(task.uploadedBytes)} / ${formatFileSize(task.sizeBytes)}',
      status: task.status,
      actions: [
        if (canPause)
          _ActionIconButton(
            tooltip: l10n.filesPauseUpload,
            icon: Icons.pause_rounded,
            enabled: enabled,
            onTap: () => onPause(task.id),
          ),
        if (canResume)
          _ActionIconButton(
            tooltip: l10n.filesResumeUpload,
            icon: Icons.play_arrow_rounded,
            enabled: enabled,
            onTap: () => onResume(task.id),
          ),
        if (isConflict && onResolveConflict != null)
          _ActionIconButton(
            tooltip: l10n.filesCleanAndRetry,
            icon: Icons.cleaning_services_rounded,
            enabled: enabled,
            onTap: () => onResolveConflict!(task.id),
          ),
        _ActionIconButton(
          tooltip: l10n.filesDeleteTask,
          icon: Icons.delete_outline_rounded,
          enabled: enabled,
          onTap: () => onRemove(task.id),
          destructive: true,
        ),
      ],
    );
  }
}

class _TaskCard extends StatefulWidget {
  const _TaskCard({
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.trailing,
    required this.status,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final double progress;
  final String trailing;
  final String status;
  final List<Widget> actions;

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _hovering = false;

  Color _statusAccent(String status) {
    return switch (status) {
      'UPLOADING' => context.filesColors.primary,
      'QUEUED' => context.filesColors.onSurfaceVariant,
      'PAUSED' => context.filesColors.tertiary,
      'FAILED' => context.filesColors.error,
      'CONFLICT' => context.filesColors.tertiary,
      'COMPLETED' => context.filesColors.primary,
      _ => context.filesColors.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final accent = _statusAccent(widget.status);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color:
              _hovering
                  ? context.filesColors.surfaceContainerHigh.withValues(
                    alpha: 0.78,
                  )
                  : context.filesColors.surfaceContainerHigh.withValues(
                    alpha: 0.58,
                  ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                _hovering
                    ? accent.withValues(alpha: 0.30)
                    : context.filesColors.outlineVariant.withValues(
                      alpha: 0.24,
                    ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.subtitle,
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
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _StatusPill(
                        label: _statusLabel(
                          widget.status,
                          AppLocalizations.of(context),
                        ),
                        status: widget.status,
                      ),
                      if (widget.actions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 2,
                          runSpacing: 2,
                          children: [
                            for (final action in widget.actions)
                              SizedBox.square(dimension: 48, child: action),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: AnimatedLinearProgress(
                  value: widget.progress,
                  color: accent,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.trailing,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.filesColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnimatedLinearProgress extends StatelessWidget {
  const AnimatedLinearProgress({
    super.key,
    required this.value,
    required this.color,
  });

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: value, end: value),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return LinearProgressIndicator(
          value: animatedValue,
          minHeight: 7,
          backgroundColor: context.filesColors.surfaceContainerHigh,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        );
      },
    );
  }
}

class _ActionIconButton extends StatefulWidget {
  const _ActionIconButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.destructive = false,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<_ActionIconButton> createState() => _ActionIconButtonState();
}

class _ActionIconButtonState extends State<_ActionIconButton> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final baseColor =
        widget.destructive
            ? context.filesColors.error
            : context.filesColors.onSurfaceVariant;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp:
            widget.enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel:
            widget.enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.enabled ? widget.onTap : null,
        // 命中盒按 48 取（触屏标准），按下缩放与悬停底色仍按 34 的视觉尺寸绘制；
        // 透明区间也要能命中，故 opaque。
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.9 : 1.0,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color:
                      _hovering && widget.enabled
                          ? (widget.destructive
                              ? context.filesColors.error.withValues(
                                alpha: 0.12,
                              )
                              : context.filesColors.onSurfaceVariant.withValues(
                                alpha: 0.10,
                              ))
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Tooltip(
                  message: widget.tooltip,
                  child: Icon(
                    widget.icon,
                    size: 18,
                    color:
                        widget.enabled
                            ? (_hovering
                                ? baseColor
                                : context.filesColors.onSurfaceVariant)
                            : context.filesColors.onSurfaceVariant.withValues(
                              alpha: 0.3,
                            ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadEmptyState extends StatefulWidget {
  const _UploadEmptyState();

  @override
  State<_UploadEmptyState> createState() => _UploadEmptyStateState();
}

class _UploadEmptyStateState extends State<_UploadEmptyState> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 18),
        decoration: BoxDecoration(
          color:
              _hovering
                  ? context.filesColors.surfaceContainerHigh.withValues(
                    alpha: 0.50,
                  )
                  : context.filesColors.surfaceContainerHigh.withValues(
                    alpha: 0.36,
                  ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                _hovering
                    ? context.filesColors.outlineVariant.withValues(alpha: 0.36)
                    : context.filesColors.outlineVariant.withValues(
                      alpha: 0.22,
                    ),
          ),
        ),
        child: Column(
          children: [
            AnimatedScale(
              scale: _hovering ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.cloud_done_outlined,
                color: context.filesColors.primary.withValues(alpha: 0.86),
                size: 34,
              ),
            ),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context).filesNoUploadTasks),
          ],
        ),
      ),
    );
  }
}

class _PanelSurface extends StatelessWidget {
  const _PanelSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.filesColors.surfaceContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.filesColors.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(22), child: child),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.filesColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: context.filesColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.filesColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatefulWidget {
  const _StatusPill({required this.label, required this.status});

  final String label;
  final String status;

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill> {
  bool _hovering = false;

  Color _pillColor(String status) {
    return switch (status) {
      'UPLOADING' => context.filesColors.primary,
      'QUEUED' => context.filesColors.onSurfaceVariant,
      'PAUSED' => context.filesColors.tertiary,
      'FAILED' => context.filesColors.error,
      'COMPLETED' => context.filesColors.primary,
      'CONFLICT' => context.filesColors.tertiary,
      _ => context.filesColors.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _pillColor(widget.status);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color:
              _hovering
                  ? color.withValues(alpha: 0.20)
                  : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

String _statusLabel(String status, AppLocalizations l10n) {
  return switch (status) {
    'QUEUED' => l10n.filesStatusQueued,
    'UPLOADING' => l10n.filesStatusUploading,
    'PAUSED' => l10n.filesStatusPaused,
    'COMPLETED' => l10n.filesStatusCompleted,
    'FAILED' => l10n.filesStatusFailed,
    'CONFLICT' => l10n.filesStatusConflict,
    'CREATED' => l10n.filesStatusCreated,
    _ => status,
  };
}
