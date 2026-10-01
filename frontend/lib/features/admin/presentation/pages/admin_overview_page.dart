import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_trend_charts.dart';

/// 管理控制台概览页 — 三行式仪表盘（依 01_overview_dashboard 样板）：
/// 1. KPI 行：账号 / 任务吞吐 / 存储资产 / 系统负载四张紧凑指标卡
/// 2. 趋势行：任务吞吐柱状图 + 用户与存储增长细线折线（1:1 等宽分栏）
/// 3. 运维行：服务健康通栏表（等宽三列）
///
/// 概览不再拉取 /admin/monitoring 审计流；审计统一由日志中心承载。
class AdminOverviewPage extends ConsumerWidget {
  const AdminOverviewPage({required this.summary, super.key});

  final AdminConsoleSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    // value：定时刷新失效重建期间保留上一份数据，不闪空趋势图。
    final analytics = ref.watch(adminAnalyticsProvider(7)).value;
    // 挂载期间保活定时刷新轮询器；页面卸载即停。
    ref.watch(adminOverviewPollerProvider);

    return AdminSectionEntrance(
      children: [
        AdminPageHeader(
          title: l10n.adminConsole,
          subtitle: l10n.adminConsoleSubtitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AdminStatusPill(
                label: l10n.adminRunning,
                color: adminColors.success,
              ),
              const SizedBox(width: 12),
              _OverviewRefreshControl(
                interval: ref.watch(adminOverviewRefreshIntervalProvider),
                onIntervalSelected:
                    (value) => ref
                        .read(adminOverviewRefreshIntervalProvider.notifier)
                        .selectInterval(value),
                onRefreshNow: () {
                  ref.invalidate(adminConsoleControllerProvider);
                  ref.invalidate(adminAnalyticsProvider(7));
                },
              ),
            ],
          ),
        ),
        // 样板主区 space-y-6：区块间距 24。
        const SizedBox(height: 24),
        _OverviewMetricCards(summary: summary, analytics: analytics),
        const SizedBox(height: 24),
        _OverviewTrendRow(analytics: analytics),
        const SizedBox(height: 24),
        _HealthPanel(summary: summary),
      ],
    );
  }
}

// ── Bento 指标卡网格 ─────────────────────────────────────────────────

/// 页头刷新控制：自动刷新档位分段（关闭 / 30秒 / 5分钟）+ 手动刷新按钮。
/// 默认关闭；选择档位后由 [adminOverviewPollerProvider] 定时失效概览数据。
class _OverviewRefreshControl extends StatelessWidget {
  const _OverviewRefreshControl({
    required this.interval,
    required this.onIntervalSelected,
    required this.onRefreshNow,
  });

  final AdminOverviewRefreshInterval interval;

  final ValueChanged<AdminOverviewRefreshInterval> onIntervalSelected;

  final VoidCallback onRefreshNow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: l10n.adminOverviewAutoRefresh,
          child: WorkstationSegmented<AdminOverviewRefreshInterval>(
            selected: interval,
            onSelected: onIntervalSelected,
            segments: [
              WorkstationSegment(
                value: AdminOverviewRefreshInterval.off,
                tooltip: l10n.adminOverviewRefreshOff,
                icon: Icons.timer_off_outlined,
                label: l10n.adminOverviewRefreshOff,
              ),
              WorkstationSegment(
                value: AdminOverviewRefreshInterval.thirtySeconds,
                tooltip: l10n.adminOverviewRefresh30s,
                icon: Icons.timer_outlined,
                label: l10n.adminOverviewRefresh30s,
              ),
              WorkstationSegment(
                value: AdminOverviewRefreshInterval.fiveMinutes,
                tooltip: l10n.adminOverviewRefresh5m,
                icon: Icons.schedule_outlined,
                label: l10n.adminOverviewRefresh5m,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        WorkstationIconButton(
          tooltip: l10n.adminRefresh,
          icon: Icons.refresh_rounded,
          onPressed: onRefreshNow,
        ),
      ],
    );
  }
}

class _OverviewMetricCards extends StatelessWidget {
  const _OverviewMetricCards({required this.summary, this.analytics});

  final AdminConsoleSummary summary;
  final AdminAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    final userValues =
        analytics?.userGrowth.map((d) => d.value.toDouble()).toList();
    final throughputData =
        analytics?.taskThroughput ?? const <DailyTaskMetric>[];
    // 近 7 日吞吐总量 = 每日 completed+failed+running 之和；无数据回退任务总数。
    final throughputTotal = throughputData.fold<int>(
      0,
      (sum, d) => sum + d.completed + d.failed + d.running,
    );
    final taskValues =
        throughputData
            .map((d) => (d.completed + d.failed + d.running).toDouble())
            .toList();
    final storageValues =
        analytics?.storageGrowth.map((d) => d.value.toDouble()).toList();
    final load = analytics?.currentLoad;
    final taskIssueCount =
        summary.tasks.failed + summary.tasks.cancelled + summary.tasks.dlq;
    final userBadge = _trendBadge(userValues);
    final taskBadge = _trendBadge(taskValues);
    final storageBadge = _trendBadge(storageValues);

    return AdminResponsiveMetricGrid(
      children: [
        AdminMetricCard(
          title: l10n.adminAccountOverview,
          value: summary.users.total.toString(),
          detail:
              '${l10n.adminActive} ${summary.users.active} · ${l10n.adminStatusDisabled} ${summary.users.disabled}',
          icon: Icons.group_outlined,
          supporting: [
            AdminMetricMiniStat(
              label: l10n.adminRoleSuperAdmin,
              value: summary.users.roleCount(AdminRoles.superAdmin).toString(),
            ),
            AdminMetricMiniStat(
              label: l10n.adminRoleAdmin,
              value: summary.users.roleCount(AdminRoles.admin).toString(),
            ),
            // 涨跌徽标并入 supporting 单行，替代独立 footer 行以维持紧凑高度。
            if (userBadge != null) userBadge,
          ],
        ),
        AdminMetricCard(
          title: l10n.adminTaskThroughput7d,
          value:
              throughputData.isEmpty
                  ? summary.tasks.total.toString()
                  : throughputTotal.toString(),
          detail:
              '${l10n.adminRunningLabel} ${summary.tasks.running} · ${l10n.adminQueued} ${summary.tasks.queued}',
          icon: Icons.task_alt_outlined,
          supporting: [
            AdminMetricMiniStat(
              label: l10n.adminCompleted,
              value: summary.tasks.completed.toString(),
              color: c.success,
            ),
            AdminMetricMiniStat(
              label: l10n.adminNeedAttention,
              value: taskIssueCount.toString(),
              color: taskIssueCount == 0 ? null : c.error,
            ),
            if (taskBadge != null) taskBadge,
          ],
        ),
        AdminMetricCard(
          title: l10n.adminStorageAssets,
          value: formatFileSize(summary.storage.usedBytes),
          detail: l10n.adminFilesFoldersObjects(
            '${summary.storage.fileCount}',
            '${summary.storage.folderCount}',
            '${summary.storage.objectCount}',
          ),
          icon: Icons.storage_outlined,
          supporting: [if (storageBadge != null) storageBadge],
        ),
        AdminMetricCard(
          title: l10n.adminSystemLoad,
          value:
              load == null ? '—' : 'CPU ${load.cpuUsage.toStringAsFixed(0)}%',
          detail: load == null ? '—' : _loadStateLabel(l10n, load.cpuUsage),
          icon: Icons.memory_outlined,
          accent: load == null ? null : _loadThreshold(c, load.cpuUsage),
          progress: load == null ? null : (load.cpuUsage / 100).clamp(0.0, 1.0),
          supporting:
              load == null
                  ? const <Widget>[]
                  : [
                    AdminMetricMiniStat(
                      label: l10n.adminLoadMemory,
                      value: '${load.memoryUsage.toStringAsFixed(0)}%',
                      color: _loadThreshold(c, load.memoryUsage),
                    ),
                    AdminMetricMiniStat(
                      label: l10n.adminLoadDisk,
                      value: '${load.diskUsage.toStringAsFixed(0)}%',
                      color: _loadThreshold(c, load.diskUsage),
                    ),
                    AdminMetricMiniStat(
                      label: l10n.adminLoadJvm,
                      value: '${load.jvmHeapUsage.toStringAsFixed(0)}%',
                      color: _loadThreshold(c, load.jvmHeapUsage),
                    ),
                  ],
        ),
      ],
    );
  }

  /// 末两点对比的涨跌徽标；序列不足两点时返回 null。
  Widget? _trendBadge(List<double>? values) {
    if (values == null || values.length < 2) {
      return null;
    }
    return AdminTrendBadge(
      current: values.last,
      previous: values[values.length - 2],
    );
  }
}

/// 负载阈值示警色：≥85 绯红、≥70 琥珀、其余中性。
Color _loadThreshold(AdminColors c, double value) {
  if (value >= 85) {
    return c.error;
  }
  if (value >= 70) {
    return c.warning;
  }
  return c.onSurfaceVariant;
}

String _loadStateLabel(AppLocalizations l10n, double value) {
  if (value >= 85) {
    return l10n.adminLoadStateCritical;
  }
  if (value >= 70) {
    return l10n.adminLoadStateWarning;
  }
  return l10n.adminLoadStateNormal;
}

// ── 趋势行：吞吐柱状图 + 用户/存储增长折线 ─────────────────────────────

/// 趋势行宽屏统一高度，保证左右面板顶底对齐。
const double _overviewTrendRowHeight = 300;

/// 面板内边距与区块头分隔线取样板值：p-5=20、pb-4 border-b mb-4。
const EdgeInsets _overviewPanelPadding = EdgeInsets.all(20);

class _OverviewTrendRow extends StatelessWidget {
  const _OverviewTrendRow({required this.analytics});

  final AdminAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1080;
        final throughput = _OverviewThroughputPanel(analytics: analytics);
        final growth = _OverviewGrowthPanel(analytics: analytics);
        if (!isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: _overviewTrendRowHeight, child: throughput),
              const SizedBox(height: 16),
              SizedBox(height: _overviewTrendRowHeight, child: growth),
            ],
          );
        }
        // 样板 02_monitoring 中排为 1:1 等宽双卡（gap-4=16）。
        return SizedBox(
          height: _overviewTrendRowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: throughput),
              const SizedBox(width: 16),
              Expanded(child: growth),
            ],
          ),
        );
      },
    );
  }
}

DateTime _mondayOfThisWeek() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - (now.weekday - 1));
}

String _isoDate(DateTime day) {
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

/// 把滚动 7 日窗口重排为本历周：周一→周日，缺失与未来日补零点。
List<DailyTaskMetric> _calendarWeekSeries(List<DailyTaskMetric> raw) {
  if (raw.isEmpty) {
    return const <DailyTaskMetric>[];
  }
  final monday = _mondayOfThisWeek();
  final byDate = <String, DailyTaskMetric>{for (final d in raw) d.date: d};
  return [
    for (var i = 0; i < 7; i++)
      () {
        final day = monday.add(Duration(days: i));
        final hit = byDate[_isoDate(day)];
        return DailyTaskMetric(
          date: _isoDate(day),
          completed: hit?.completed ?? 0,
          failed: hit?.failed ?? 0,
          running: hit?.running ?? 0,
        );
      }(),
  ];
}

/// 任务吞吐趋势面板：本周（周一→周日）直角柱状图 + 等宽统计。
class _OverviewThroughputPanel extends StatelessWidget {
  const _OverviewThroughputPanel({required this.analytics});

  final AdminAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    final rawData = analytics?.taskThroughput ?? const <DailyTaskMetric>[];
    // X 轴固定为本历周（周一→周日）：缺失与未来日补零，不再随当天滚动前移。
    final data = _calendarWeekSeries(rawData);
    final weekLabels = MaterialLocalizations.of(context).narrowWeekdays;
    final monday = _mondayOfThisWeek();
    final tickLabels = [
      for (var i = 0; i < data.length; i++)
        weekLabels[monday.add(Duration(days: i)).weekday % 7],
    ];
    final completed = data.fold<int>(0, (sum, d) => sum + d.completed);
    final failed = data.fold<int>(0, (sum, d) => sum + d.failed);

    return AdminInfoPanel(
      title: l10n.adminOverviewThroughputTrend,
      subtitle: l10n.adminThroughputTrendSubtitle,
      padding: _overviewPanelPadding,
      headerDivider: true,
      expandBody: true,
      children: [
        Expanded(
          child:
              rawData.isEmpty
                  ? Center(child: _EmptyText(l10n.adminNoTrendData))
                  : AdminThroughputBarChart(
                    data: data,
                    tickLabels: tickLabels,
                    semanticsLabel: l10n.adminOverviewThroughputTrend,
                  ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            AdminChartLegend(color: c.onSurface, label: l10n.adminCompleted),
            const SizedBox(width: 12),
            AdminChartLegend(color: c.error, label: l10n.adminFailedCount),
            const Spacer(),
            Text(
              '$completed / $failed',
              style: TextStyle(
                fontFamily: AppTypography.monoFamily,
                fontFamilyFallback: AppTypography.monoFamilyFallback,
                fontSize: AppTypography.labelSmall,
                color: c.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 活动与存储增长面板：上用户增长、下存储增长两条细线折线。
class _OverviewGrowthPanel extends StatelessWidget {
  const _OverviewGrowthPanel({required this.analytics});

  final AdminAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final userPoints = (analytics?.userGrowth ?? const <DailyMetric>[])
        .map((d) => AdminChartPoint(date: d.date, value: d.value.toDouble()))
        .toList(growable: false);
    final storagePoints = (analytics?.storageGrowth ?? const <DailyMetric>[])
        .map((d) => AdminChartPoint(date: d.date, value: d.value.toDouble()))
        .toList(growable: false);

    return AdminInfoPanel(
      title: AppLocalizations.of(context).adminGrowthPanelTitle,
      subtitle: AppLocalizations.of(context).adminGrowthPanelSubtitle,
      padding: _overviewPanelPadding,
      headerDivider: true,
      expandBody: true,
      children: [
        Expanded(
          child: _GrowthSection(
            label: AppLocalizations.of(context).adminUserGrowthLabel,
            points: userPoints,
            valueLabel:
                userPoints.isEmpty
                    ? null
                    : userPoints.last.value.round().toString(),
            valueFormatter: (value) => value.round().toString(),
          ),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 12),
          color: scheme.outlineVariant,
        ),
        Expanded(
          child: _GrowthSection(
            label: AppLocalizations.of(context).adminStorageGrowthLabel,
            points: storagePoints,
            valueLabel:
                storagePoints.isEmpty
                    ? null
                    : formatFileSize(storagePoints.last.value.round()),
            valueFormatter: (value) => formatFileSize(value.round()),
          ),
        ),
      ],
    );
  }
}

/// 单条增长分区：标签 + 等宽当前值 + 细线折线；空数据展示空文案。
class _GrowthSection extends StatelessWidget {
  const _GrowthSection({
    required this.label,
    required this.points,
    required this.valueLabel,
    this.valueFormatter,
  });

  final String label;
  final List<AdminChartPoint> points;
  final String? valueLabel;

  /// 悬停浮牌数值格式化（存储增长传字节格式化，用户增长取整数）。
  final String Function(double value)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontSize: AppTypography.bodySmall,
                height: 16 / 12,
                color: c.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              valueLabel ?? '—',
              style: TextStyle(
                fontFamily: AppTypography.monoFamily,
                fontFamilyFallback: AppTypography.monoFamilyFallback,
                fontSize: AppTypography.labelSmall,
                color: c.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child:
              points.isEmpty
                  ? Center(child: _EmptyText(l10n.adminNoTrendData))
                  : AdminHairlineLineChart(
                    points: points,
                    valueFormatter: valueFormatter,
                    semanticsLabel: label,
                  ),
        ),
      ],
    );
  }
}

// ── 服务健康通栏表 ───────────────────────────────────────────────────

/// 表格单元格水平内边距（样板 px-3=12）。
const EdgeInsets _healthCellGutter = EdgeInsets.symmetric(horizontal: 12);

class _HealthPanel extends StatelessWidget {
  const _HealthPanel({required this.summary});

  final AdminConsoleSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final upCount = summary.health.where((h) => h.status == 'UP').length;
    return AdminInfoPanel(
      title: l10n.adminHealthStatus,
      subtitle: l10n.adminHealthStatusSubtitle,
      padding: _overviewPanelPadding,
      headerDivider: true,
      // 样板表头右侧 n/n Operational 等宽汇总（text-xs mono 弱化色）。
      trailing: Text(
        '$upCount / ${summary.health.length}',
        style: TextStyle(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: AppTypography.bodySmall,
          color: scheme.onSurfaceVariant,
        ),
      ),
      children: [
        _HealthHeaderRow(
          cells: [
            l10n.adminServiceColumn,
            l10n.adminStatusColumn,
            l10n.adminLatencyColumn,
          ],
        ),
        for (final item in summary.health)
          _HealthRow(name: item.name, status: item.status, detail: item.detail),
        if (summary.health.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _EmptyText(l10n.adminNoComponentHealth),
          ),
      ],
    );
  }
}

/// 健康表三列共享栅格：三列等宽，
/// 表头与数据行复用同一布局，杜绝列轴线漂移。
class _HealthColumnLayout extends StatelessWidget {
  const _HealthColumnLayout({
    required this.service,
    required this.status,
    required this.latency,
  });

  final Widget service;
  final Widget status;
  final Widget latency;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: service,
          ),
        ),
        Expanded(child: Padding(padding: _healthCellGutter, child: status)),
        Expanded(child: Padding(padding: _healthCellGutter, child: latency)),
      ],
    );
  }
}

class _HealthHeaderRow extends StatelessWidget {
  const _HealthHeaderRow({required this.cells});

  final List<String> cells;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: _HealthColumnLayout(
        service: _headerCell(context, cells[0]),
        status: _headerCell(context, cells[1]),
        latency: _headerCell(context, cells[2]),
      ),
    );
  }

  Widget _headerCell(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: AppTypography.monoFamily,
        fontFamilyFallback: AppTypography.monoFamilyFallback,
        fontSize: AppTypography.labelMicro,
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// 健康表数据行：行高按样板 py-3=12 + 16px 行盒（约 40），
/// 服务名等宽 w500、状态 AdminStatusTag、延迟等宽。
class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.name,
    required this.status,
    required this.detail,
  });

  final String name;
  final String status;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: _HealthColumnLayout(
        service: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTypography.monoFamily,
            fontFamilyFallback: AppTypography.monoFamilyFallback,
            fontSize: AppTypography.bodySmall,
            height: 16 / 12,
            color: scheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        status: Align(
          alignment: Alignment.centerLeft,
          child: AdminStatusTag(label: status, tone: _tagTone(status)),
        ),
        latency: Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTypography.monoFamily,
            fontFamilyFallback: AppTypography.monoFamilyFallback,
            fontSize: AppTypography.bodySmall,
            height: 16 / 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  AdminTagTone _tagTone(String status) {
    return switch (status) {
      'UP' => AdminTagTone.success,
      'WARN' => AdminTagTone.warning,
      _ => AdminTagTone.error,
    };
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
