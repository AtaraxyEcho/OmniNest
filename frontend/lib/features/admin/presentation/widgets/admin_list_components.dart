/// Admin 通用列表组件集：筛选栏、数据表格、分页条、状态标签。
///
/// 四个列表页（会话/任务/日志/配置）共用同一套组件，保证交互
/// 与视觉词汇一致；行高固定以支持"横向滚动 + 右侧固定操作列"。
library;

import 'dart:math' as math;

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';

export 'package:omninest/app/widgets/app_dropdown.dart';

part 'admin_list_table.dart';
part 'admin_list_pagination.dart';

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

/// 语义化状态标签：状态点 + 文本，直角描边样式。
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
