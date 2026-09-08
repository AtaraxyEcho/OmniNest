import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';
import 'package:omninest/features/admin/presentation/pages/admin_analytics_page.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';

/// 管理控制台概览页面 — 指标卡片 + 活动趋势 + 健康状态。
class AdminOverviewPage extends StatefulWidget {
  const AdminOverviewPage({required this.summary, super.key});

  final AdminConsoleSummary summary;

  @override
  State<AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends State<AdminOverviewPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(duration: MotionToken.stagger, vsync: this)
      ..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fadeSlide(
          0,
          AdminPageHeader(
            title: l10n.adminConsole,
            subtitle: l10n.adminConsoleSubtitle,
            trailing: AdminStatusPill(
              label: l10n.adminRunning,
              color: adminColors.success,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _fadeSlide(1, _MetricCards(summary: widget.summary)),
        const SizedBox(height: 24),
        _fadeSlide(2, _ActivityAndHealth(summary: widget.summary)),
      ],
    );
  }

  Widget _fadeSlide(int index, Widget child) {
    final start = index * 0.2;
    final end = (start + 0.6).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: MotionToken.curve),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: MotionToken.slideContent,
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}

// ── 指标卡片网格 ──────────────────────────────────────────────────────

class _MetricCards extends StatelessWidget {
  const _MetricCards({required this.summary});

  final AdminConsoleSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 1180
                ? 4
                : constraints.maxWidth >= 720
                ? 2
                : 1;
        final permissionBindings = summary.roles.fold<int>(
          0,
          (total, role) => total + role.permissionCount,
        );
        final activeRatio = _ratio(summary.users.active, summary.users.total);
        final taskIssueCount =
            summary.tasks.failed + summary.tasks.cancelled + summary.tasks.dlq;
        final taskDoneRatio = _ratio(
          summary.tasks.completed,
          summary.tasks.total,
        );
        final healthWarnCount =
            summary.health.where((item) => item.status != 'UP').length;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio:
              columns == 1
                  ? 1.38
                  : columns == 4
                  ? 1.35
                  : 1.72,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            AdminMetricCard(
              title: l10n.adminAccountOverview,
              value: summary.users.total.toString(),
              detail:
                  '${l10n.adminActive} ${summary.users.active} · ${l10n.adminStatusDisabled} ${summary.users.disabled}',
              icon: Icons.group_outlined,
              progress: activeRatio,
              supporting: [
                AdminMetricMiniStat(
                  label: l10n.adminRoleSuperAdmin,
                  value:
                      summary.users.roleCount(AdminRoles.superAdmin).toString(),
                  color: context.adminColors.tertiary,
                ),
                AdminMetricMiniStat(
                  label: l10n.adminRoleAdmin,
                  value: summary.users.roleCount(AdminRoles.admin).toString(),
                  color: adminColors.info,
                ),
              ],
            ),
            AdminMetricCard(
              title: l10n.adminPermissionModel,
              value: summary.roles.length.toString(),
              detail: l10n.adminPermissionBindingsCount('$permissionBindings'),
              icon: Icons.admin_panel_settings_outlined,
              accent: adminColors.info,
              progress: _ratio(
                summary.roles.where((role) => role.enabled).length,
                summary.roles.length,
              ),
              supporting:
                  summary.roles.take(3).map((role) {
                    return AdminMetricMiniStat(
                      label: role.name,
                      value: role.permissionCount.toString(),
                      color:
                          role.builtIn
                              ? context.adminColors.primary
                              : context.adminColors.tertiary,
                    );
                  }).toList(),
            ),
            AdminMetricCard(
              title: l10n.adminTasks,
              value: summary.tasks.total.toString(),
              detail:
                  '${l10n.adminRunningLabel} ${summary.tasks.running} · ${l10n.adminQueued} ${summary.tasks.queued}',
              icon: Icons.pending_actions_outlined,
              accent: context.adminColors.primary,
              progress: taskDoneRatio,
              supporting: [
                AdminMetricMiniStat(
                  label: l10n.adminCompleted,
                  value: summary.tasks.completed.toString(),
                  color: adminColors.success,
                ),
                AdminMetricMiniStat(
                  label: l10n.adminNeedAttention,
                  value: taskIssueCount.toString(),
                  color:
                      taskIssueCount == 0
                          ? context.adminColors.onSurfaceVariant
                          : context.adminColors.error,
                ),
              ],
            ),
            AdminMetricCard(
              title: l10n.adminStorageAssets,
              value: formatFileSize(summary.storage.usedBytes),
              detail: l10n.adminFilesFolders(
                '${summary.storage.fileCount}',
                '${summary.storage.folderCount}',
              ),
              icon: Icons.storage_outlined,
              accent: adminColors.success,
              progress: _ratio(
                summary.storage.objectCount,
                summary.storage.objectCount + summary.storage.fileCount,
              ),
              supporting: [
                AdminMetricMiniStat(
                  label: l10n.adminObjects,
                  value: summary.storage.objectCount.toString(),
                  color: adminColors.info,
                ),
                AdminMetricMiniStat(
                  label:
                      healthWarnCount == 0
                          ? l10n.adminHealthy
                          : l10n.adminWarning,
                  value: healthWarnCount.toString(),
                  color:
                      healthWarnCount == 0
                          ? adminColors.success
                          : context.adminColors.error,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ── 活动趋势 + 健康状态 ──────────────────────────────────────────────

class _ActivityAndHealth extends ConsumerWidget {
  const _ActivityAndHealth({required this.summary});

  final AdminConsoleSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    final analyticsAsync = ref.watch(adminAnalyticsProvider(7));
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1080;
        final activity = AdminInfoPanel(
          title: l10n.adminActivityChart,
          subtitle: l10n.adminActivityChartSubtitle,
          trailing: AdminStatusPill(
            label: l10n.adminOverviewTasksTotal(summary.tasks.total),
          ),
          children: [
            SizedBox(
              height: 260,
              child: analyticsAsync.when(
                data: (analytics) {
                  if (analytics.userGrowth.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.adminNoTrendData,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.adminColors.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return _OverviewAreaChart(data: analytics.userGrowth);
                },
                loading:
                    () => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                error:
                    (_, _) => Center(
                      child: Text(
                        l10n.adminNoTrendData,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.adminColors.onSurfaceVariant,
                        ),
                      ),
                    ),
              ),
            ),
            const SizedBox(height: 20),
            _ActivityLegend(),
          ],
        );
        final health = AdminInfoPanel(
          title: l10n.adminHealthStatus,
          subtitle: l10n.adminHealthStatusSubtitle,
          children: [
            for (final item in summary.health) ...[
              _HealthLine(
                name: item.name,
                detail: item.detail,
                color: _healthColor(item.status, adminColors),
              ),
              const SizedBox(height: 14),
            ],
          ],
        );

        if (!isWide) {
          return Column(
            children: [activity, const SizedBox(height: 24), health],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: activity),
            const SizedBox(width: 24),
            Expanded(flex: 4, child: health),
          ],
        );
      },
    );
  }
}

// ── 概览页曲线图（复用 CurveChart） ─────────────────────────────────

class _OverviewAreaChart extends StatelessWidget {
  const _OverviewAreaChart({required this.data});

  final List<DailyMetric> data;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return CurveChart(data: data, color: c.primary);
  }
}

// ── 辅助组件 ──────────────────────────────────────────────────────────

class _ActivityLegend extends StatelessWidget {
  const _ActivityLegend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [AdminStatusPill(label: l10n.adminUserLabel)],
    );
  }
}

class _HealthLine extends StatelessWidget {
  const _HealthLine({
    required this.name,
    required this.detail,
    required this.color,
  });

  final String name;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 3),
              Text(
                detail,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: context.adminColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

double _ratio(int value, int total) {
  if (total <= 0) return 0;
  return (value / total).clamp(0, 1).toDouble();
}

Color _healthColor(String status, AdminColors adminColors) {
  return switch (status) {
    'UP' => adminColors.success,
    'WARN' => adminColors.tertiary,
    _ => adminColors.error,
  };
}
