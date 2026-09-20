import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';

part 'admin_analytics_charts.dart';

/// 可视化图表页面 — 时间范围选择 + 四面板（用户/任务/存储/负载）。
///
/// 四面板内容区统一 [_analyticsPanelBodyHeight]，保证双列等高对齐。
const double _analyticsPanelBodyHeight = 260;

class AdminAnalyticsPage extends ConsumerStatefulWidget {
  const AdminAnalyticsPage({required this.analytics, super.key});
  final AdminAnalytics analytics;

  @override
  ConsumerState<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends ConsumerState<AdminAnalyticsPage> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(adminAnalyticsProvider(_days));
    return AdminSectionEntrance(
      children: [
        AdminPageHeader(
          title: l10n.adminAnalyticsPage,
          subtitle: l10n.adminAnalyticsPageSubtitle,
          trailing: AdminTimeRangeSelector(
            selected: _days,
            onChanged: (d) => setState(() => _days = d),
          ),
        ),
        const SizedBox(height: 24),
        async.when(
          data: (a) => _AnalyticsGrid(analytics: a),
          loading:
              () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
          error:
              (e, _) => Padding(
                padding: const EdgeInsets.all(48),
                child: Center(child: Text(l10n.adminLoadFailed('$e'))),
              ),
        ),
      ],
    );
  }
}

/// 自适应双列网格。
class _AnalyticsGrid extends StatelessWidget {
  const _AnalyticsGrid({required this.analytics});
  final AdminAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (!wide) {
          return Column(
            children: [
              _UserGrowthPanel(data: analytics.userGrowth),
              const SizedBox(height: 16),
              _TaskPanel(data: analytics.taskThroughput),
              const SizedBox(height: 16),
              _StoragePanel(data: analytics.storageGrowth),
              const SizedBox(height: 16),
              _LoadPanel(load: analytics.currentLoad),
            ],
          );
        }
        // 双列：内容区固定等高，避免 IntrinsicHeight 与视口/图表 intrinsic 冲突。
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _UserGrowthPanel(data: analytics.userGrowth)),
                const SizedBox(width: 16),
                Expanded(child: _TaskPanel(data: analytics.taskThroughput)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _StoragePanel(data: analytics.storageGrowth)),
                const SizedBox(width: 16),
                Expanded(child: _LoadPanel(load: analytics.currentLoad)),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ── 面板实现 ───────────────────────────────────────────────────────────

class _UserGrowthPanel extends StatelessWidget {
  const _UserGrowthPanel({required this.data});
  final List<DailyMetric> data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    final total = data.fold<int>(0, (s, d) => s + d.value);
    return AdminInfoPanel(
      title: l10n.adminAccountGrowth,
      subtitle: l10n.adminAnalyticsPageSubtitle,
      trailing: AdminStatusPill(label: '+$total', color: c.primary),
      children: [
        SizedBox(
          height: _analyticsPanelBodyHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child:
                    data.isEmpty
                        ? _ChartEmpty(
                          icon: Icons.show_chart_rounded,
                          message: l10n.adminNoTrendData,
                        )
                        : CurveChart(data: data, color: c.primary),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskPanel extends StatelessWidget {
  const _TaskPanel({required this.data});
  final List<DailyTaskMetric> data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    final done = data.fold<int>(0, (s, d) => s + d.completed);
    final err = data.fold<int>(0, (s, d) => s + d.failed);
    return AdminInfoPanel(
      title: l10n.adminTaskThroughput,
      subtitle:
          '${l10n.adminCompletedLabel} $done · ${l10n.adminExceptions} $err',
      trailing: AdminStatusPill(label: done.toString(), color: c.primary),
      children: [
        SizedBox(
          height: _analyticsPanelBodyHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child:
                    data.isEmpty
                        ? _ChartEmpty(
                          icon: Icons.bar_chart_rounded,
                          message: l10n.adminNoTrendData,
                        )
                        : TaskThroughputChart(data: data),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 20,
                child: _ChartLegend(
                  items: [
                    (color: c.primary, label: l10n.adminCompleted),
                    (color: c.error, label: l10n.adminExceptions),
                    (color: c.tertiary, label: l10n.adminRunningTasks),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StoragePanel extends StatelessWidget {
  const _StoragePanel({required this.data});
  final List<DailyMetric> data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    final bytes = data.isEmpty ? 0 : data.last.value;
    return AdminInfoPanel(
      title: l10n.adminStorageOccupancy,
      subtitle: formatFileSize(bytes),
      trailing: AdminStatusPill(label: formatFileSize(bytes), color: c.info),
      children: [
        SizedBox(
          height: _analyticsPanelBodyHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child:
                    data.isEmpty
                        ? _ChartEmpty(
                          icon: Icons.storage_rounded,
                          message: l10n.adminNoTrendData,
                        )
                        : StepChart(data: data, color: c.info),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadPanel extends StatelessWidget {
  const _LoadPanel({required this.load});
  final SystemLoadSnapshot load;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    return AdminInfoPanel(
      title: l10n.adminSystemLoad,
      subtitle: l10n.adminRealtime,
      trailing: AdminStatusPill(
        label: l10n.adminAnalyticsLive,
        color: c.success,
      ),
      children: [
        SizedBox(
          height: _analyticsPanelBodyHeight,
          child: Center(
            child: AdminGaugeGrid(
              gaugeSize: 100,
              children: [
                AdminGaugeRing(
                  label: l10n.adminLoadCpu,
                  value: load.cpuUsage,
                  detail: '',
                  size: 100,
                ),
                AdminGaugeRing(
                  label: l10n.adminLoadMemory,
                  value: load.memoryUsage,
                  detail: '',
                  size: 100,
                ),
                AdminGaugeRing(
                  label: l10n.adminLoadDisk,
                  value: load.diskUsage,
                  detail: '',
                  size: 100,
                ),
                AdminGaugeRing(
                  label: l10n.adminLoadJvm,
                  value: load.jvmHeapUsage,
                  detail: '',
                  size: 100,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── 图表辅助 ───────────────────────────────────────────────────────────

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 22,
            color: c.onSurfaceVariant.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              fontSize: AppTypography.labelSmall,
              color: c.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.items});
  final List<({Color color, String label})> items;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: items[i].color,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            items[i].label,
            style: TextStyle(
              fontSize: AppTypography.labelSmall,
              color: c.onSurfaceVariant,
            ),
          ),
          if (i < items.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}
