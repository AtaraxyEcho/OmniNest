import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';

/// 概览页活动趋势曲线（每日计数指标）。
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
        titlesData: _axisTitles(c, data),
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
      duration: _chartAnimDuration,
    );
  }
}

const _chartAnimDuration = Duration(milliseconds: 400);

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
  if (v > 0 && v < 1) return v.toStringAsFixed(1);
  return v.toInt().toString();
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

FlTitlesData _axisTitles(AdminColors c, List<DailyMetric> data) {
  return FlTitlesData(
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
  );
}

LineTouchData _touchData(
  Color color,
  AdminColors c, {
  required List<DailyMetric> data,
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
              return LineTooltipItem(
                '${data[index].date}\n${_fmt(spot.y)}',
                TextStyle(
                  color: c.onSurface,
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
  ),
);
