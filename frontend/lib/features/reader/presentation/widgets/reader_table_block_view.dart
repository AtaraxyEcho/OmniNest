import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 表格块的分行渲染：首帧只构建一批行，其余行在随后的帧里补齐。
///
/// 表格放在横向滚动容器里，行不折行、行高由测量侧唯一确定，所以没构建的行可以按
/// 等高预留空位：整表占据的高度从头到尾等于 `measureBlockHeight(TableBlock)`，
/// 补齐过程既不改动滚动高度表，也不改动字符偏移↔像素映射。
///
/// 这里拆开的是单帧构建量，不是视口虚拟化：同一个组件还要服务翻页装页与没有高度
/// 表的无界上下文，那两处拿不到有界高度，嵌套纵向滚动容器放不下。
///
/// 行数不超过首帧预算的表走与原实现逐层相同的控件树，不多一个布局节点，也不测行高。
class ReaderTableBlockView extends StatefulWidget {
  const ReaderTableBlockView({
    required this.rows,
    required this.settings,
    required this.spanBuilder,
    super.key,
  });

  /// 首帧构建的行数：够铺满一屏行位，不必为视口外的几百行付同一次构建。
  static const int firstFrameRowBudget = 32;

  /// 首帧之后每帧补齐的行数。
  static const int rowFillStep = 32;

  final List<TableRowData> rows;
  final ReaderViewSettings settings;

  /// 单元格行内片段的构造：链接手势与行内样式仍由块渲染侧持有，本组件只管排版。
  final InlineSpan Function(ReaderInlineSpan span, {FontWeight? weight})
  spanBuilder;

  @override
  State<ReaderTableBlockView> createState() => _ReaderTableBlockViewState();
}

class _ReaderTableBlockViewState extends State<ReaderTableBlockView> {
  /// 从第 i 行起（含）到表尾还需要预留的高度，末位恒为 0。
  List<double> _tailHeights = const [0.0];
  List<TableRowData>? _measuredRows;
  double _measuredTextScale = 0.0;
  int _builtRows = 0;
  bool _fillScheduled = false;

  @override
  void initState() {
    super.initState();
    _resetBuiltRows();
  }

  @override
  void didUpdateWidget(ReaderTableBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rows.length != widget.rows.length) {
      _resetBuiltRows();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final built = math.min(_builtRows, widget.rows.length);
    const padding = EdgeInsets.symmetric(
      vertical: ReaderContentBlockItem.tableVerticalPadding,
    );
    if (built >= widget.rows.length) {
      return Padding(padding: padding, child: _rows(built, 0.0));
    }
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 纵向已被定高槽位夹住时（滚动列表按高度表给了 itemExtent），空位槽位
          // 自己留着：再预留就得为整表测一遍行高，白付一遍 O(行数)。
          final tail =
              constraints.hasTightHeight ? 0.0 : _tailHeightFrom(built);
          return _rows(built, tail);
        },
      ),
    );
  }

  Widget _rows(int built, double tail) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < built; index++) _row(widget.rows[index]),
          if (tail > 0.0) SizedBox(height: tail),
        ],
      ),
    );
  }

  void _resetBuiltRows() {
    _builtRows = math.min(
      widget.rows.length,
      ReaderTableBlockView.firstFrameRowBudget,
    );
    _scheduleFill();
  }

  double _tailHeightFrom(int built) {
    _ensureRowHeights();
    if (_tailHeights.length <= built) {
      return 0.0;
    }
    return _tailHeights[built];
  }

  /// 预留位要用的行高表：只在行列表或文字缩放真的变了时重算。
  ///
  /// 补帧每帧都要 build，每次重算就为一屏行位白测整表几百个 TextPainter。
  /// 这里只写这份私有缓存，不改可见状态，所以按需在 build 路径里取。
  void _ensureRowHeights() {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    if (identical(_measuredRows, widget.rows) &&
        _measuredTextScale == textScale) {
      return;
    }
    final heights = ReaderPaginationEngine.tableRowHeights(
      widget.rows,
      widget.settings,
      textScale,
    );
    final tails = List<double>.filled(heights.length + 1, 0.0);
    for (var index = heights.length - 1; index >= 0; index--) {
      tails[index] = tails[index + 1] + heights[index];
    }
    _measuredRows = widget.rows;
    _measuredTextScale = textScale;
    _tailHeights = tails;
  }

  void _scheduleFill() {
    if (_fillScheduled || _builtRows >= widget.rows.length) {
      return;
    }
    _fillScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fillScheduled = false;
      if (!mounted) {
        return;
      }
      setState(() {
        _builtRows = math.min(
          _builtRows + ReaderTableBlockView.rowFillStep,
          widget.rows.length,
        );
      });
      _scheduleFill();
    });
  }

  Widget _row(TableRowData row) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: widget.settings.onSurfaceVariantColor.withValues(
              alpha: 0.15,
            ),
            width: ReaderContentBlockItem.tableRowBorderWidth,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final cell in row.cells)
            Container(
              constraints: const BoxConstraints(minWidth: 60),
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: ReaderContentBlockItem.tableCellVerticalPadding,
              ),
              decoration: BoxDecoration(
                color:
                    row.isHeader
                        ? widget.settings.onSurfaceVariantColor.withValues(
                          alpha: 0.08,
                        )
                        : null,
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    for (final span in cell)
                      widget.spanBuilder(
                        span,
                        weight:
                            row.isHeader
                                ? FontWeight.w700
                                : span.isBold
                                ? FontWeight.w700
                                : FontWeight.w400,
                      ),
                  ],
                ),
                strutStyle: widget.settings.bodyStrutStyle(),
              ),
            ),
        ],
      ),
    );
  }
}
