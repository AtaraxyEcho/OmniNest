part of 'admin_operations_pages.dart';

class _PageEntrance extends StatefulWidget {
  const _PageEntrance({required this.children});

  final List<Widget> children;

  @override
  State<_PageEntrance> createState() => _PageEntranceState();
}

class _PageEntranceState extends State<_PageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: MotionToken.stagger, vsync: this)
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < widget.children.length; i++)
          _buildAnimated(i, widget.children[i]),
      ],
    );
  }

  Widget _buildAnimated(int index, Widget child) {
    final total = widget.children.length;
    final start = (index / total).clamp(0.0, 0.8);
    final end = (start + 0.5).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
      parent: _ctrl,
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

/// 中栏「趋势 + 组件健康」统一高度，保证左右面板顶底对齐。
const double _monitoringMidRowHeight = 420;

/// 监控页布局：
/// 1. 系统负载仪表 + 摘要指标
/// 2. 左趋势 / 右组件健康（等高）
/// 3. 最近告警（通栏；操作审计已在日志中心，此处不再重复）
class AdminMonitoringPage extends StatelessWidget {
  const AdminMonitoringPage({required this.view, super.key});

  final AdminMonitoringView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    final warnCount =
        view.components.where((item) => item.status != 'UP').length +
        view.alerts.where((item) => item.severity == 'WARNING').length;
    final overview = view.overview;
    return AdminSectionEntrance(
      children: [
        AdminPageHeader(
          title: l10n.adminSystemMonitoring,
          subtitle: l10n.adminMonitoringSubtitle,
          trailing: AdminStatusPill(
            label:
                overview.status == 'UP'
                    ? l10n.adminRunning
                    : l10n.adminAttentionItems('$warnCount'),
            // 颜色与标签同源：系统正常（UP）必须显示绿色，
            // 仅存在告警项时为琥珀，避免「运行正常」标签配红色指示的矛盾。
            color: _statusColor(overview.status, adminColors),
          ),
        ),
        const SizedBox(height: 20),
        // ── 1. 系统负载 ──
        AdminInfoPanel(
          title: l10n.adminSystemLoad,
          subtitle: l10n.adminUptime(overview.uptime),
          trailing: AdminStatusPill(
            label: overview.status,
            color: _statusColor(overview.status, adminColors),
          ),
          children: [
            AdminGaugeGrid(
              gaugeSize: 112,
              children: [
                AdminGaugeRing(
                  label: l10n.adminSystemCpu,
                  value: overview.cpuUsage,
                  detail: '',
                  size: 112,
                ),
                AdminGaugeRing(
                  label: l10n.adminLoadMemory,
                  value: overview.memoryUsage,
                  detail: '',
                  size: 112,
                ),
                AdminGaugeRing(
                  label: l10n.adminLoadDisk,
                  value: overview.diskUsage,
                  detail: '',
                  size: 112,
                ),
                AdminGaugeRing(
                  label: l10n.adminLoadJvm,
                  value: overview.jvmHeapUsage,
                  detail: '',
                  size: 112,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AdminMetricMiniStat(
                  label: l10n.adminComponents,
                  value: view.components.length.toString(),
                ),
                AdminMetricMiniStat(
                  label: l10n.adminAlerts,
                  value: view.alerts.length.toString(),
                  color: view.alerts.isEmpty ? null : adminColors.error,
                ),
                AdminMetricMiniStat(
                  label: l10n.adminRequests,
                  value: overview.todayRequests.toString(),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1080;
            final trend = _MonitoringTrendPanel(series: view.series);
            final components = AdminInfoPanel(
              title: l10n.adminComponentHealth,
              subtitle: l10n.adminComponentHealthSubtitle,
              expandBody: true,
              trailing: AdminStatusPill(
                label:
                    '${view.components.where((c) => c.status == 'UP').length}/${view.components.length}',
                color:
                    warnCount == 0 ? adminColors.success : adminColors.tertiary,
              ),
              children: [
                Expanded(
                  child: _BoundedMonitoringList(
                    maxHeight: double.infinity,
                    emptyMessage: l10n.adminNoComponentHealth,
                    children: [
                      for (final item in view.components)
                        _InfoRow(
                          leading: item.name,
                          middle: _detailText(item.detail, l10n),
                          trailing: AdminStatusPill(
                            label: item.status,
                            color: _statusColor(item.status, adminColors),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
            final alerts = AdminInfoPanel(
              title: l10n.adminRecentAlerts,
              subtitle: l10n.adminRecentAlertsSubtitle,
              trailing: AdminStatusPill(
                label: '${view.alerts.length}',
                color:
                    view.alerts.isEmpty
                        ? adminColors.success
                        : adminColors.error,
              ),
              children: [
                _BoundedMonitoringList(
                  maxHeight: 320,
                  emptyMessage: l10n.adminNoAlerts,
                  children: [
                    for (final alert in view.alerts.take(20))
                      _InfoRow(
                        leading: alert.severity,
                        middle: '${alert.message}\n${alert.timestamp}',
                        trailing: Icon(
                          alert.severity == 'WARNING'
                              ? Icons.warning_amber_rounded
                              : Icons.info_outline_rounded,
                          color:
                              alert.severity == 'WARNING'
                                  ? adminColors.error
                                  : adminColors.info,
                        ),
                      ),
                  ],
                ),
              ],
            );

            if (!isWide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  trend,
                  const SizedBox(height: 16),
                  SizedBox(height: _monitoringMidRowHeight, child: components),
                  const SizedBox(height: 16),
                  alerts,
                ],
              );
            }

            // 等高中栏：左趋势 / 右组件健康，底边对齐。
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _monitoringMidRowHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 7, child: trend),
                      const SizedBox(width: 16),
                      Expanded(flex: 5, child: components),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                alerts,
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MonitoringTrendPanel extends StatelessWidget {
  const _MonitoringTrendPanel({required this.series});

  final List<AdminMonitoringSeries> series;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdminInfoPanel(
      title: l10n.adminTrendCharts,
      subtitle: l10n.adminTrendChartsSubtitle,
      expandBody: true,
      trailing: AdminStatusPill(label: l10n.adminMonitoringStepMinutes(5)),
      children:
          series.isEmpty
              ? [
                Expanded(
                  child: Center(child: _EmptyText(l10n.adminNoTrendData)),
                ),
              ]
              : [
                Expanded(
                  child: _MonitoringTrendCards(
                    series: series,
                    maxCardHeight: _monitoringMidRowHeight - 120,
                  ),
                ),
              ],
    );
  }
}

class _MonitoringTrendCard extends StatefulWidget {
  const _MonitoringTrendCard({required this.series});

  final AdminMonitoringSeries series;

  @override
  State<_MonitoringTrendCard> createState() => _MonitoringTrendCardState();
}

class _MonitoringTrendCardState extends State<_MonitoringTrendCard> {
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final points = widget.series.points;
    final current = points.isEmpty ? 0.0 : points.last.value;
    final color = _seriesColor(widget.series.metric, c);
    final displayValue =
        _hoverIndex != null && _hoverIndex! < points.length
            ? points[_hoverIndex!].value
            : current;
    final displayTimestamp =
        points.isEmpty
            ? ''
            : _shortMonitoringTimestamp(
              points[_hoverIndex ?? (points.length - 1)].timestamp,
            );

    return MouseRegion(
      onExit: (_) => setState(() => _hoverIndex = null),
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.outlineVariant.withValues(alpha: 0.18)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.series.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w600,
                      color: c.onSurface,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${displayValue.toStringAsFixed(1)} ${widget.series.unit}',
                      style: TextStyle(
                        fontSize: AppTypography.titleMedium,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    if (displayTimestamp.isNotEmpty)
                      Text(
                        displayTimestamp,
                        style: TextStyle(
                          fontSize: AppTypography.labelSmall,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _TrendChart(
                points: points,
                color: color,
                onHover: (index) => setState(() => _hoverIndex = index),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 监控趋势卡片区域：统一 2 列网格，卡片等高填满容器。
class _MonitoringTrendCards extends StatelessWidget {
  const _MonitoringTrendCards({required this.series, this.maxCardHeight = 300});

  final List<AdminMonitoringSeries> series;
  final double maxCardHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 520;
        final columns = isWide ? 2 : 1;
        final spacing = 12.0;
        final rows = (series.length / columns).ceil().clamp(1, 4);
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final available =
            constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : maxCardHeight;
        final tileHeight = ((available - spacing * (rows - 1)) / rows).clamp(
          140.0,
          maxCardHeight,
        );
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in series)
              SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: _MonitoringTrendCard(series: item),
              ),
          ],
        );
      },
    );
  }
}

/// 监控趋势图 — 渐变填充 + 当前值高亮点 + 水平参考线 + Hover 交互。
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points, required this.color, this.onHover});

  final List<AdminMonitoringSeriesPoint> points;
  final Color color;
  final ValueChanged<int?>? onHover;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    if (points.isEmpty) {
      return Center(
        child: Text(
          '-',
          style: TextStyle(
            fontSize: AppTypography.labelSmall,
            color: c.onSurfaceVariant,
          ),
        ),
      );
    }

    final spots = [
      for (int i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final rawRange = maxY - minY;
    final range =
        rawRange > 0 ? rawRange : (maxY.abs() * 0.1).clamp(1.0, 100.0);
    final gridInterval = range / 3;
    final chartMinY = minY - range * 0.12;
    final chartMaxY = maxY + range * 0.18;
    final labelInterval = points.length > 4 ? (points.length / 4).ceil() : 1;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: gridInterval,
          getDrawingHorizontalLine:
              (value) => FlLine(
                color: c.outlineVariant.withValues(alpha: 0.12),
                strokeWidth: 0.8,
                dashArray: [4, 4],
              ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: gridInterval,
              getTitlesWidget:
                  (value, meta) => Text(
                    value.toStringAsFixed(value.abs() >= 100 ? 0 : 1),
                    style: TextStyle(
                      fontSize: AppTypography.labelSmall,
                      color: c.onSurfaceVariant,
                    ),
                  ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: labelInterval.toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _shortMonitoringTimestamp(points[index].timestamp),
                    style: TextStyle(
                      fontSize: AppTypography.labelSmall,
                      color: c.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          enabled: onHover != null,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems:
                (spots) =>
                    spots.map((spot) {
                      return LineTooltipItem(
                        spot.y.toStringAsFixed(1),
                        TextStyle(
                          fontSize: AppTypography.labelSmall,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      );
                    }).toList(),
          ),
          touchCallback: (event, response) {
            if (event is FlPanEndEvent) {
              onHover?.call(null);
              return;
            }
            final spotIndex = response?.lineBarSpots?.first.spotIndex;
            if (spotIndex != null) {
              onHover?.call(spotIndex);
            }
          },
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: color,
            barWidth: 2.2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) {
                if (index == spots.length - 1) {
                  return FlDotCirclePainter(
                    radius: 3.5,
                    color: color,
                    strokeWidth: 2,
                    strokeColor: c.surfaceContainerLow,
                  );
                }
                return FlDotCirclePainter(
                  radius: 0,
                  color: Colors.transparent,
                  strokeWidth: 0,
                  strokeColor: Colors.transparent,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.28),
                  color.withValues(alpha: 0.08),
                  color.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          if (spots.length > 1)
            LineChartBarData(
              spots: [spots.last],
              barWidth: 0,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  return FlDotCirclePainter(
                    radius: 6,
                    color: color.withValues(alpha: 0.15),
                    strokeWidth: 0,
                    strokeColor: Colors.transparent,
                  );
                },
              ),
              belowBarData: BarAreaData(show: false),
            ),
        ],
        minY: chartMinY,
        maxY: chartMaxY,
      ),
      duration: Duration.zero,
    );
  }
}

class _BoundedMonitoringList extends StatefulWidget {
  const _BoundedMonitoringList({
    required this.maxHeight,
    required this.emptyMessage,
    required this.children,
  });

  final double maxHeight;
  final String emptyMessage;
  final List<Widget> children;

  @override
  State<_BoundedMonitoringList> createState() => _BoundedMonitoringListState();
}

class _BoundedMonitoringListState extends State<_BoundedMonitoringList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) {
      return _EmptyText(widget.emptyMessage);
    }
    final list = Scrollbar(
      controller: _controller,
      thumbVisibility: widget.children.length > 5,
      child: ListView.separated(
        controller: _controller,
        primary: false,
        shrinkWrap: widget.maxHeight.isFinite,
        itemCount: widget.children.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) => widget.children[index],
      ),
    );
    if (!widget.maxHeight.isFinite) {
      return list;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: list,
    );
  }
}

String _shortMonitoringTimestamp(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed != null) {
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  if (value.length >= 5) {
    return value.substring(value.length - 5);
  }
  return value;
}
