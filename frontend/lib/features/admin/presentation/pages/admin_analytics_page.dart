import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';

part 'admin_analytics_charts.dart';

// ═══════════════════════════════════════════════════════════════════════
// 常量
// ═══════════════════════════════════════════════════════════════════════

const _kDayOptions = [7, 30, 90];

// ═══════════════════════════════════════════════════════════════════════
// 页面入口
// ═══════════════════════════════════════════════════════════════════════

class AdminAnalyticsPage extends ConsumerStatefulWidget {
  const AdminAnalyticsPage({required this.analytics, super.key});
  final AdminAnalytics analytics;

  @override
  ConsumerState<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends ConsumerState<AdminAnalyticsPage>
    with SingleTickerProviderStateMixin {
  int _days = 7;
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
    final async = ref.watch(adminAnalyticsProvider(_days));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fadeSlide(
          0,
          AdminPageHeader(
            title: l10n.adminAnalyticsPage,
            subtitle: l10n.adminAnalyticsPageSubtitle,
            trailing: _DaysSelector(
              selected: _days,
              onChanged: (d) => setState(() => _days = d),
            ),
          ),
        ),
        const SizedBox(height: 24),
        async.when(
          data: (a) => _fadeSlide(1, _Grid(analytics: a)),
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

  Widget _fadeSlide(int index, Widget child) {
    final start = index * 0.25;
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

// ── 时间选择器 ─────────────────────────────────────────────────────────

class _DaysSelector extends StatelessWidget {
  const _DaysSelector({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedButton<int>(
      segments: [
        for (final days in _kDayOptions)
          ButtonSegment<int>(
            value: days,
            label: Text(l10n.adminAnalyticsDays(days)),
          ),
      ],
      selected: <int>{selected},
      showSelectedIcon: false,
      onSelectionChanged: (values) => onChanged(values.first),
    );
  }
}

// ── 自适应网格 ─────────────────────────────────────────────────────────

class _Grid extends StatelessWidget {
  const _Grid({required this.analytics});
  final AdminAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final w = wide ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: w,
              child: _UserGrowthPanel(data: analytics.userGrowth),
            ),
            SizedBox(
              width: w,
              child: _TaskPanel(data: analytics.taskThroughput),
            ),
            SizedBox(
              width: w,
              child: _StoragePanel(data: analytics.storageGrowth),
            ),
            SizedBox(width: w, child: _LoadPanel(load: analytics.currentLoad)),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 共享组件
// ═══════════════════════════════════════════════════════════════════════

const double _kChartHeight = 240;

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.footer,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? footer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return Semantics(
      label: '$title: $subtitle',
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.outlineVariant.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: c.onSurface,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: c.onSurfaceVariant,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
              child: SizedBox(height: _kChartHeight, child: child),
            ),
            if (footer != null) footer!,
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});
  final List<({Color color, String label})> items;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  style: TextStyle(fontSize: 9, color: c.onSurfaceVariant),
                ),
              ],
            ),
            if (i < items.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: message,
            child: Icon(
              icon,
              size: 22,
              color: c.onSurfaceVariant.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(fontSize: 10, color: c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// fl_chart 工具
// ═══════════════════════════════════════════════════════════════════════

class _UserGrowthPanel extends StatelessWidget {
  const _UserGrowthPanel({required this.data});
  final List<DailyMetric> data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    final total = data.fold<int>(0, (s, d) => s + d.value);
    return _Card(
      title: l10n.adminAccountGrowth,
      subtitle: l10n.adminAnalyticsPageSubtitle,
      trailing: _Pill(text: '+$total', color: c.primary),
      child:
          data.isEmpty
              ? _Empty(
                icon: Icons.show_chart_rounded,
                message: l10n.adminNoTrendData,
              )
              : CurveChart(data: data, color: c.primary),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 任务吞吐（堆叠柱状图）
// ═══════════════════════════════════════════════════════════════════════

class _TaskPanel extends StatelessWidget {
  const _TaskPanel({required this.data});
  final List<DailyTaskMetric> data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    final done = data.fold<int>(0, (s, d) => s + d.completed);
    final err = data.fold<int>(0, (s, d) => s + d.failed);
    return _Card(
      title: l10n.adminTaskThroughput,
      subtitle:
          '${l10n.adminCompletedLabel} $done · ${l10n.adminExceptions} $err',
      trailing: _Pill(text: done.toString(), color: c.primary),
      footer: _Legend(
        items: [
          (color: c.primary, label: l10n.adminCompleted),
          (color: c.error, label: l10n.adminExceptions),
          (color: c.tertiary, label: l10n.adminRunningTasks),
        ],
      ),
      child:
          data.isEmpty
              ? _Empty(
                icon: Icons.bar_chart_rounded,
                message: l10n.adminNoTrendData,
              )
              : _TaskBarChart(data: data),
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
    return _Card(
      title: l10n.adminStorageOccupancy,
      subtitle: formatFileSize(bytes),
      trailing: _Pill(text: formatFileSize(bytes), color: c.info),
      child:
          data.isEmpty
              ? _Empty(
                icon: Icons.storage_rounded,
                message: l10n.adminNoTrendData,
              )
              : StepChart(data: data, color: c.info),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 系统负载（同心环仪表盘）
// ═══════════════════════════════════════════════════════════════════════

class _LoadPanel extends StatelessWidget {
  const _LoadPanel({required this.load});
  final SystemLoadSnapshot load;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.adminColors;
    return _Card(
      title: l10n.adminSystemLoad,
      subtitle: l10n.adminRealtime,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: c.success, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            l10n.adminAnalyticsLive,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c.success,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
      child: _SystemLoadBars(load: load),
    );
  }
}

/// 4 层同心环仪表盘。
