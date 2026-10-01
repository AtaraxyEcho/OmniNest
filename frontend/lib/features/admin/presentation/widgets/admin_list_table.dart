part of 'admin_list_components.dart';

/// 高密度数据表（AdminDataTable）：列定义、固定操作列与多选/排序。

/// 操作列行内图标动作：对齐 Files 工位行内操作的形态 —— 28×28 纯平
/// 悬停块（无涟漪）、14px 图标、默认灰阶、悬停提亮为前景色；语义色
/// 动作（如销毁类绯红）固定着色。[onTap] 为空呈禁用态，[busy] 以
/// 14px 进度圈占位且不响应点击。
class AdminRowIconAction extends StatefulWidget {
  const AdminRowIconAction({
    required this.tooltip,
    required this.icon,
    this.onTap,
    this.color,
    this.busy = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  /// 固定语义色；为空时走默认灰阶悬停逻辑。
  final Color? color;

  final bool busy;

  @override
  State<AdminRowIconAction> createState() => _AdminRowIconActionState();
}

class _AdminRowIconActionState extends State<AdminRowIconAction> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final adminColors = context.adminColors;
    final enabled = widget.onTap != null && !widget.busy;
    final hovering = _hovering && enabled;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: enabled ? (_) => setState(() => _hovering = true) : null,
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.busy ? null : widget.onTap,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            color:
                hovering
                    ? adminColors.surfaceContainerHighest
                    : Colors.transparent,
            child:
                widget.busy
                    ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Icon(
                      widget.icon,
                      size: 14,
                      color:
                          widget.color ??
                          (enabled
                              ? (hovering
                                  ? adminColors.onSurface
                                  : adminColors.onSurfaceVariant)
                              : adminColors.onSurfaceVariant.withValues(
                                alpha: 0.45,
                              )),
                    ),
          ),
        ),
      ),
    );
  }
}

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
    this.checkDisabledTooltip,
    this.allChecked = false,
    this.someChecked = false,
    this.onCheckAll,
    this.sort,
    this.onSort,
    this.showIndex = false,
    this.indexBase = 0,
    this.minTableWidth = 860,
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

  /// 禁用行复选框的悬停说明；返回非空文案时在禁用复选框上挂 Tooltip，
  /// 解释该行为何不可勾选。
  final String? Function(int index)? checkDisabledTooltip;

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
            // 不覆写样式：表头文字由皮肤 dataTableTheme 统一为 mono 小标。
            label: Text(l10n.adminListIndex),
          ),
        for (final column in columns)
          DataColumn2(
            fixedWidth: column.minWidth,
            size: _columnSizeFor(column.flex),
            numeric: column.numeric,
            label: Text(column.label),
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
              if (showCheckboxes) _buildCheckCell(i),
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
    final tableHeight = 44.0 + rowCount * rowHeight;
    final boundedTable = SizedBox(height: tableHeight, child: dataTable);
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
    // 绘制边框会被行背景盖住，导致边线显示不全。直角形态无需裁切。
    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
      ),
      child: tableArea,
    );
  }

  /// 行首复选框单元格：禁用行可附带悬停说明，解释为何不可勾选。
  DataCell _buildCheckCell(int index) {
    final disabled = isCheckDisabled?.call(index) ?? false;
    Widget checkbox = Checkbox(
      value: isChecked!(index),
      onChanged:
          disabled ? null : (value) => onRowCheck!(index, value ?? false),
    );
    final reason = disabled ? checkDisabledTooltip?.call(index) : null;
    if (reason != null && reason.isNotEmpty) {
      checkbox = Tooltip(message: reason, child: checkbox);
    }
    return DataCell(
      SizedBox(width: _checkColumnWidth, child: Center(child: checkbox)),
    );
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

  /// 操作列表头为 DataTable2 之外的定制列，主题 headingTextStyle 不会
  /// 自动生效：按 Files 工位表头规格复刻 —— mono 小标、1.2 字距、w500、
  /// 左对齐并共享 10px 水平起点。
  TextStyle _headerStyle(BuildContext context) {
    final theme = Theme.of(context);
    return TextStyle(
      fontFamily: AppTypography.monoFamily,
      fontFamilyFallback: AppTypography.monoFamilyFallback,
      fontSize: theme.textTheme.labelSmall?.fontSize,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  /// 右侧固定操作列：表头标签与每行操作内容。分隔线绘制在行顶边（除
  /// 首行外，不占高度），与主表 DataTable2 绘制在行边界上的分隔线处于
  /// 同一 Y 坐标，保证横贯整表宽度的连续基线。
  Widget _buildActionColumn(BuildContext context, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppLocalizations.of(context).adminListActions,
                style: _headerStyle(context),
              ),
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actionsBuilder!(context, i),
                  ),
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
