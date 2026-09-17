import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/admin/domain/admin_console_access.dart';

class TaskStatusWidget extends ConsumerWidget {
  const TaskStatusWidget({
    required this.running,
    required this.queued,
    required this.failed,
    super.key,
  });
  final int running;
  final int queued;
  final int failed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canAccessAdmin = ref.watch(canAccessAdminConsoleProvider);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canAccessAdmin ? () => context.go('/admin') : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.portalAdmin, style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 12),
              _StatusLine(
                label: l10n.portalTaskRunning,
                count: running,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 4),
              _StatusLine(
                label: l10n.portalTaskQueued,
                count: queued,
                color: colorScheme.tertiary,
              ),
              const SizedBox(height: 4),
              _StatusLine(
                label: l10n.portalTaskFailed,
                count: failed,
                color:
                    failed > 0
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodySmall),
        const Spacer(),
        Text(
          '$count',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
