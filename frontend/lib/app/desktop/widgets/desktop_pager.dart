import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_focus_outline.dart';
import 'package:omninest/app/desktop/widgets/desktop_select.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 通用桌面分页组件（对照样例 `src/desktop/list.tsx:28-44` 与 `more.css:27`）。
///
/// 左侧显示当前区间与总数，中间提供首页 / 上一页 / 智能省略页码 / 下一页 / 末页，
/// 右侧在传入 [onPageSizeChanged] 时显示每页条数切换。
class DesktopPager extends StatelessWidget {
  const DesktopPager({
    required this.page, // 0-based current page
    required this.pageSize,
    required this.totalItems,
    required this.onPageChanged,
    this.onPageSizeChanged,
    this.pageSizeOptions = const [10, 20, 50],
    super.key,
  });

  final int page;
  final int pageSize;
  final int totalItems;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int>? onPageSizeChanged;
  final List<int> pageSizeOptions;

  List<int?> _pageTokens(int currentOneBased, int totalPages) {
    if (totalPages <= 7) {
      return List<int?>.generate(totalPages, (index) => index + 1);
    }
    final tokens = <int?>[1];
    final lo = math.max(2, currentOneBased - 1);
    final hi = math.min(totalPages - 1, currentOneBased + 1);
    if (lo > 2) {
      tokens.add(null);
    }
    for (var i = lo; i <= hi; i++) {
      tokens.add(i);
    }
    if (hi < totalPages - 1) {
      tokens.add(null);
    }
    tokens.add(totalPages);
    return tokens;
  }

  String _formatCount(int value) {
    final text = value.toString();
    if (text.length <= 3) {
      return text;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (totalItems <= 0) {
      return const SizedBox.shrink();
    }
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.maybeLocaleOf(context)?.languageCode == 'zh';
    final safePageSize = pageSize > 0 ? pageSize : 10;
    final totalPages = math.max(
      1,
      (totalItems + safePageSize - 1) ~/ safePageSize,
    );
    final currentPage = page.clamp(0, totalPages - 1);
    final currentOneBased = currentPage + 1;
    final from = currentPage * safePageSize + 1;
    final to = math.min(totalItems, currentOneBased * safePageSize);

    final summary =
        isZh
            ? '显示 $from–$to / 共 ${_formatCount(totalItems)} 项'
            : 'Showing $from–$to of ${_formatCount(totalItems)}';

    final tokens = _pageTokens(currentOneBased, totalPages);
    // 永远先拷贝：默认 pageSizeOptions 是 const 列表，直接 sort 会抛
    // UnsupportedError（cascade 作用于整个三元表达式，而不只是 else 分支）。
    final effectiveSizeOptions = <int>[...pageSizeOptions];
    if (!effectiveSizeOptions.contains(safePageSize)) {
      effectiveSizeOptions.add(safePageSize);
      effectiveSizeOptions.sort();
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 10,
        children: [
          Text(
            summary,
            style: DesktopType.caption(
              skin.text3,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PagerButton(
                icon: DesktopIcons.firstPage,
                tooltip: isZh ? '首页' : 'First page',
                enabled: currentPage > 0,
                onTap: () => onPageChanged(0),
              ),
              const SizedBox(width: 4),
              _PagerButton(
                icon: DesktopIcons.left,
                tooltip: isZh ? '上一页' : 'Previous page',
                enabled: currentPage > 0,
                onTap: () => onPageChanged(currentPage - 1),
              ),
              const SizedBox(width: 4),
              for (var i = 0; i < tokens.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                if (tokens[i] == null)
                  SizedBox(
                    width: 22,
                    child: Center(
                      child: Text('…', style: DesktopType.caption(skin.text3)),
                    ),
                  )
                else
                  _PagerButton(
                    label: '${tokens[i]}',
                    selected: tokens[i] == currentOneBased,
                    enabled: true,
                    onTap: () {
                      final target = tokens[i]! - 1;
                      if (target != currentPage) {
                        onPageChanged(target);
                      }
                    },
                  ),
              ],
              const SizedBox(width: 4),
              _PagerButton(
                icon: DesktopIcons.chevron,
                tooltip: isZh ? '下一页' : 'Next page',
                enabled: currentPage < totalPages - 1,
                onTap: () => onPageChanged(currentPage + 1),
              ),
              const SizedBox(width: 4),
              _PagerButton(
                icon: DesktopIcons.lastPage,
                tooltip: isZh ? '末页' : 'Last page',
                enabled: currentPage < totalPages - 1,
                onTap: () => onPageChanged(totalPages - 1),
              ),
            ],
          ),
          if (onPageSizeChanged != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isZh ? '每页' : 'Rows',
                  style: DesktopType.caption(skin.text3),
                ),
                const SizedBox(width: 8),
                DesktopSelect<int>(
                  value: safePageSize,
                  variant: DesktopSelectVariant.small,
                  align: DesktopSelectAlign.end,
                  search: false,
                  width: 72,
                  options: [
                    for (final size in effectiveSizeOptions)
                      DesktopSelectOption<int>(value: size, label: '$size'),
                  ],
                  onChanged: onPageSizeChanged!,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    this.icon,
    this.label,
    this.tooltip,
    this.selected = false,
    required this.enabled,
    required this.onTap,
  });

  final IconData? icon;
  final String? label;
  final String? tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    Widget button = DesktopHover(
      enabled: enabled && !selected,
      builder:
          (context, hovered) => GestureDetector(
            onTap: enabled ? onTap : null,
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: enabled ? 1 : 0.3,
              child: AnimatedContainer(
                duration: MotionToken.reduced(context, MotionToken.fast),
                curve: MotionToken.curve,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      selected
                          ? skin.accent
                          : hovered
                          ? skin.raise2
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusIconButton,
                  ),
                ),
                child:
                    icon != null
                        ? Icon(
                          icon,
                          size: 14,
                          color:
                              selected
                                  ? skin.accentInk
                                  : hovered
                                  ? skin.text
                                  : skin.text2,
                        )
                        : Text(
                          label ?? '',
                          style: DesktopType.dense(
                            selected
                                ? skin.accentInk
                                : hovered
                                ? skin.text
                                : skin.text2,
                          ).copyWith(
                            fontSize: 12.5, // ignore: font_size_whitelist
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
              ),
            ),
          ),
    );
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: tooltip ?? label,
      child: DesktopFocusOutline(
        radius: DesktopMetrics.radiusIconButton,
        onActivate: enabled ? onTap : null,
        child: button,
      ),
    );
  }
}
