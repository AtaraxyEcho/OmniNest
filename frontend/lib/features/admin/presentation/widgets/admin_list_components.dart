/// Admin 通用列表组件集：筛选栏、数据表格、分页条、状态标签。
///
/// 四个列表页（会话/任务/日志/配置）共用同一套组件，保证交互
/// 与视觉词汇一致；行高固定以支持"横向滚动 + 右侧固定操作列"。
library;

import 'dart:math' as math;

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';

export 'package:omninest/app/widgets/app_dropdown.dart';

/// 状态标签语义色。
enum AdminTagTone { success, warning, error, info, neutral }

/// 语义色对应的标签配色：前景取 Admin 主题扩展的语义基色，背景为
/// 前景低透明底色，附同色描边，保证明暗两套主题下的可读性一致。
extension AdminTagToneColor on AdminTagTone {
  Color _base(BuildContext context) {
    final adminColors = context.adminColors;
    return switch (this) {
      AdminTagTone.success => adminColors.success,
      AdminTagTone.warning => adminColors.warning,
      AdminTagTone.error => adminColors.error,
      AdminTagTone.info => adminColors.info,
      AdminTagTone.neutral => adminColors.onSurfaceVariant,
    };
  }

  Color foreground(BuildContext context) => _base(context);

  Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? _base(context).withValues(alpha: 0.16)
          : _base(context).withValues(alpha: 0.1);

  Color border(BuildContext context) => _base(context).withValues(alpha: 0.28);
}

/// 语义化状态标签：状态点 + 文本，胶囊描边样式。
class AdminStatusTag extends StatelessWidget {
  const AdminStatusTag({
    required this.label,
    this.tone = AdminTagTone.neutral,
    super.key,
  });

  final String label;
  final AdminTagTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone.foreground(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: tone.background(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 列表列定义。
class AdminListColumn {
  const AdminListColumn({
    required this.key,
    required this.label,
    this.flex = 1,
    this.minWidth,
    this.sortable = false,
    this.numeric = false,
  });

  /// 列标识（排序回调与取值键共用）。
  final String key;
  final String label;

  /// 弹性宽度权重；设置 [minWidth] 时按最小宽度参与横向滚动分配。
  final int flex;
  final double? minWidth;
  final bool sortable;
  final bool numeric;
}

/// 单行省略文本单元格：内容被列宽截断时，悬停以 Tooltip 展示完整内容；
/// 未截断时不挂 Tooltip，避免完整可见的行也弹重复提示。
class AdminCellText extends StatefulWidget {
  const AdminCellText(this.text, {this.style, this.tooltipMessage, super.key});

  final String text;
  final TextStyle? style;

  /// 悬停展示的完整文案；缺省为 [text] 本身。需要附带额外信息
  /// （如堆栈摘要）时传入，此时不要再在外层包 Tooltip，避免嵌套双气泡。
  final String? tooltipMessage;

  @override
  State<AdminCellText> createState() => _AdminCellTextState();
}

class _AdminCellTextState extends State<AdminCellText> {
  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final defaultStyle = DefaultTextStyle.of(context).style;
        final painter = TextPainter(
          text: TextSpan(
            text: widget.text,
            style:
                widget.style == null
                    ? defaultStyle
                    : defaultStyle.merge(widget.style),
          ),
          textScaler:
              MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout(maxWidth: constraints.maxWidth);
        final overflowed = painter.didExceedMaxLines;
        painter.dispose();
        // 富文案（如附带堆栈）包含单元格之外的信息，无论是否截断都保持可悬停；
        // 普通单元格仅在截断时挂 Tooltip。
        final richMessage =
            widget.tooltipMessage != null &&
            widget.tooltipMessage != widget.text;
        if (!overflowed && !richMessage) {
          return text;
        }
        return Tooltip(
          message: widget.tooltipMessage ?? widget.text,
          waitDuration: const Duration(milliseconds: 300),
          child: text,
        );
      },
    );
  }
}

/// 服务端排序状态。
class AdminListSort {
  const AdminListSort({required this.columnKey, required this.ascending});

  final String columnKey;
  final bool ascending;
}

/// 筛选栏：关键词 + 组合筛选控件 + 可选的展开/收起。
class AdminFilterBar extends StatefulWidget {
  const AdminFilterBar({
    required this.keyword,
    required this.onKeywordChanged,
    this.filterChildren = const <Widget>[],
    this.trailing,
    this.collapsible = false,
    this.expanded = true,
    this.onToggleExpanded,
    super.key,
  });

  final String keyword;
  final ValueChanged<String> onKeywordChanged;
  final List<Widget> filterChildren;
  final List<Widget>? trailing;

  /// 是否提供展开/收起能力；收起时仅显示关键词与前两个筛选项。
  final bool collapsible;
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  @override
  State<AdminFilterBar> createState() => _AdminFilterBarState();
}

class _AdminFilterBarState extends State<AdminFilterBar> {
  /// 关键词控制器由本状态持有：每次 build 都新建 TextEditingController 会在
  /// 输入触发的重建中重置选区，中文输入法下光标跳回开头。
  late final TextEditingController _keywordController = TextEditingController(
    text: widget.keyword,
  );

  @override
  void didUpdateWidget(covariant AdminFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyword != widget.keyword &&
        _keywordController.text != widget.keyword) {
      _keywordController.value = TextEditingValue(
        text: widget.keyword,
        selection: TextSelection.collapsed(offset: widget.keyword.length),
      );
    }
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  // 转发宿主字段，避免改写既有 build 主体。
  String get keyword => widget.keyword;
  ValueChanged<String> get onKeywordChanged => widget.onKeywordChanged;
  List<Widget> get filterChildren => widget.filterChildren;
  List<Widget>? get trailing => widget.trailing;
  bool get collapsible => widget.collapsible;
  bool get expanded => widget.expanded;
  VoidCallback? get onToggleExpanded => widget.onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final visibleFilters =
        collapsible && !expanded
            ? filterChildren.take(2).toList()
            : filterChildren;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: AppControlTokens.searchFieldWidth,
          child: TextField(
            controller: _keywordController,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: AppLocalizations.of(context).adminSearchHint,
            ),
            onSubmitted: onKeywordChanged,
            onChanged: onKeywordChanged,
          ),
        ),
        ...visibleFilters,
        if (collapsible)
          TextButton.icon(
            onPressed: onToggleExpanded,
            icon: Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18,
            ),
            label: Text(
              expanded
                  ? AppLocalizations.of(context).adminListCollapseFilters
                  : AppLocalizations.of(context).adminListExpandFilters,
            ),
          ),
        if (trailing != null) ...trailing!,
      ],
    );
  }
}

/// 高密度数据表格：固定行高、横向滚动、右侧固定操作列、可选多选列、
/// 可排序表头。内部基于 data_table_2 的 [DataTable2]：列宽分配、横向
/// 滚动与行 hover/选中态由其维护，本类只保留页面侧的稳定 API。
class AdminDataTable extends StatelessWidget {
  const AdminDataTable({
    required this.columns,
    required this.rowCount,
    required this.rowCellsBuilder,
    this.actionsBuilder,
    this.showCheckboxes = false,
    this.isChecked,
    this.onRowCheck,
    this.isCheckDisabled,
    this.allChecked = false,
    this.someChecked = false,
    this.onCheckAll,
    this.sort,
    this.onSort,
    this.showIndex = false,
    this.indexBase = 0,
    this.minTableWidth = 860,
    this.maxTableWidth,
    this.actionColumnWidth = 168,
    this.rowHeight = 48,
    this.emptyState,
    this.onRowTap,
    super.key,
  }) : assert(
         !showCheckboxes || (isChecked != null && onRowCheck != null),
         'showCheckboxes 需要同时提供 isChecked 与 onRowCheck',
       );

  final List<AdminListColumn> columns;
  final int rowCount;
  final List<Widget> Function(BuildContext context, int index) rowCellsBuilder;

  /// 操作列内容（每行一组操作控件）；为空时不渲染操作列。
  final List<Widget> Function(BuildContext context, int index)? actionsBuilder;

  final bool showCheckboxes;
  final bool Function(int index)? isChecked;
  final void Function(int index, bool value)? onRowCheck;

  /// 行复选框禁用判定（如不可执行批量操作的行）；为空时全部可勾选。
  final bool Function(int index)? isCheckDisabled;

  final bool allChecked;
  final bool someChecked;
  final void Function(bool value)? onCheckAll;

  final AdminListSort? sort;
  final void Function(String columnKey, bool ascending)? onSort;

  /// 是否在首列渲染序号列。
  final bool showIndex;

  /// 序号基数：服务端分页下传入（页码 × 每页条数），行号 = 基数 + 行序 + 1。
  final int indexBase;

  /// 主表最小宽度（低于该宽度表格内部出现横向滚动条）。
  final double minTableWidth;

  /// 主表最大宽度；超出时表格居中收窄，避免宽屏下唯一弹性列被拉得过长。
  final double? maxTableWidth;
  final double actionColumnWidth;
  final double rowHeight;
  final Widget? emptyState;

  /// 行点击回调（如主从布局的选中）；为空时行不可点。
  final void Function(int index)? onRowTap;

  bool get _hasActionColumn => actionsBuilder != null;

  /// 复选框列固定宽度。
  static const _checkColumnWidth = 48.0;

  /// 序号列固定宽度。
  static const _indexColumnWidth = 64.0;

  @override
  Widget build(BuildContext context) {
    if (rowCount == 0 && emptyState != null) {
      return emptyState!;
    }
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    final leadingCount = (showCheckboxes ? 1 : 0) + (showIndex ? 1 : 0);
    int? sortIndex;
    if (sort != null) {
      final position = columns.indexWhere(
        (column) => column.key == sort!.columnKey,
      );
      if (position >= 0 && columns[position].sortable) {
        sortIndex = position + leadingCount;
      }
    }

    var fixedWidthTotal = 0.0;
    for (final column in columns) {
      if (column.minWidth != null) {
        fixedWidthTotal += column.minWidth!;
      }
    }

    final dataTable = DataTable2(
      columns: [
        if (showCheckboxes)
          DataColumn2(
            fixedWidth: _checkColumnWidth,
            label: Center(
              child: Checkbox(
                tristate: true,
                value: allChecked ? true : (someChecked ? null : false),
                onChanged:
                    onCheckAll == null
                        ? null
                        : (value) => onCheckAll!(value == true),
              ),
            ),
          ),
        if (showIndex)
          DataColumn2(
            fixedWidth: _indexColumnWidth,
            label: Text(l10n.adminListIndex, style: _headerStyle(context)),
          ),
        for (final column in columns)
          DataColumn2(
            fixedWidth: column.minWidth,
            size: _columnSizeFor(column.flex),
            numeric: column.numeric,
            label: Text(column.label, style: _headerStyle(context)),
            onSort:
                column.sortable && onSort != null
                    ? (index, ascending) => onSort!(column.key, ascending)
                    : null,
          ),
      ],
      rows: [
        for (var i = 0; i < rowCount; i++)
          DataRow2(
            onTap: onRowTap == null ? null : () => onRowTap!(i),
            selected: showCheckboxes && (isChecked?.call(i) ?? false),
            cells: [
              if (showCheckboxes)
                DataCell(
                  SizedBox(
                    width: _checkColumnWidth,
                    child: Center(
                      child: Checkbox(
                        value: isChecked!(i),
                        onChanged:
                            (isCheckDisabled?.call(i) ?? false)
                                ? null
                                : (value) => onRowCheck!(i, value ?? false),
                      ),
                    ),
                  ),
                ),
              if (showIndex)
                DataCell(
                  Text(
                    '${indexBase + i + 1}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final cell in rowCellsBuilder(context, i)) DataCell(cell),
            ],
          ),
      ],
      minWidth: math.max(minTableWidth, fixedWidthTotal),
      headingRowHeight: 44,
      dataRowHeight: rowHeight,
      columnSpacing: 24,
      horizontalMargin: 12,
      dividerThickness: 1,
      smRatio: 0.5,
      lmRatio: 1.5,
      sortColumnIndex: sortIndex,
      sortAscending: sort?.ascending ?? false,
      sortArrowIconColor: colors.primary,
      showCheckboxColumn: false,
      showHeadingCheckBox: false,
    );

    // DataTable2 内部使用 Flexible(tight) 布局，必须给定有界高度；
    // 其分隔线绘制在行边界上不占用高度，总高 = 表头 44 + 行数 × 行高。
    // ClipRRect 保证表头与行背景按圆角裁切。
    final tableHeight = 44.0 + rowCount * rowHeight;
    final boundedTable = SizedBox(
      height: tableHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: dataTable,
      ),
    );
    Widget tableArea = boundedTable;
    if (_hasActionColumn) {
      tableArea = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: boundedTable),
          Container(
            width: actionColumnWidth,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: colors.outlineVariant)),
            ),
            child: _buildActionColumn(context, colors),
          ),
        ],
      );
    }
    // 边框放在 foregroundDecoration：行背景为不透明色，若用 decoration
    // 绘制边框会被行背景盖住，导致边线与圆角显示不全。
    Widget result = Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: tableArea,
    );
    if (maxTableWidth != null) {
      result = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxTableWidth!),
          child: result,
        ),
      );
    }
    return result;
  }

  /// flex 数值映射到 DataTable2 的 S/M/L 档位；配合 smRatio 0.5、
  /// lmRatio 1.5 保持 1:2:3 的既有列宽比例。
  ColumnSize _columnSizeFor(int flex) {
    if (flex <= 1) {
      return ColumnSize.S;
    }
    if (flex == 2) {
      return ColumnSize.M;
    }
    return ColumnSize.L;
  }

  TextStyle? _headerStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      );

  /// 右侧固定操作列：表头标签与每行操作内容。分隔线绘制在行顶边（除
  /// 首行外，不占高度），与主表 DataTable2 绘制在行边界上的分隔线处于
  /// 同一 Y 坐标，保证横贯整表宽度的连续基线。
  Widget _buildActionColumn(BuildContext context, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 44,
          child: Align(
            child: Text(
              AppLocalizations.of(context).adminListActions,
              style: _headerStyle(context),
            ),
          ),
        ),
        for (var i = 0; i < rowCount; i++)
          SizedBox(
            height: rowHeight,
            child: Container(
              decoration:
                  i == 0
                      ? null
                      : BoxDecoration(
                        border: Border(
                          top: BorderSide(color: colors.outlineVariant),
                        ),
                      ),
              child: Align(
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actionsBuilder!(context, i),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 列表分页控件：总条数与当前范围、每页条数选择、首页/末页与上/下页、
/// 数字页码（总页数 > 7 时折叠省略号）、页码跳转（总页数 > 5 时出现）
/// 与翻页加载状态。布局用 [Wrap] 承载，窄屏自动折行不溢出。
class AdminListPaginationBar extends StatefulWidget {
  const AdminListPaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.totalElements,
    required this.rowsPerPage,
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
    this.busy = false,
    super.key,
  });

  /// 当前页码（0 基）。
  final int currentPage;
  final int totalPages;
  final int totalElements;
  final int rowsPerPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRowsPerPageChanged;

  /// 翻页/筛选刷新中：数据仍在展示，控件上显示细进度与转圈提示。
  final bool busy;

  static const _rowsPerPageChoices = [10, 20, 50, 100];

  @override
  State<AdminListPaginationBar> createState() => _AdminListPaginationBarState();
}

class _AdminListPaginationBarState extends State<AdminListPaginationBar> {
  final TextEditingController _jumpController = TextEditingController();

  @override
  void didUpdateWidget(AdminListPaginationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage) {
      _jumpController.clear();
    }
  }

  @override
  void dispose() {
    _jumpController.dispose();
    super.dispose();
  }

  /// 计算可见页码（0 基）：总页数 ≤ 7 全量展示；否则固定首末页与当前页
  /// ±1，缺口以 null（省略号）填充。
  List<int?> _visiblePages() {
    final total = widget.totalPages;
    if (total <= 0) {
      return const <int?>[];
    }
    final current = widget.currentPage.clamp(0, total - 1);
    if (total <= 7) {
      return List<int?>.generate(total, (index) => index);
    }
    final marks =
        <int>{
            0,
            total - 1,
            current - 1,
            current,
            current + 1,
          }.where((page) => page >= 0 && page < total).toList()
          ..sort();
    final result = <int?>[];
    for (var i = 0; i < marks.length; i++) {
      if (i > 0 && marks[i] - marks[i - 1] > 1) {
        result.add(null);
      }
      result.add(marks[i]);
    }
    return result;
  }

  void _submitJump(String value) {
    final target = int.tryParse(value.trim());
    if (target == null) {
      return;
    }
    final clamped = (target - 1).clamp(0, widget.totalPages - 1);
    widget.onPageChanged(clamped);
    _jumpController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final total = widget.totalPages;
    final current = total <= 0 ? 0 : widget.currentPage.clamp(0, total - 1);
    final rangeStart = current * widget.rowsPerPage + 1;
    final rangeEnd = ((current + 1) * widget.rowsPerPage).clamp(
      0,
      widget.totalElements,
    );
    final disabledColor = colors.onSurfaceVariant;

    Widget pageChip(int page) {
      final selected = page == current;
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selected ? null : () => widget.onPageChanged(page),
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? colors.primary.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${page + 1}',
            style: TextStyle(
              color: selected ? colors.primary : colors.onSurface,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.adminListTotalCount(widget.totalElements),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (widget.totalElements > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      l10n.adminListRange(rangeStart, rangeEnd),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (widget.busy) ...[
                    const SizedBox(width: 8),
                    SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 92,
                    child: AppDropdown<int>(
                      dense: true,
                      value: widget.rowsPerPage,
                      items: [
                        for (final choice
                            in AdminListPaginationBar._rowsPerPageChoices)
                          AppDropdownItem(value: choice, label: '$choice'),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          widget.onRowsPerPageChanged(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed:
                        current > 0 ? () => widget.onPageChanged(0) : null,
                    style: IconButton.styleFrom(
                      minimumSize: Size.square(AppControlTokens.iconButtonSize),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.first_page_rounded),
                    tooltip: l10n.adminListFirstPage,
                    color: disabledColor,
                  ),
                  IconButton(
                    onPressed:
                        current > 0
                            ? () => widget.onPageChanged(current - 1)
                            : null,
                    style: IconButton.styleFrom(
                      minimumSize: Size.square(AppControlTokens.iconButtonSize),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: l10n.adminListPrevPage,
                    color: disabledColor,
                  ),
                  for (final page in _visiblePages())
                    page == null
                        ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            '…',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: disabledColor),
                          ),
                        )
                        : pageChip(page),
                  IconButton(
                    onPressed:
                        current < total - 1
                            ? () => widget.onPageChanged(current + 1)
                            : null,
                    style: IconButton.styleFrom(
                      minimumSize: Size.square(AppControlTokens.iconButtonSize),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: l10n.adminListNextPage,
                    color: disabledColor,
                  ),
                  IconButton(
                    onPressed:
                        current < total - 1
                            ? () => widget.onPageChanged(total - 1)
                            : null,
                    style: IconButton.styleFrom(
                      minimumSize: Size.square(AppControlTokens.iconButtonSize),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.last_page_rounded),
                    tooltip: l10n.adminListLastPage,
                    color: disabledColor,
                  ),
                  if (total > 5) ...[
                    const SizedBox(width: 4),
                    Text(
                      l10n.adminListJumpTo,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: _jumpController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: Theme.of(context).textTheme.bodySmall,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          suffixText:
                              l10n.adminListPageUnit.isEmpty
                                  ? null
                                  : l10n.adminListPageUnit,
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 0,
                            minHeight: 0,
                          ),
                        ),
                        onSubmitted: _submitJump,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 列表分区骨架：无卡片容器的标准列表分区。
///
/// 结构为标题行（标题 + 副标题 + 操作区）、可选筛选行与内容区（表格 +
/// 分页由调用方传入）。列表页统一使用本骨架，禁止卡片套列表。
class AdminTableSection extends StatelessWidget {
  const AdminTableSection({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing = const <Widget>[],
    this.filters = const <Widget>[],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> trailing;
  final List<Widget> filters;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing.isNotEmpty)
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: trailing,
              ),
          ],
        ),
        if (filters.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: filters),
        ],
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

/// 列表空态：左对齐行式提示（符合 admin 页面布局惯例）。
class AdminListEmptyState extends StatelessWidget {
  const AdminListEmptyState({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// 列表加载指示：居中转圈，不再渲染与表头同形的骨架行。
class AdminListSkeleton extends StatelessWidget {
  const AdminListSkeleton({this.rows = 8, super.key});

  // ignore: unused_field
  final int rows;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
