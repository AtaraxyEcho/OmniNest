import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';

class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontSize: AppTypography.headlineMedium,
                height: 36 / 28,
                color: c.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: AppTypography.bodyLarge,
                height: 21 / 14,
                color: c.onSurfaceVariant,
              ),
            ),
          ],
        );

        if (!isWide || trailing == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              if (trailing != null) ...[const SizedBox(height: 18), trailing!],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 24),
            trailing!,
          ],
        );
      },
    );
  }
}

class AdminMetricCard extends StatelessWidget {
  const AdminMetricCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    this.accent,
    this.progress,
    this.supporting = const [],
    this.footer,
    super.key,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final Color? accent;
  final double? progress;
  final List<Widget> supporting;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final resolvedAccent = accent ?? c.primary;
    return WorkbenchPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: AppTypography.bodySmall,
                  height: 16 / 12,
                  color: c.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Icon(icon, color: resolvedAccent),
            ],
          ),
          if (supporting.isEmpty && progress == null && footer == null)
            const Spacer()
          else
            const SizedBox(height: 14),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontSize: AppTypography.headlineMedium,
              height: 34 / 28,
              color: resolvedAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: AppTypography.bodySmall,
              height: 16 / 12,
              color: c.onSurfaceVariant,
            ),
          ),
          if (supporting.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: supporting),
          ],
          if (progress != null) ...[
            const Spacer(),
            _MetricProgress(value: progress!, color: resolvedAccent),
          ],
          if (footer != null) ...[const SizedBox(height: 10), footer!],
        ],
      ),
    );
  }
}

class AdminMetricMiniStat extends StatelessWidget {
  const AdminMetricMiniStat({
    required this.label,
    required this.value,
    this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? context.adminColors.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: resolvedColor.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: AppTypography.labelSmall,
              height: 14 / 11,
              color: context.adminColors.onSurfaceVariant,
            ),
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  color: resolvedColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(text: ' $label'),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricProgress extends StatelessWidget {
  const _MetricProgress({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0, 1).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.adminColors.surfaceContainerHighest.withValues(
                alpha: 0.42,
              ),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: safeValue,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: color),
                  child: const SizedBox(height: 6),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AdminStatusPill extends StatelessWidget {
  const AdminStatusPill({required this.label, this.color, super.key});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? context.adminColors.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: resolvedColor.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: resolvedColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: AppTypography.labelSmall,
                height: 14 / 11,
                color: resolvedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminInfoPanel extends StatelessWidget {
  const AdminInfoPanel({
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return WorkbenchPanel(
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
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: AppTypography.titleLarge,
                        height: 28 / 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: AppTypography.bodyMedium,
                        height: 20 / 13,
                        color: context.adminColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 16), trailing!],
            ],
          ),
          const SizedBox(height: 22),
          ...children,
        ],
      ),
    );
  }
}

class AdminEmptyFeature extends StatelessWidget {
  const AdminEmptyFeature({
    required this.icon,
    required this.title,
    required this.description,
    this.actions = const [],
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return WorkbenchPanel(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: c.primary, size: 30),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: AppTypography.titleLarge,
                  height: 28 / 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: AppTypography.bodyLarge,
                  height: 21 / 14,
                  color: c.onSurfaceVariant,
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 22),
                Wrap(spacing: 10, runSpacing: 10, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AdminPaginationBar extends StatelessWidget {
  const AdminPaginationBar({
    required this.page,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final AdminPage<Object?> page;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totalPages = page.totalPages == 0 ? 1 : page.totalPages;
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          l10n.adminPageIndicator(page.page + 1, totalPages),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.adminColors.onSurfaceVariant,
          ),
        ),
        Text(
          l10n.adminTotalCount('${page.totalElements}'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.adminColors.onSurfaceVariant,
          ),
        ),
        IconButton(
          tooltip: l10n.adminPreviousPage,
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: l10n.adminNextPage,
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}
