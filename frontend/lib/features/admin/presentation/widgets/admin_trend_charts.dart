import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';

/// 悬停浮牌宽度估算：直角小卡（日期 + 三行等宽计数），用于夹取定位。
const double _kHoverCardWidthEstimate = 176;

/// 悬停浮牌高度估算：上下内边距 16 + 4 行 * 16 行高。
const double _kHoverCardHeightEstimate = 80;

/// 图表图例：8px 直角色块 + 标签，柱状图与折线图共用。
class AdminChartLegend extends StatelessWidget {
  const AdminChartLegend({required this.color, required this.label, super.key});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 折线图数据点：日期 + 单序列数值（用户增长、存储增长等按日聚合）。
class AdminChartPoint {
  const AdminChartPoint({required this.date, required this.value});

  final String date;
  final double value;
}

/// 直角吞吐柱状图：1px 细线网格、矩形堆叠柱（完成=前景、失败=绯红），
/// 零渐变零圆角；X 轴等宽日期刻度（短序列逐日，长序列每 5 日 + 末点）。
///
/// 鼠标悬停时追踪指针 x 命中柱索引：命中柱加 1px 描边高亮、光标精确，
/// 并在指针旁弹出直角等宽小浮牌（日期 / 完成 / 失败 / 运行），移出清除；
/// Semantics 标签随悬停同步当前柱数值。
///
/// 颜色参数缺省取主题映射（网格=outlineVariant、柱=onSurface、失败=error）。
/// [xAxisLabelCount] 与 [labelAxisWidth] 为坐标轴标注改造预留：
/// 前者显式指定刻度数量（缺省按数据长度自适应），后者为左侧 Y 轴标注
/// 预留留边宽度，缺省 0 即全宽绘图。
class AdminThroughputBarChart extends StatefulWidget {
  const AdminThroughputBarChart({
    required this.data,
    this.gridColor,
    this.barColor,
    this.failedColor,
    this.gridLines = 4,
    this.xAxisLabelCount,
    this.labelAxisWidth = 0,
    this.semanticsLabel,
    this.tickLabels,
    super.key,
  });

  final List<DailyTaskMetric> data;

  final Color? gridColor;
  final Color? barColor;
  final Color? failedColor;

  /// 水平网格线数量（含顶底线）。
  final int gridLines;

  /// X 轴日期刻度数量；null 时自适应。
  final int? xAxisLabelCount;

  /// 左侧 Y 轴标注预留的留边宽度，默认 0 即全宽绘图。
  final double labelAxisWidth;

  /// 无障碍基础描述（图表标题）；悬停时追加当前柱数值。
  final String? semanticsLabel;

  /// X 轴刻度文本覆盖（按数据点下标对应）；缺省回落到日期缩写。
  final List<String>? tickLabels;

  @override
  State<AdminThroughputBarChart> createState() =>
      _AdminThroughputBarChartState();
}

class _AdminThroughputBarChartState extends State<AdminThroughputBarChart> {
  int? _hoverIndex;
  Offset? _hoverPosition;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ticks = _tickIndices(widget.data.length, widget.xAxisLabelCount);
    // 图表整体作为一个语义节点：基础描述 + 悬停点数值，
    // 子树刻度文本为冗余装饰，排除以避免合并污染标签。
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: _semanticsLabel(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final chartHeight = height - 20;
          return Column(
            children: [
              SizedBox(
                height: chartHeight,
                width: width,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.precise,
                        onHover:
                            (event) => _updateHover(event.localPosition, width),
                        onExit: (_) => _clearHover(),
                        child: CustomPaint(
                          size: Size(width, chartHeight),
                          painter: AdminThroughputBarPainter(
                            data: widget.data,
                            gridColor:
                                widget.gridColor ?? scheme.outlineVariant,
                            barColor: widget.barColor ?? scheme.onSurface,
                            failedColor: widget.failedColor ?? scheme.error,
                            gridLines: widget.gridLines,
                            labelAxisWidth: widget.labelAxisWidth,
                            labelStyle:
                                widget.labelAxisWidth > 0
                                    ? _axisTextStyle(scheme)
                                    : null,
                            hoverIndex: _hoverIndex,
                            hoverBorderColor: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    if (_hoverIndex != null && _hoverPosition != null)
                      Positioned(
                        left: _hoverLeft(width),
                        top: _hoverTop(chartHeight),
                        child: IgnorePointer(
                          child: _ChartHoverCard(lines: _hoverLines()),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 18,
                width: width,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final index in ticks)
                      Text(
                        widget.tickLabels != null &&
                                index < widget.tickLabels!.length
                            ? widget.tickLabels![index]
                            : _shortDate(widget.data[index].date),
                        style: _axisTextStyle(scheme),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 指针 x → 柱索引：plotLeft + slot 槽位取整；越出绘图区即清除。
  void _updateHover(Offset position, double width) {
    final plotLeft = widget.labelAxisWidth;
    final plotWidth = width - plotLeft;
    if (widget.data.isEmpty || plotWidth <= 0 || position.dx < plotLeft) {
      _clearHover();
      return;
    }
    final slot = plotWidth / widget.data.length;
    final index = ((position.dx - plotLeft) / slot).floor().clamp(
      0,
      widget.data.length - 1,
    );
    setState(() {
      _hoverIndex = index;
      _hoverPosition = position;
    });
  }

  void _clearHover() {
    if (_hoverIndex == null) {
      return;
    }
    setState(() {
      _hoverIndex = null;
      _hoverPosition = null;
    });
  }

  /// 浮牌水平定位：指针右侧偏移 12，越界时向左夹取保持浮牌完整可见。
  double _hoverLeft(double width) {
    final maxLeft =
        width - _kHoverCardWidthEstimate < 0
            ? 0.0
            : width - _kHoverCardWidthEstimate;
    return (_hoverPosition!.dx + 12).clamp(0.0, maxLeft);
  }

  /// 浮牌垂直定位：优先悬于指针上方，顶部越界时贴顶。
  double _hoverTop(double chartHeight) {
    final maxTop =
        chartHeight - _kHoverCardHeightEstimate < 0
            ? 0.0
            : chartHeight - _kHoverCardHeightEstimate;
    return (_hoverPosition!.dy - _kHoverCardHeightEstimate - 8).clamp(
      0.0,
      maxTop,
    );
  }

  List<String> _hoverLines() {
    final l10n = AppLocalizations.of(context);
    final index = _hoverIndex;
    if (index == null || index >= widget.data.length) {
      return const <String>[];
    }
    final item = widget.data[index];
    return <String>[
      item.date,
      l10n.adminChartTipCompleted(item.completed),
      l10n.adminChartTipFailed(item.failed),
      l10n.adminChartTipRunning(item.running),
    ];
  }

  String? _semanticsLabel() {
    final base = widget.semanticsLabel;
    final hover = _hoverLines().join(', ');
    if (base == null || base.isEmpty) {
      return hover.isEmpty ? null : hover;
    }
    return hover.isEmpty ? base : '$base, $hover';
  }
}

class AdminThroughputBarPainter extends CustomPainter {
  const AdminThroughputBarPainter({
    required this.data,
    required this.gridColor,
    required this.barColor,
    required this.failedColor,
    this.gridLines = 4,
    this.labelAxisWidth = 0,
    this.labelStyle,
    this.hoverIndex,
    this.hoverBorderColor,
  });

  final List<DailyTaskMetric> data;
  final Color gridColor;
  final Color barColor;
  final Color failedColor;
  final int gridLines;
  final double labelAxisWidth;

  /// Y 轴数值标注样式；留边宽度大于 0 且提供样式时按网格线绘制刻度值。
  final TextStyle? labelStyle;

  /// 当前悬停柱索引；命中柱追加 1px 描边高亮。
  final int? hoverIndex;

  /// 悬停描边色；null 时不描边。
  final Color? hoverBorderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = gridLines <= 0 ? 1 : gridLines;
    final gridPaint =
        Paint()
          ..color = gridColor
          ..strokeWidth = 1;
    for (var i = 0; i <= lines; i++) {
      final y = (size.height * i / lines).floorToDouble() + 0.5;
      canvas.drawLine(
        Offset(labelAxisWidth, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    if (data.isEmpty) {
      return;
    }
    final maxTotal = data
        .map((d) => d.completed + d.failed + d.running)
        .reduce((a, b) => a > b ? a : b);
    final labelStyle = this.labelStyle;
    if (labelStyle != null && labelAxisWidth > 0 && maxTotal > 0) {
      final lines = gridLines <= 0 ? 1 : gridLines;
      for (var i = 0; i <= lines; i++) {
        final y = (size.height * i / lines).floorToDouble() + 0.5;
        _paintAxisLabel(canvas, maxTotal * (lines - i) / lines, y, labelStyle);
      }
    }
    if (maxTotal <= 0) {
      return;
    }
    final plotWidth = size.width - labelAxisWidth;
    final slot = plotWidth / data.length;
    // 样板柱占比约四成槽宽；窄窗口退化到 6px 保底、宽屏封顶 26px。
    final barWidth = (slot * 0.42).clamp(6.0, 26.0);
    for (var i = 0; i < data.length; i++) {
      final item = data[i];
      final total = item.completed + item.failed + item.running;
      if (total <= 0) {
        continue;
      }
      final centerX = labelAxisWidth + slot * i + slot / 2;
      final totalHeight = total / maxTotal * (size.height - 4);
      final barTop = size.height - totalHeight;
      var top = barTop;
      if (item.failed > 0) {
        final failedHeight = item.failed / total * totalHeight;
        canvas.drawRect(
          Rect.fromLTWH(centerX - barWidth / 2, top, barWidth, failedHeight),
          Paint()..color = failedColor,
        );
        top += failedHeight;
      }
      if (item.completed + item.running > 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            centerX - barWidth / 2,
            top,
            barWidth,
            (item.completed + item.running) / total * totalHeight,
          ),
          Paint()..color = barColor,
        );
      }
      final border = hoverBorderColor;
      if (i == hoverIndex && border != null) {
        canvas.drawRect(
          Rect.fromLTWH(
            centerX - barWidth / 2 - 0.5,
            barTop - 0.5,
            barWidth + 1,
            totalHeight + 1,
          ),
          Paint()
            ..color = border
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant AdminThroughputBarPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.barColor != barColor ||
        oldDelegate.failedColor != failedColor ||
        oldDelegate.gridLines != gridLines ||
        oldDelegate.labelAxisWidth != labelAxisWidth ||
        oldDelegate.labelStyle != labelStyle ||
        oldDelegate.hoverIndex != hoverIndex ||
        oldDelegate.hoverBorderColor != hoverBorderColor;
  }

  void _paintAxisLabel(Canvas canvas, double value, double y, TextStyle style) {
    final text =
        value >= 1000
            ? '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k'
            : value.round().toString();
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(0, (y - painter.height / 2).clamp(0.0, 1000)));
    painter.dispose();
  }
}

/// 直角细线折线图：1px 折线 + 末端方块标记 + 水平细网格，
/// 零渐变零圆角；适用于用户增长、存储增长等单序列按日数据。
///
/// 悬停交互与柱状图同款：指针 x 命中最近数据点，绘制垂直细线与
/// 方块标记高亮，并在指针旁弹出直角等宽小浮牌（日期 + 数值）。
/// 参数预留语义与 [AdminThroughputBarChart] 一致。
class AdminHairlineLineChart extends StatefulWidget {
  const AdminHairlineLineChart({
    required this.points,
    this.lineColor,
    this.gridColor,
    this.markerColor,
    this.gridLines = 3,
    this.xAxisLabelCount,
    this.labelAxisWidth = 0,
    this.valueFormatter,
    this.semanticsLabel,
    super.key,
  });

  final List<AdminChartPoint> points;

  final Color? lineColor;
  final Color? gridColor;
  final Color? markerColor;

  /// 水平网格线数量（含顶底线）。
  final int gridLines;

  /// X 轴日期刻度数量；null 时自适应。
  final int? xAxisLabelCount;

  /// 左侧 Y 轴标注预留的留边宽度，默认 0 即全宽绘图。
  final double labelAxisWidth;

  /// 悬停浮牌与语义标签的数值格式化；缺省输出原始数值。
  final String Function(double value)? valueFormatter;

  /// 无障碍基础描述（图表标题）；悬停时追加当前点日期与数值。
  final String? semanticsLabel;

  @override
  State<AdminHairlineLineChart> createState() => _AdminHairlineLineChartState();
}

class _AdminHairlineLineChartState extends State<AdminHairlineLineChart> {
  int? _hoverIndex;
  Offset? _hoverPosition;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ticks = _tickIndices(widget.points.length, widget.xAxisLabelCount);
    // 图表整体作为一个语义节点：基础描述 + 悬停点数值，
    // 子树刻度文本为冗余装饰，排除以避免合并污染标签。
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: _semanticsLabel(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final chartHeight = height - 20;
          return Column(
            children: [
              SizedBox(
                height: chartHeight,
                width: width,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.precise,
                        onHover:
                            (event) => _updateHover(event.localPosition, width),
                        onExit: (_) => _clearHover(),
                        child: CustomPaint(
                          size: Size(width, chartHeight),
                          painter: _HairlineLinePainter(
                            points: widget.points,
                            lineColor: widget.lineColor ?? scheme.onSurface,
                            gridColor:
                                widget.gridColor ?? scheme.outlineVariant,
                            markerColor: widget.markerColor ?? scheme.onSurface,
                            gridLines: widget.gridLines,
                            labelAxisWidth: widget.labelAxisWidth,
                            hoverIndex: _hoverIndex,
                          ),
                        ),
                      ),
                    ),
                    if (_hoverIndex != null && _hoverPosition != null)
                      Positioned(
                        left: _hoverLeft(width),
                        top: _hoverTop(chartHeight),
                        child: IgnorePointer(
                          child: _ChartHoverCard(lines: _hoverLines()),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 18,
                width: width,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final index in ticks)
                      Text(
                        _shortDate(widget.points[index].date),
                        style: _axisTextStyle(scheme),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 指针 x → 最近点索引：按绘图区比例四舍五入；越出绘图区即清除。
  void _updateHover(Offset position, double width) {
    final plotLeft = widget.labelAxisWidth;
    final plotWidth = width - plotLeft;
    final count = widget.points.length;
    if (count == 0 || plotWidth <= 0 || position.dx < plotLeft) {
      _clearHover();
      return;
    }
    final index =
        count == 1
            ? 0
            : ((position.dx - plotLeft) / plotWidth * (count - 1))
                .round()
                .clamp(0, count - 1);
    setState(() {
      _hoverIndex = index;
      _hoverPosition = position;
    });
  }

  void _clearHover() {
    if (_hoverIndex == null) {
      return;
    }
    setState(() {
      _hoverIndex = null;
      _hoverPosition = null;
    });
  }

  double _hoverLeft(double width) {
    final maxLeft =
        width - _kHoverCardWidthEstimate < 0
            ? 0.0
            : width - _kHoverCardWidthEstimate;
    return (_hoverPosition!.dx + 12).clamp(0.0, maxLeft);
  }

  double _hoverTop(double chartHeight) {
    final maxTop =
        chartHeight - _kHoverCardHeightEstimate < 0
            ? 0.0
            : chartHeight - _kHoverCardHeightEstimate;
    return (_hoverPosition!.dy - _kHoverCardHeightEstimate - 8).clamp(
      0.0,
      maxTop,
    );
  }

  List<String> _hoverLines() {
    final index = _hoverIndex;
    if (index == null || index >= widget.points.length) {
      return const <String>[];
    }
    final point = widget.points[index];
    final value =
        widget.valueFormatter?.call(point.value) ??
        point.value.toStringAsFixed(0);
    return <String>[point.date, value];
  }

  String? _semanticsLabel() {
    final base = widget.semanticsLabel;
    final hover = _hoverLines().join(': ');
    if (base == null || base.isEmpty) {
      return hover.isEmpty ? null : hover;
    }
    return hover.isEmpty ? base : '$base, $hover';
  }
}

class _HairlineLinePainter extends CustomPainter {
  const _HairlineLinePainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.markerColor,
    this.gridLines = 3,
    this.labelAxisWidth = 0,
    this.hoverIndex,
  });

  final List<AdminChartPoint> points;
  final Color lineColor;
  final Color gridColor;
  final Color markerColor;
  final int gridLines;
  final double labelAxisWidth;

  /// 当前悬停点索引；命中点绘制垂直细线与放大方块标记。
  final int? hoverIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = gridLines <= 0 ? 1 : gridLines;
    final gridPaint =
        Paint()
          ..color = gridColor
          ..strokeWidth = 1;
    for (var i = 0; i <= lines; i++) {
      final y = (size.height * i / lines).floorToDouble() + 0.5;
      canvas.drawLine(
        Offset(labelAxisWidth, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    if (points.isEmpty) {
      return;
    }
    final plotWidth = size.width - labelAxisWidth;
    final maxValue = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    Offset pointAt(int index) {
      final x =
          points.length == 1
              ? labelAxisWidth + plotWidth / 2
              : labelAxisWidth + plotWidth * index / (points.length - 1);
      final y =
          maxValue <= 0
              ? size.height
              : size.height -
                  points[index].value / maxValue * (size.height - 4);
      return Offset(x, y);
    }

    if (points.length > 1) {
      final linePaint =
          Paint()
            ..color = lineColor
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(pointAt(i).dx, pointAt(i).dy);
      }
      canvas.drawPath(path, linePaint);
    }

    final hover = hoverIndex;
    if (hover != null && hover >= 0 && hover < points.length) {
      final anchor = pointAt(hover);
      final hoverPaint =
          Paint()
            ..color = gridColor
            ..strokeWidth = 1;
      canvas.drawLine(
        Offset(anchor.dx, 0),
        Offset(anchor.dx, size.height),
        hoverPaint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: anchor, width: 5, height: 5),
        Paint()..color = markerColor,
      );
    }
    canvas.drawRect(
      Rect.fromCenter(center: pointAt(points.length - 1), width: 3, height: 3),
      Paint()..color = markerColor,
    );
  }

  @override
  bool shouldRepaint(covariant _HairlineLinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.markerColor != markerColor ||
        oldDelegate.gridLines != gridLines ||
        oldDelegate.labelAxisWidth != labelAxisWidth ||
        oldDelegate.hoverIndex != hoverIndex;
  }
}

/// 直角悬停浮牌：纯平层级底色 + 1px 细边，等宽字体逐行展示，
/// 首行（日期）前景强调、其余行次级灰。
class _ChartHoverCard extends StatelessWidget {
  const _ChartHoverCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border.all(color: scheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines.length; i++)
              Text(
                lines[i],
                style: TextStyle(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontSize: AppTypography.labelSmall,
                  height: 16 / 11,
                  color: i == 0 ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

TextStyle _axisTextStyle(ColorScheme scheme) {
  return TextStyle(
    fontFamily: AppTypography.monoFamily,
    fontFamilyFallback: AppTypography.monoFamilyFallback,
    fontSize: AppTypography.labelMicro,
    color: scheme.onSurfaceVariant,
  );
}

/// 等宽短日期标签：取 MM-dd。
String _shortDate(String date) {
  if (date.length >= 10) {
    return date.substring(5, 10);
  }
  return date;
}

/// X 轴刻度索引集合：显式 [labelCount] 时均匀抽样；
/// 缺省自适应——短序列（≤8 点）逐日，长序列每 5 日一档，末点固定出现。
List<int> _tickIndices(int dataLength, int? labelCount) {
  if (dataLength == 0) {
    return const <int>[];
  }
  if (labelCount != null) {
    final count = labelCount.clamp(1, dataLength);
    if (count == 1) {
      return const <int>[0];
    }
    return <int>[
      for (var i = 0; i < count; i++)
        (i * (dataLength - 1) / (count - 1)).round(),
    ];
  }
  final step = dataLength > 8 ? 5 : 1;
  return <int>{
      for (var i = 0; i < dataLength; i += step) i,
      dataLength - 1,
    }.toList()
    ..sort();
}
