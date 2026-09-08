part of 'admin_analytics_page.dart';

FlLine _gridLine(Color c) => FlLine(
  color: c.withValues(alpha: 0.08),
  strokeWidth: 0.5,
  dashArray: [4, 4],
);

TextStyle _labelStyle(AdminColors c) => TextStyle(
  fontSize: AppTypography.labelSmall,
  color: c.onSurfaceVariant,
  height: 1,
);

String _fmt(double v) {
  if (!v.isFinite || v.isNaN) return '0';
  if (v < 0) return '-${_fmt(-v)}';
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
  return v.toInt().toString();
}

String _fmtGb(double bytes) {
  if (!bytes.isFinite || bytes.isNaN) return '0.00G';
  if (bytes < 0) return '-${_fmtGb(-bytes)}';
  final gb = bytes / (1024 * 1024 * 1024);
  if (gb >= 100) return '${gb.toStringAsFixed(0)}G';
  if (gb >= 10) return '${gb.toStringAsFixed(1)}G';
  return '${gb.toStringAsFixed(2)}G';
}

double _interval(List<double> values, {int divisions = 4}) {
  final finite = values.where((v) => v.isFinite && !v.isNaN).toList();
  if (finite.isEmpty) return 1;
  final max = finite.reduce((a, b) => a > b ? a : b);
  if (max <= 0) return 1;
  return (max / divisions).ceilToDouble().clamp(1.0, double.infinity);
}

double _safeMaxY(List<double> values, {double fallback = 10}) {
  final finite = values.where((v) => v.isFinite && !v.isNaN && v > 0).toList();
  if (finite.isEmpty) return fallback;
  return finite.reduce((a, b) => a > b ? a : b) * 1.1;
}

/// 面积渐变（ECharts 风格 3-stop）。
LinearGradient _areaGradient(Color color) => LinearGradient(
  colors: [
    color.withValues(alpha: 0.30),
    color.withValues(alpha: 0.08),
    color.withValues(alpha: 0.0),
  ],
  stops: const [0.0, 0.5, 1.0],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);

// ═══════════════════════════════════════════════════════════════════════
// 通用曲线图（用户增长 / 概览页复用）
// ═══════════════════════════════════════════════════════════════════════

class CurveChart extends StatelessWidget {
  const CurveChart({super.key, required this.data, required this.color});

  final List<DailyMetric> data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final values = data.map((d) => d.value.toDouble()).toList();
    final iv = _interval(values);
    final maxY = _safeMaxY(values);
    final showDots = data.length <= 14;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: iv,
          getDrawingHorizontalLine: (_) => _gridLine(c.outlineVariant),
        ),
        titlesData: _axisTitles(c, data, showGb: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < data.length; i++)
                FlSpot(i.toDouble(), data[i].value.toDouble()),
            ],
            isCurved: true,
            curveSmoothness: 0.4,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: showDots,
              getDotPainter:
                  (_, _, _, _) => FlDotCirclePainter(
                    radius: 3,
                    color: color,
                    strokeWidth: 2,
                    strokeColor: c.surfaceContainerLow,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: _areaGradient(color),
            ),
          ),
        ],
        lineTouchData: _touchData(color, c, data: data),
      ),
      duration: Duration.zero,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 阶梯折线图（存储占用）
// ═══════════════════════════════════════════════════════════════════════

class StepChart extends StatelessWidget {
  const StepChart({super.key, required this.data, required this.color});

  final List<DailyMetric> data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final values = data.map((d) => d.value.toDouble()).toList();
    final iv = _interval(values);
    final maxY = _safeMaxY(values);
    final showDots = data.length <= 14;
    // 构造阶梯点：每个值复制为 (i, v) 和 (i+1, v) 形成直角转折。
    final stepSpots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      final v = data[i].value.toDouble();
      stepSpots.add(FlSpot(i.toDouble(), v));
      if (i < data.length - 1) {
        stepSpots.add(FlSpot((i + 1).toDouble(), v));
      }
    }
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: iv,
          getDrawingHorizontalLine: (_) => _gridLine(c.outlineVariant),
        ),
        titlesData: _axisTitles(c, data, showGb: true),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: stepSpots,
            isCurved: false,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: showDots,
              getDotPainter: (spot, _, _, _) {
                // 只在原始数据点（整数 x）显示圆点。
                final isOriginal = spot.x == spot.x.roundToDouble();
                if (!isOriginal || !showDots) {
                  return FlDotCirclePainter(
                    radius: 0,
                    color: Colors.transparent,
                    strokeWidth: 0,
                    strokeColor: Colors.transparent,
                  );
                }
                return FlDotCirclePainter(
                  radius: 3,
                  color: color,
                  strokeWidth: 2,
                  strokeColor: c.surfaceContainerLow,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: _areaGradient(color),
            ),
          ),
        ],
        lineTouchData: _touchData(color, c, data: data, showGb: true),
      ),
      duration: Duration.zero,
    );
  }
}

/// 通用坐标轴配置。
FlTitlesData _axisTitles(
  AdminColors c,
  List<DailyMetric> data, {
  required bool showGb,
}) {
  return FlTitlesData(
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: showGb ? 48 : 38,
        getTitlesWidget:
            (v, _) => Text(showGb ? _fmtGb(v) : _fmt(v), style: _labelStyle(c)),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: data.length > 14 ? (data.length / 7).ceilToDouble() : 1,
        getTitlesWidget: (v, _) {
          final i = v.toInt();
          if (i < 0 || i >= data.length) return const SizedBox();
          final d = data[i].date;
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              d.length >= 5 ? d.substring(5) : d,
              style: _labelStyle(c),
            ),
          );
        },
      ),
    ),
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
  );
}

/// 通用触摸交互。
LineTouchData _touchData(
  Color color,
  AdminColors c, {
  required List<DailyMetric> data,
  bool showGb = false,
}) => LineTouchData(
  touchSpotThreshold: 20,
  handleBuiltInTouches: true,
  getTouchedSpotIndicator:
      (_, indices) =>
          indices
              .map(
                (_) => TouchedSpotIndicatorData(
                  FlLine(
                    color: color.withValues(alpha: 0.15),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                  FlDotData(
                    show: true,
                    getDotPainter:
                        (_, _, _, _) => FlDotCirclePainter(
                          radius: 4.5,
                          color: color,
                          strokeWidth: 2,
                          strokeColor: c.surfaceContainerLow,
                        ),
                  ),
                ),
              )
              .toList(),
  touchTooltipData: LineTouchTooltipData(
    getTooltipColor: (_) => c.surfaceContainerHighest,
    tooltipRoundedRadius: 6,
    tooltipPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    getTooltipItems:
        (spots) =>
            spots.map((spot) {
              final index = spot.x.round().clamp(0, data.length - 1);
              final value = showGb ? _fmtGb(spot.y) : _fmt(spot.y);
              return LineTooltipItem(
                '${data[index].date}\n$value',
                TextStyle(
                  color: c.onSurface,
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
  ),
);

// ═══════════════════════════════════════════════════════════════════════
// 用户增长（曲线图 + 填充）
// ═══════════════════════════════════════════════════════════════════════

class _TaskBarChart extends StatelessWidget {
  const _TaskBarChart({required this.data});
  final List<DailyTaskMetric> data;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final totals =
        data
            .map((d) => (d.completed + d.failed + d.running).toDouble())
            .toList();
    final maxY = _safeMaxY(totals);
    final iv = (maxY / 4).ceilToDouble().clamp(1.0, double.infinity);
    final barW = data.length > 14 ? 8.0 : 14.0;
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barGroups: [
          for (int i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              groupVertically: true,
              barRods: [
                BarChartRodData(
                  toY: totals[i],
                  color: Colors.transparent,
                  width: barW,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                  rodStackItems: [
                    if (data[i].running > 0)
                      BarChartRodStackItem(
                        0,
                        data[i].running.toDouble(),
                        c.tertiary,
                      ),
                    if (data[i].failed > 0)
                      BarChartRodStackItem(
                        data[i].running.toDouble(),
                        (data[i].running + data[i].failed).toDouble(),
                        c.error,
                      ),
                    if (data[i].completed > 0)
                      BarChartRodStackItem(
                        (data[i].running + data[i].failed).toDouble(),
                        totals[i],
                        c.primary,
                      ),
                  ],
                ),
              ],
            ),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: iv,
          getDrawingHorizontalLine: (_) => _gridLine(c.outlineVariant),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (v, _) => Text(_fmt(v), style: _labelStyle(c)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: data.length > 14 ? (data.length / 7).ceilToDouble() : 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= data.length) return const SizedBox();
                final d = data[i].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    d.length >= 5 ? d.substring(5) : d,
                    style: _labelStyle(c),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => c.onSurface.withValues(alpha: 0.92),
            tooltipRoundedRadius: 8,
            getTooltipItem: (group, _, rod, _) {
              final d = data[group.x.toInt()];
              final hasData = d.completed > 0 || d.failed > 0 || d.running > 0;
              if (!hasData) return null;
              final l10n = AppLocalizations.of(context);
              return BarTooltipItem(
                l10n.adminTaskThroughputTooltip(d.completed, d.failed),
                TextStyle(
                  color: c.surface,
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
      ),
      duration: Duration.zero,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 存储占用（阶梯折线图）
// ═══════════════════════════════════════════════════════════════════════

class _SystemLoadBars extends StatelessWidget {
  const _SystemLoadBars({required this.load});
  final SystemLoadSnapshot load;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final l10n = AppLocalizations.of(context);
    final items = [
      (label: l10n.adminLoadCpu, value: load.cpuUsage),
      (label: l10n.adminLoadMemory, value: load.memoryUsage),
      (label: l10n.adminLoadDisk, value: load.diskUsage),
      (label: l10n.adminLoadJvm, value: load.jvmHeapUsage),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items) ...[
              Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w700,
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (item.value / 100).clamp(0, 1),
                        minHeight: 10,
                        backgroundColor: c.outlineVariant.withValues(
                          alpha: 0.16,
                        ),
                        color: _ringColor(item.value, c),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 46,
                    child: Text(
                      '${item.value.toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w800,
                        color: _ringColor(item.value, c),
                      ),
                    ),
                  ),
                ],
              ),
              if (item != items.last) const SizedBox(height: 22),
            ],
          ],
        ),
      ),
    );
  }
}

Color _ringColor(double value, AdminColors c) {
  if (value >= 85) return c.error;
  if (value >= 70) return c.tertiary;
  return c.success;
}
