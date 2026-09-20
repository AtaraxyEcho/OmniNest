import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 入场动画：统一交错淡入+滑入
// ─────────────────────────────────────────────────────────────────────────────

/// 页面级入场动画容器：子项按序交错淡入。
class AdminSectionEntrance extends StatefulWidget {
  const AdminSectionEntrance({required this.children, super.key});

  final List<Widget> children;

  @override
  State<AdminSectionEntrance> createState() => _AdminSectionEntranceState();
}

class _AdminSectionEntranceState extends State<AdminSectionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: MotionToken.stagger, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && !_ctrl.isCompleted) {
      _ctrl.forward();
    }
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
          _animated(i, widget.children[i]),
      ],
    );
  }

  Widget _animated(int index, Widget child) {
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

// ─────────────────────────────────────────────────────────────────────────────
// 响应式指标卡网格
// ─────────────────────────────────────────────────────────────────────────────

/// 响应式指标卡网格：按容器宽度自适应列数，固定卡片高度保证同行对齐。
class AdminResponsiveMetricGrid extends StatelessWidget {
  const AdminResponsiveMetricGrid({
    required this.children,
    this.cardHeight = 208,
    super.key,
  });

  final List<Widget> children;

  /// 统一卡片高度（含 sparkline + 徽标行的完整高度）。
  ///
  /// 基准 208：内边距 32 + 标题/数值/明细约 80 + 趋势 32 + 徽标 24 + 间距，
  /// 为趋势徽标与长文案留出余量，避免 Column 底部溢出。
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // 四列阈值放宽，避免宽屏下卡片过窄导致数值/徽标换行错位。
        final columns =
            w >= 1280
                ? 4
                : w >= 820
                ? 2
                : 1;
        // 字体放大时卡片高度同步放大，防溢出。
        final textScale =
            MediaQuery.textScalerOf(
              context,
            ).scale(1).clamp(1.0, 1.4).toDouble();
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: cardHeight * textScale,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

/// 统一仪表环网格：控制台监控与可视化图表共用，保证同一行对齐。
///
/// 使用 Wrap 而非 GridView，避免 shrink-wrap viewport 无法参与 intrinsic 高度测量。
class AdminGaugeGrid extends StatelessWidget {
  const AdminGaugeGrid({
    required this.children,
    this.gaugeSize = 112,
    this.spacing = 12,
    super.key,
  });

  final List<Widget> children;
  final double gaugeSize;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth == double.infinity
                ? 720.0
                : constraints.maxWidth;
        final columns =
            width >= 520
                ? 4
                : width >= 360
                ? 2
                : 1;
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        return Align(
          alignment: Alignment.topCenter,
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final child in children)
                SizedBox(
                  width: itemWidth.clamp(gaugeSize, itemWidth),
                  child: Center(child: child),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sparkline 迷你趋势线
// ─────────────────────────────────────────────────────────────────────────────

/// 指标卡内嵌迷你趋势线（无坐标轴，仅曲线+面积）。
class AdminSparkline extends StatelessWidget {
  const AdminSparkline({
    required this.values,
    required this.color,
    this.height = 36,
    super.key,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(height: height);
    }
    final max = values.reduce((a, b) => a > b ? a : b);
    final min = values.reduce((a, b) => a < b ? a : b);
    final range = (max - min) == 0 ? 1.0 : (max - min).toDouble();
    final spots = [
      for (int i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: min - range * 0.1,
          maxY: max + range * 0.1,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: color,
              barWidth: 1.8,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.25),
                    color.withValues(alpha: 0.0),
                  ],
                  stops: const [0, 1],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          lineTouchData: const LineTouchData(enabled: false),
        ),
        duration: const Duration(milliseconds: 300),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 径向仪表（系统监控）
// ─────────────────────────────────────────────────────────────────────────────

/// 圆环仪表：展示百分比指标（CPU/内存/磁盘等）。
class AdminGaugeRing extends StatelessWidget {
  const AdminGaugeRing({
    required this.label,
    required this.value,
    required this.detail,
    this.size = 120,
    super.key,
  });

  final String label;
  final double value;
  final String detail;
  final double size;

  Color _color(AdminColors c) {
    if (value >= 85) return c.error;
    if (value >= 70) return c.tertiary;
    return c.success;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final color = _color(c);
    final clamped = value.clamp(0, 100) / 100;
    return SizedBox(
      width: size,
      height: size + 52,
      child: Column(
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _GaugeRingPainter(
                progress: clamped,
                color: color,
                trackColor: c.outlineVariant.withValues(alpha: 0.16),
                strokeWidth: 8,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${value.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: AppTypography.headlineMedium,
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w700,
              color: c.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: TextStyle(
              fontSize: AppTypography.labelSmall,
              color: c.onSurfaceVariant.withValues(alpha: 0.70),
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugeRingPainter extends CustomPainter {
  const _GaugeRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 轨道
    final trackPaint =
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * 3.14159265, false, trackPaint);

    // 进度弧（从顶部顺时针）
    final progressPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -3.14159265 / 2,
      2 * 3.14159265 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_GaugeRingPainter old) =>
      old.progress != progress || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// 趋势指标徽标（↑↓ + 百分比）
// ─────────────────────────────────────────────────────────────────────────────

/// 趋势方向徽标：与上一周期对比的涨跌指示。
class AdminTrendBadge extends StatelessWidget {
  const AdminTrendBadge({
    required this.current,
    required this.previous,
    this.invertGood = false,
    super.key,
  });

  final double current;
  final double previous;

  /// 为 true 时下降视为好趋势（如错误率、延迟）。
  final bool invertGood;

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final delta = previous == 0 ? 0.0 : ((current - previous) / previous * 100);
    final isUp = delta >= 0;
    final isGood = invertGood ? !isUp : isUp;
    final color =
        delta == 0
            ? c.onSurfaceVariant
            : isGood
            ? c.success
            : c.error;
    final icon =
        delta == 0
            ? Icons.trending_flat_rounded
            : isUp
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          delta == 0 ? '—' : '${delta.abs().toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: AppTypography.labelSmall,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 时间范围选择器（图表页）
// ─────────────────────────────────────────────────────────────────────────────

/// 时间范围分段选择器。
class AdminTimeRangeSelector extends StatelessWidget {
  const AdminTimeRangeSelector({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final int selected; // 天数：7 / 30 / 90
  final ValueChanged<int> onChanged;

  static const ranges = [7, 30, 90];

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    return SegmentedButton<int>(
      segments: [
        for (final d in ranges) ButtonSegment(value: d, label: Text('${d}d')),
      ],
      selected: {selected},
      onSelectionChanged: (set) => onChanged(set.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: AppTypography.labelSmall),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.primary;
          return c.onSurfaceVariant;
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 服务状态网格瓦片（系统监控）
// ─────────────────────────────────────────────────────────────────────────────

/// 服务健康状态瓦片：图标 + 名称 + 状态指示灯。
class AdminServiceTile extends StatelessWidget {
  const AdminServiceTile({
    required this.name,
    required this.status,
    required this.detail,
    super.key,
  });

  final String name;
  final String status;
  final String detail;

  Color _statusColor(AdminColors c) {
    return switch (status) {
      'UP' => c.success,
      'WARN' => c.warning,
      _ => c.error,
    };
  }

  IconData _statusIcon() {
    return switch (status) {
      'UP' => Icons.check_circle_rounded,
      'WARN' => Icons.warning_rounded,
      _ => Icons.error_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.adminColors;
    final color = _statusColor(c);
    return WorkbenchPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(_statusIcon(), size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w700,
                    color: c.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.labelSmall,
                    color: c.onSurfaceVariant.withValues(alpha: 0.70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
