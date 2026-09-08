import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({required this.task, this.onRetry, super.key});

  final TaskRecord task;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusIcon(status: task.status),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.taskType,
                      style: TextStyle(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    if (task.routingKey != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        task.routingKey!,
                        style: TextStyle(
                          fontSize: AppTypography.bodySmall,
                          color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _StatusBadge(status: task.status, l10n: l10n),
            ],
          ),
          if (task.errorMessage != null && task.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                task.errorMessage!,
                style: TextStyle(
                  fontSize: AppTypography.bodySmall,
                  color: colors.error.withValues(alpha: 0.8),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (task.isPending || task.isRunning) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _phaseLabel(l10n, task.phase),
                    style: TextStyle(
                      fontSize: AppTypography.bodySmall,
                      color: colors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${task.progress.clamp(0, 100)}%',
                  style: TextStyle(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: task.progress <= 0 ? null : task.progress / 100,
                backgroundColor: colors.outlineVariant.withValues(alpha: 0.12),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _TaskFooter(
            retryLabel: l10n.tasksRetryProgress(
              task.retryCount,
              task.maxRetries,
            ),
            timeLabel: _formatTime(context, task.createdAt),
            retryAction: task.canRetry ? onRetry : null,
          ),
        ],
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime dateTime) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return l10n.tasksTimeJustNow;
    if (diff.inHours < 1) return l10n.tasksTimeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.tasksTimeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.tasksTimeDaysAgo(diff.inDays);
    return MaterialLocalizations.of(context).formatCompactDate(dateTime);
  }

  String _phaseLabel(AppLocalizations l10n, String? phase) {
    return switch (phase) {
      'PLANNING' => l10n.tasksPhasePlanning,
      'DELETING_OBJECTS' => l10n.tasksPhaseDeletingObjects,
      'VERIFYING_REFERENCES' => l10n.tasksPhaseVerifyingReferences,
      'FINALIZING_DATABASE' => l10n.tasksPhaseFinalizingDatabase,
      _ => l10n.tasksPhaseWaiting,
    };
  }
}

class _TaskFooter extends StatelessWidget {
  const _TaskFooter({
    required this.retryLabel,
    required this.timeLabel,
    this.retryAction,
  });

  final String retryLabel;
  final String timeLabel;
  final VoidCallback? retryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    final textStyle = TextStyle(
      fontSize: AppTypography.labelSmall,
      color: colors.onSurfaceVariant,
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compact = MediaQuery.sizeOf(context).width < 420 || textScale > 1.4;
    final retryButton =
        retryAction == null
            ? null
            : TextButton(
              onPressed: retryAction,
              child: Text(AppLocalizations.of(context).tasksRetry),
            );

    if (compact) {
      return Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(retryLabel, style: textStyle),
          Text(timeLabel, style: textStyle),
          if (retryButton != null) retryButton,
        ],
      );
    }
    return Row(
      children: [
        Text(retryLabel, style: textStyle),
        const Spacer(),
        Text(timeLabel, style: textStyle),
        if (retryButton != null) ...[const SizedBox(width: 8), retryButton],
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    final (icon, color) = switch (status) {
      'PENDING' ||
      'QUEUED' => (Icons.schedule_rounded, colors.onSurfaceVariant),
      'RETRY_WAIT' => (Icons.update_rounded, colors.warning),
      'RUNNING' => (Icons.sync_rounded, colors.info),
      'COMPLETED' => (Icons.check_circle_rounded, colors.success),
      'FAILED' || 'DLQ' => (Icons.error_rounded, colors.error),
      'CANCELLED' => (Icons.cancel_outlined, colors.onSurfaceVariant),
      _ => (Icons.help_outline_rounded, colors.onSurfaceVariant),
    };
    return Icon(icon, size: 20, color: color);
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.l10n});

  final String status;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    final (label, color) = switch (status) {
      'PENDING' ||
      'QUEUED' => (l10n.tasksStatusPending, colors.onSurfaceVariant),
      'RETRY_WAIT' => (l10n.tasksStatusRetryWait, colors.warning),
      'RUNNING' => (l10n.tasksStatusRunning, colors.info),
      'COMPLETED' => (l10n.tasksStatusCompleted, colors.success),
      'FAILED' => (l10n.tasksStatusFailed, colors.error),
      'DLQ' => (l10n.tasksStatusNeedsAttention, colors.error),
      'CANCELLED' => (l10n.tasksStatusCancelled, colors.onSurfaceVariant),
      _ => (status, colors.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
