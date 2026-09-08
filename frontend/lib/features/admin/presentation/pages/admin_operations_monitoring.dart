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

class AdminMonitoringPage extends StatefulWidget {
  const AdminMonitoringPage({required this.view, super.key});

  final AdminMonitoringView view;

  @override
  State<AdminMonitoringPage> createState() => _AdminMonitoringPageState();
}

class _AdminMonitoringPageState extends State<AdminMonitoringPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(duration: MotionToken.slow, vsync: this)
      ..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Widget _fadeSlide(int index, Widget child) {
    final start = index * 0.15;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final adminColors = context.adminColors;
    final warnCount =
        widget.view.components.where((item) => item.status != 'UP').length +
        widget.view.alerts.where((item) => item.severity == 'WARNING').length;
    final overview = widget.view.overview;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fadeSlide(
          0,
          AdminPageHeader(
            title: l10n.adminSystemMonitoring,
            subtitle: l10n.adminMonitoringSubtitle,
            trailing: AdminStatusPill(
              label:
                  overview.status == 'UP'
                      ? l10n.adminRunning
                      : l10n.adminAttentionItems('$warnCount'),
              color:
                  warnCount == 0
                      ? adminColors.success
                      : context.adminColors.error,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _fadeSlide(
          1,
          _MetricGrid(
            mainAxisExtent: 176,
            children: [
              AdminMetricCard(
                title: l10n.adminServiceStatus,
                value: overview.status,
                detail: l10n.adminUptime(overview.uptime),
                icon: Icons.monitor_heart_outlined,
                accent:
                    overview.status == 'UP'
                        ? adminColors.success
                        : context.adminColors.error,
                supporting: [
                  AdminMetricMiniStat(
                    label: l10n.adminComponents,
                    value: widget.view.components.length.toString(),
                  ),
                  AdminMetricMiniStat(
                    label: l10n.adminAlerts,
                    value: widget.view.alerts.length.toString(),
                  ),
                ],
              ),
              AdminMetricCard(
                title: l10n.adminSystemCpu,
                value: '${overview.cpuUsage.toStringAsFixed(1)}%',
                detail:
                    '${l10n.adminMemory} ${overview.memoryUsage.toStringAsFixed(1)}%',
                icon: Icons.memory_rounded,
                accent: _usageColor(overview.cpuUsage, adminColors),
                progress: overview.cpuUsage / 100,
                supporting: [
                  AdminMetricMiniStat(
                    label: l10n.adminLoadJvm,
                    value: '${overview.jvmHeapUsage.toStringAsFixed(1)}%',
                    color: _usageColor(overview.jvmHeapUsage, adminColors),
                  ),
                ],
              ),
              AdminMetricCard(
                title: l10n.adminDiskUsage,
                value: '${overview.diskUsage.toStringAsFixed(1)}%',
                detail: l10n.adminDataDirectoryDisk,
                icon: Icons.storage_rounded,
                accent: _usageColor(overview.diskUsage, adminColors),
                progress: overview.diskUsage / 100,
                supporting: [
                  AdminMetricMiniStat(
                    label: l10n.adminRequests,
                    value: overview.todayRequests.toString(),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _fadeSlide(
          2,
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1180;
              final trend = _MonitoringTrendPanel(series: widget.view.series);
              final components = AdminInfoPanel(
                title: l10n.adminComponentHealth,
                subtitle: l10n.adminComponentHealthSubtitle,
                children: [
                  _BoundedMonitoringList(
                    maxHeight: 420,
                    emptyMessage: l10n.adminNoComponentHealth,
                    children: [
                      for (final item in widget.view.components)
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
                ],
              );
              final alerts = AdminInfoPanel(
                title: l10n.adminRecentAlerts,
                subtitle: l10n.adminRecentAlertsSubtitle,
                children: [
                  _BoundedMonitoringList(
                    maxHeight: 320,
                    emptyMessage: l10n.adminNoAlerts,
                    children: [
                      for (final alert in widget.view.alerts.take(10))
                        _InfoRow(
                          leading: alert.severity,
                          middle: '${alert.message}\n${alert.timestamp}',
                          trailing: Icon(
                            alert.severity == 'WARNING'
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline_rounded,
                            color:
                                alert.severity == 'WARNING'
                                    ? context.adminColors.error
                                    : adminColors.info,
                          ),
                        ),
                    ],
                  ),
                ],
              );
              final recentOperations = AdminInfoPanel(
                title: l10n.adminRecentOperations,
                subtitle: l10n.adminRecentOperationsSubtitle,
                children: [
                  _BoundedMonitoringList(
                    maxHeight: 320,
                    emptyMessage: l10n.adminNoOperations,
                    children: [
                      for (final item in widget.view.auditRecent.take(20))
                        _InfoRow(
                          leading:
                              item.description.isEmpty
                                  ? item.action
                                  : item.description,
                          middle:
                              '${item.action} · ${item.resourceType} ${item.resourceId ?? ''}\n${item.ipAddress} · ${item.createdAt}',
                          trailing: const Icon(Icons.receipt_long_outlined),
                        ),
                    ],
                  ),
                ],
              );

              if (!isWide) {
                return Column(
                  children: [
                    trend,
                    const SizedBox(height: 24),
                    components,
                    const SizedBox(height: 24),
                    alerts,
                    const SizedBox(height: 24),
                    recentOperations,
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: trend),
                      const SizedBox(width: 24),
                      Expanded(flex: 4, child: components),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: alerts),
                      const SizedBox(width: 24),
                      Expanded(flex: 7, child: recentOperations),
                    ],
                  ),
                ],
              );
            },
          ),
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
      trailing: AdminStatusPill(label: l10n.adminMonitoringStepMinutes(5)),
      children:
          series.isEmpty
              ? [_EmptyText(l10n.adminNoTrendData)]
              : [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 700;
                    final panelWidth =
                        isWide
                            ? (constraints.maxWidth - 16) / 2
                            : constraints.maxWidth;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final item in series)
                          SizedBox(
                            width: panelWidth,
                            child: _MonitoringTrendCard(series: item),
                          ),
                      ],
                    );
                  },
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                      fontSize: 13,
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
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    if (displayTimestamp.isNotEmpty)
                      Text(
                        displayTimestamp,
                        style: TextStyle(
                          fontSize: 11,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
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
          style: TextStyle(fontSize: 11, color: c.onSurfaceVariant),
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
              reservedSize: 38,
              interval: gridInterval,
              getTitlesWidget:
                  (value, meta) => Text(
                    value.toStringAsFixed(value.abs() >= 100 ? 0 : 1),
                    style: TextStyle(fontSize: 10, color: c.onSurfaceVariant),
                  ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: labelInterval.toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _shortMonitoringTimestamp(points[index].timestamp),
                    style: TextStyle(fontSize: 10, color: c.onSurfaceVariant),
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
                          fontSize: 11,
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
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) {
                if (index == spots.length - 1) {
                  return FlDotCirclePainter(
                    radius: 4,
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
          // 当前值高亮圆点（叠加层）
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
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: widget.children.length > 5,
        child: ListView.separated(
          controller: _controller,
          primary: false,
          shrinkWrap: true,
          itemCount: widget.children.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) => widget.children[index],
        ),
      ),
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
