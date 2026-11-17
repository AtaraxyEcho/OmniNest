import 'package:flutter/material.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_select.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 样例 `.pager` / `.pg-b`：32×32、圆角 9 的方形翻页按钮，
/// First / Prev / 数字页码（超过 7 页折叠成 `…`）/ Next / Last，
/// 右侧可选「每页行数」下拉（`[10, 20, 50]`）。
class DesktopPager extends StatelessWidget {
  const DesktopPager({
    required this.page,
    required this.totalPages,
    required this.onPageChanged,
    this.summary,
    this.pageSize,
    this.pageSizeOptions = const <int>[10, 20, 50],
    this.onPageSizeChanged,
    super.key,
  });

  /// 从 0 开始的页码，与各控制器的 `state.page` 一致。
  final int page;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  /// 左侧说明文字（`{count} total` 之类），为空时不留白。
  final String? summary;

  /// 每页行数；与 [onPageSizeChanged] 同时给出才显示下拉。
  final int? pageSize;
  final List<int> pageSizeOptions;
  final ValueChanged<int>? onPageSizeChanged;

  /// 超过这个页数才折叠，否则一屏放得下就全列。
  static const int _foldAfter = 7;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final total = totalPages < 1 ? 1 : totalPages;
    final current = page.clamp(0, total - 1);
    final atStart = current <= 0;
    final atEnd = current + 1 >= total;
    final size = pageSize;
    final onSize = onPageSizeChanged;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄容器里先牺牲左说明文字，翻页按钮始终可达。
        final showSummary =
            summary != null && constraints.maxWidth >= kPagerWithSummaryWidth;
        return Container(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 2),
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: skin.line)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 10,
            children: [
              if (showSummary) _info(summary!, skin),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PagerButton(
                    icon: DesktopIcons.firstPage,
                    tooltip: l10n.paginationFirst,
                    onPressed: atStart ? null : () => onPageChanged(0),
                  ),
                  const SizedBox(width: kPagerGap),
                  _PagerButton(
                    icon: DesktopIcons.left,
                    tooltip: l10n.paginationPrev,
                    onPressed:
                        atStart ? null : () => onPageChanged(current - 1),
                  ),
                  for (final entry in pageSlots(current, total)) ...[
                    const SizedBox(width: kPagerGap),
                    if (entry == null)
                      SizedBox(
                        width: kPagerButtonSize,
                        height: kPagerButtonSize,
                        child: Center(
                          child: Text(
                            '…',
                            style: DesktopType.caption(skin.text3),
                          ),
                        ),
                      )
                    else
                      _PagerButton(
                        label: '${entry + 1}',
                        tooltip: l10n.paginationJumpTo,
                        active: entry == current,
                        inGroup: true,
                        onPressed: () => onPageChanged(entry),
                      ),
                  ],
                  const SizedBox(width: kPagerGap),
                  _PagerButton(
                    icon: DesktopIcons.chevron,
                    tooltip: l10n.paginationNext,
                    onPressed: atEnd ? null : () => onPageChanged(current + 1),
                  ),
                  const SizedBox(width: kPagerGap),
                  _PagerButton(
                    icon: DesktopIcons.lastPage,
                    tooltip: l10n.paginationLast,
                    onPressed: atEnd ? null : () => onPageChanged(total - 1),
                  ),
                ],
              ),
              // 样例把「每页行数」放在按钮组右侧。
              if (size != null && onSize != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.paginationRows,
                      style: DesktopType.caption(skin.text3),
                    ),
                    const SizedBox(width: 8),
                    DesktopSelect<int>(
                      value: size,
                      variant: DesktopSelectVariant.small,
                      width: 76,
                      options: [
                        for (final option in pageSizeOptions)
                          DesktopSelectOption(value: option, label: '$option'),
                      ],
                      onChanged: onSize,
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _info(String text, DesktopSkin skin) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: DesktopType.caption(skin.text3),
  );

  /// 页码槽位：首末页与当前页 ±1 必显，间隔处插一个 `null` 表示 `…`。
  /// 总页数不超过 [_foldAfter] 时全部直出，`…` 反而更难读。
  static List<int?> pageSlots(int current, int total) {
    if (total <= _foldAfter) {
      return [for (var i = 0; i < total; i++) i];
    }
    final keep = <int>{0, total - 1, current};
    if (current - 1 > 0) {
      keep.add(current - 1);
    }
    if (current + 1 < total - 1) {
      keep.add(current + 1);
    }
    final ordered = keep.toList()..sort();
    final slots = <int?>[];
    for (var i = 0; i < ordered.length; i++) {
      if (i > 0 && ordered[i] - ordered[i - 1] > 1) {
        slots.add(null);
      }
      slots.add(ordered[i]);
    }
    return slots;
  }
}

/// `.pg-b` 边长。
const double kPagerButtonSize = 32;

/// 翻页按钮之间的间距。
const double kPagerGap = 4;

/// 低于这个宽度就收起左侧说明文字（按钮组本身约需 320）。
const double kPagerWithSummaryWidth = 620;

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    this.label,
    this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.inGroup = false,
  });

  final String? label;
  final IconData? icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  /// 数字页码成组互斥；首/末/前后翻页不属于这组。
  final bool inGroup;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final enabled = onPressed != null;
    final foreground = active ? skin.accentInk : skin.text2;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        selected: inGroup ? active : null,
        inMutuallyExclusiveGroup: inGroup,
        enabled: enabled,
        child: DesktopHover(
          enabled: enabled,
          builder:
              (context, hovered) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPressed,
                // 样例 `more.css:29`：min-width 32 + 左右 6 内距、12.5/550、
                // 透明 1px 描边；禁用整颗降到 30%。
                child: Opacity(
                  opacity: enabled ? 1 : 0.3,
                  child: AnimatedContainer(
                    duration: MotionToken.reduced(context, MotionToken.fast),
                    curve: MotionToken.curve,
                    constraints: const BoxConstraints(
                      minWidth: kPagerButtonSize,
                    ),
                    height: kPagerButtonSize,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color:
                          active
                              ? skin.accent
                              : hovered
                              ? skin.raise2
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        DesktopMetrics.radiusIconButton,
                      ),
                      border: Border.all(color: Colors.transparent),
                    ),
                    child: Center(
                      child:
                          icon != null
                              ? Icon(icon, size: 14, color: foreground)
                              : Text(
                                label ?? '',
                                style: DesktopType.secondary(
                                  foreground,
                                ).copyWith(fontWeight: FontWeight.w500),
                              ),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }
}
