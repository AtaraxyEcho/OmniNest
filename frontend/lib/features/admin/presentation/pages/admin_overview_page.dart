import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';
import 'package:omninest/features/admin/presentation/pages/admin_analytics_page.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';

/// 管理控制台概览页面 — sparkline 指标卡 + 趋势 + 服务健康网格。
class AdminOverviewPage extends ConsumerWidget {
  const AdminOverviewPage({required this.summary, super.key});

  final AdminConsoleSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    final analyticsAsync = ref.watch(adminAnalyticsProvider(7));
    final analytics = analyticsAsync.asData?.value;

    return AdminSectionEntrance(
      children: [
        AdminPageHeader(
          title: l10n.adminConsole,
          subtitle: l10n.adminConsoleSubtitle,
          trailing: AdminStatusPill(
            label: l10n.adminRunning,
            color: adminColors.success,
          ),
        ),
        const SizedBox(height: 24),
        _SparklineMetricCards(summary: summary, analytics: analytics),
        const SizedBox(height: 24),
        _TrendAndHealth(summary: summary, analytics: analytics),
      ],
    );
  }
}

// ── sparkline 指标卡网格 ──────────────────────────────────────────────

class _SparklineMetricCards extends StatelessWidget {
  const _SparklineMetricCards({required this.summary, this.analytics});

  final AdminConsoleSummary summary;
  final AdminAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    final userValues =
        analytics?.userGrowth.map((d) => d.value.toDouble()).toList();
    final taskValues =
        analytics?.taskThroughput
            .map((d) => (d.completed + d.failed + d.running).toDouble())
            .toList();
    final storageValues =
        analytics?.storageGrowth.map((d) => d.value.toDouble()).toList();
    final permissionBindings = summary.roles.fold<int>(
      0,
      (total, role) => total + role.permissionCount,
    );
    final taskIssueCount =
        summary.tasks.failed + summary.tasks.cancelled + summary.tasks.dlq;

    return AdminResponsiveMetricGrid(
      children: [
        // 用户
        _buildCard(
          context: context,
          title: l10n.adminAccountOverview,
          value: summary.users.total.toString(),
          detail:
              '${l10n.adminActive} ${summary.users.active} · ${l10n.adminStatusDisabled} ${summary.users.disabled}',
          icon: Icons.group_outlined,
          accent: c.tertiary,
          sparkline: userValues,
          sparklineColor: c.tertiary,
          trend: _trend(userValues),
          supporting: [
            AdminMetricMiniStat(
              label: l10n.adminRoleSuperAdmin,
              value: summary.users.roleCount(AdminRoles.superAdmin).toString(),
              color: c.tertiary,
            ),
            AdminMetricMiniStat(
              label: l10n.adminRoleAdmin,
              value: summary.users.roleCount(AdminRoles.admin).toString(),
              color: c.info,
            ),
          ],
        ),
        // 权限
        _buildCard(
          context: context,
          title: l10n.adminPermissionModel,
          value: summary.roles.length.toString(),
          detail: l10n.adminPermissionBindingsCount('$permissionBindings'),
          icon: Icons.admin_panel_settings_outlined,
          accent: c.info,
        ),
        // 任务
        _buildCard(
          context: context,
          title: l10n.adminTasks,
          value: summary.tasks.total.toString(),
          detail:
              '${l10n.adminRunningLabel} ${summary.tasks.running} · ${l10n.adminQueued} ${summary.tasks.queued}',
          icon: Icons.pending_actions_outlined,
          accent: c.primary,
          sparkline: taskValues,
          sparklineColor: c.primary,
          trend: _trend(taskValues),
          supporting: [
            AdminMetricMiniStat(
              label: l10n.adminCompleted,
              value: summary.tasks.completed.toString(),
              color: c.success,
            ),
            AdminMetricMiniStat(
              label: l10n.adminNeedAttention,
              value: taskIssueCount.toString(),
              color: taskIssueCount == 0 ? c.onSurfaceVariant : c.error,
            ),
          ],
        ),
        // 存储
        _buildCard(
          context: context,
          title: l10n.adminStorageAssets,
          value: formatFileSize(summary.storage.usedBytes),
          detail: l10n.adminFilesFolders(
            '${summary.storage.fileCount}',
            '${summary.storage.folderCount}',
          ),
          icon: Icons.storage_outlined,
          accent: c.success,
          sparkline: storageValues,
          sparklineColor: c.success,
          supporting: [
            AdminMetricMiniStat(
              label: l10n.adminObjects,
              value: summary.storage.objectCount.toString(),
              color: c.info,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required String title,
    required String value,
    required String detail,
    required IconData icon,
    required Color accent,
    List<double>? sparkline,
    Color? sparklineColor,
    Widget? trend,
    List<Widget> supporting = const [],
  }) {
    return WorkbenchPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行 1：图标 + 标题 + 趋势徽标
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: context.adminColors.onSurfaceVariant,
                  ),
                ),
              ),
              if (trend != null) ...[const SizedBox(width: 4), trend],
            ],
          ),
          const SizedBox(height: 10),
          // 行 2：大数值
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTypography.headlineMedium,
              fontWeight: FontWeight.w800,
              color: accent,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          // 行 3：明细
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTypography.labelSmall,
              color: context.adminColors.onSurfaceVariant.withValues(
                alpha: 0.70,
              ),
            ),
          ),
          // 行 4–5：sparkline + 徽标。Flexible(loose) 吃剩余高度，
          // 内部行高压缩，避免固定高度之和超过网格卡导致溢出。
          Flexible(
            fit: FlexFit.loose,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sparkline != null && sparkline.length >= 2)
                    SizedBox(
                      height: 32,
                      child: AdminSparkline(
                        values: sparkline,
                        color: sparklineColor ?? accent,
                        height: 32,
                      ),
                    )
                  else
                    const SizedBox(height: 32),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 24,
                    child:
                        supporting.isEmpty
                            ? const SizedBox.shrink()
                            : Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: supporting,
                              ),
                            ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  AdminTrendBadge? _trend(List<double>? values) {
    if (values == null || values.length < 2) return null;
    return AdminTrendBadge(
      current: values.last,
      previous: values[values.length - 2],
    );
  }
}

// ── 趋势图 + 服务健康网格 ─────────────────────────────────────────────

class _TrendAndHealth extends StatelessWidget {
  const _TrendAndHealth({required this.summary, this.analytics});

  final AdminConsoleSummary summary;
  final AdminAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1080;
        final trend = AdminInfoPanel(
          title: l10n.adminActivityChart,
          subtitle: l10n.adminActivityChartSubtitle,
          trailing: AdminStatusPill(
            label: l10n.adminOverviewTasksTotal(summary.tasks.total),
          ),
          children: [
            SizedBox(
              height: 240,
              child:
                  (analytics == null || analytics!.userGrowth.isEmpty)
                      ? Center(
                        child: Text(
                          l10n.adminNoTrendData,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: adminColors.onSurfaceVariant),
                        ),
                      )
                      : CurveChart(
                        data: analytics!.userGrowth,
                        color: adminColors.primary,
                      ),
            ),
          ],
        );
        final health = AdminInfoPanel(
          title: l10n.adminHealthStatus,
          subtitle: l10n.adminHealthStatusSubtitle,
          children: [
            LayoutBuilder(
              builder: (context, hc) {
                final columns = hc.maxWidth >= 420 ? 2 : 1;
                return GridView.count(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  // 固定 tile 高度，避免 detail 文案长短导致瓦片高度不齐。
                  mainAxisExtent: 72,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final item in summary.health)
                      AdminServiceTile(
                        name: item.name,
                        status: item.status,
                        detail: item.detail,
                      ),
                  ],
                );
              },
            ),
          ],
        );

        if (!isWide) {
          return Column(children: [trend, const SizedBox(height: 16), health]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: trend),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: health),
          ],
        );
      },
    );
  }
}
