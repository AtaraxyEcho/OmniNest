import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';

/// 工位列表通用分页条：mono 计数与范围、页码 chip 窗口折叠（≤7 全量，
/// 否则首末页 + 当前页 ±1、缺口省略号）、首页/上页/下页/末页导航钮、
/// 每页条数 MenuAnchor 下拉与页码跳转。Admin 与 Files 列表共用，
/// 样式与交互为唯一事实源。
class WorkstationPaginationBar extends StatefulWidget {
  const WorkstationPaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.totalElements,
    required this.rowsPerPage,
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
    this.busy = false,
    this.rowsPerPageChoices = const [10, 20, 50, 100],
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

  /// 每页条数候选：大视口列表可传更大档位（如 Files 主列表 50/100/200）。
  final List<int> rowsPerPageChoices;

  @override
  State<WorkstationPaginationBar> createState() =>
      _WorkstationPaginationBarState();
}

class _WorkstationPaginationBarState extends State<WorkstationPaginationBar> {
  final TextEditingController _jumpController = TextEditingController();

  @override
  void didUpdateWidget(WorkstationPaginationBar oldWidget) {
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
    // 桌面 28px 紧凑度量；触控密度升为 44px 触达安全区。
    final compact = AppControlTokens.isDesktopDensity;
    final countStyle = TextStyle(
      fontFamily: AppTypography.monoFamily,
      fontFamilyFallback: AppTypography.monoFamilyFallback,
      fontSize: AppTypography.bodySmall,
      color: colors.onSurface,
    );
    final mutedCountStyle = countStyle.copyWith(color: colors.onSurfaceVariant);

    Widget pageChip(int page) {
      final selected = page == current;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: selected ? null : () => widget.onPageChanged(page),
          hoverColor: colors.onSurface.withValues(alpha: 0.06),
          child: Container(
            constraints: BoxConstraints(
              minWidth: compact ? 32 : 44,
              minHeight: compact ? 28 : 44,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color:
                  selected
                      ? colors.surfaceContainerHighest
                      : Colors.transparent,
              border: selected ? Border.all(color: colors.outline) : null,
            ),
            child: Text(
              '${page + 1}',
              style: countStyle.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? colors.onSurface : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    // 首页/上页/下页/末页紧凑图标钮：16px 图标、28/44 视觉边长，
    // 禁用态统一 45% 透明，保证与页码 chip 同一垂直基线。
    Widget navButton(
      IconData icon,
      String tooltip,
      bool enabled,
      VoidCallback onPressed,
    ) {
      final button = IconButton(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 16),
        tooltip: tooltip,
        color: colors.onSurfaceVariant,
        style: IconButton.styleFrom(
          minimumSize: Size.square(compact ? 28 : 44),
          maximumSize: Size.square(compact ? 28 : 44),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
      return enabled ? button : Opacity(opacity: 0.45, child: button);
    }

    // 强制满宽：Wrap 默认收缩为内容宽度，宿主 Column 若未显式
    // start/stretch（如 Files 主列表）会把收缩后的条整体居中——满宽后
    // 条与上方表格同宽，内容恒自左缘排布，与宿主对齐方式解耦。
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        // 单行布局：计数/每页条数与翻页/跳页两组整体靠左（各页统一左
        // 侧语言）；窄屏自动折行，折行组同样左起，不居中不右挂。
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  l10n.paginationTotal(widget.totalElements),
                  style: countStyle,
                ),
                if (widget.totalElements > 0) ...[
                  Text(' · ', style: mutedCountStyle),
                  Text(
                    l10n.paginationRange(rangeStart, rangeEnd),
                    style: mutedCountStyle,
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
                const SizedBox(width: 12),
                _RowsPerPageSelector(
                  value: widget.rowsPerPage,
                  choices: widget.rowsPerPageChoices,
                  onChanged: widget.onRowsPerPageChanged,
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                navButton(
                  Icons.first_page_rounded,
                  l10n.paginationFirst,
                  current > 0,
                  () => widget.onPageChanged(0),
                ),
                navButton(
                  Icons.chevron_left_rounded,
                  l10n.paginationPrev,
                  current > 0,
                  () => widget.onPageChanged(current - 1),
                ),
                for (final page in _visiblePages())
                  page == null
                      ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text('…', style: mutedCountStyle),
                      )
                      : pageChip(page),
                navButton(
                  Icons.chevron_right_rounded,
                  l10n.paginationNext,
                  current < total - 1,
                  () => widget.onPageChanged(current + 1),
                ),
                navButton(
                  Icons.last_page_rounded,
                  l10n.paginationLast,
                  current < total - 1,
                  () => widget.onPageChanged(total - 1),
                ),
                if (total > 5) ...[
                  const SizedBox(width: 4),
                  Text(
                    l10n.paginationJumpTo,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _jumpController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: countStyle,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: compact ? 7 : 13,
                        ),
                        constraints: BoxConstraints(
                          minHeight: compact ? 28 : 44,
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
      ),
    );
  }
}

/// 每页条数紧凑下拉：hairline 直角触发钮 + MenuAnchor 菜单。
///
/// 与分页条其余控件共用同一行高（桌面 28 / 触控 44），替代通用
/// 下拉字段高度，保证整行垂直基线一致。
class _RowsPerPageSelector extends StatefulWidget {
  const _RowsPerPageSelector({
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final int value;
  final List<int> choices;
  final ValueChanged<int> onChanged;

  @override
  State<_RowsPerPageSelector> createState() => _RowsPerPageSelectorState();
}

class _RowsPerPageSelectorState extends State<_RowsPerPageSelector> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final compact = AppControlTokens.isDesktopDensity;
    return MenuAnchor(
      controller: _menu,
      useRootOverlay: true,
      alignmentOffset: const Offset(0, 6),
      builder: (context, controller, child) {
        return Tooltip(
          message: l10n.paginationRowsPerPage,
          child: Material(
            color: colors.surfaceContainerLow,
            child: InkWell(
              onTap: controller.isOpen ? controller.close : controller.open,
              hoverColor: colors.onSurface.withValues(alpha: 0.06),
              child: Container(
                height: compact ? 28 : 44,
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.value}',
                      style: TextStyle(
                        fontFamily: AppTypography.monoFamily,
                        fontFamilyFallback: AppTypography.monoFamilyFallback,
                        fontSize: AppTypography.bodySmall,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      menuChildren: [
        for (final choice in widget.choices)
          MenuItemButton(
            onPressed:
                choice == widget.value
                    ? null
                    : () {
                      _menu.close();
                      widget.onChanged(choice);
                    },
            leadingIcon:
                choice == widget.value
                    ? Icon(Icons.check_rounded, size: 16, color: colors.primary)
                    : const SizedBox(width: 16),
            child: Text('$choice'),
          ),
      ],
    );
  }
}
