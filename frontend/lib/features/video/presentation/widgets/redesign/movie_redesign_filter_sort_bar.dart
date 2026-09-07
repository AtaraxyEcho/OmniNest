import 'package:flutter/material.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';

/// 筛选或排序芯片数据。
class MovieRedesignChip {
  const MovieRedesignChip({required this.value, required this.label});

  final String value;
  final String label;
}

/// 新版筛选 + 排序芯片行：横向可滚动，筛选主选为实底反色，排序主选为陶土红描边。
class MovieRedesignFilterSortBar extends StatelessWidget {
  const MovieRedesignFilterSortBar({
    required this.filters,
    required this.filterValue,
    required this.onFilter,
    this.sorts,
    this.sortValue,
    this.onSort,
    super.key,
  });

  final List<MovieRedesignChip> filters;
  final String filterValue;
  final ValueChanged<String> onFilter;
  final List<MovieRedesignChip>? sorts;
  final String? sortValue;
  final ValueChanged<String>? onSort;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final sortList = sorts;
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 1),
        shrinkWrap: true,
        children: [
          for (var i = 0; i < filters.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _Chip(
              label: filters[i].label,
              selected: filters[i].value == filterValue,
              onTap: () => onFilter(filters[i].value),
              palette: palette,
              text: text,
            ),
          ],
          if (sortList != null && onSort != null) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: VerticalDivider(
                width: 1,
                thickness: 1,
                color: palette.border,
              ),
            ),
            const SizedBox(width: 8),
            for (var i = 0; i < sortList.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _Chip(
                label: sortList[i].label,
                selected: sortList[i].value == sortValue,
                onTap: () => onSort!(sortList[i].value),
                palette: palette,
                text: text,
                sortStyle: true,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.palette,
    required this.text,
    this.sortStyle = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final MovieRedesignPalette palette;
  final MovieRedesignText text;
  final bool sortStyle;

  @override
  Widget build(BuildContext context) {
    final activeFill = sortStyle ? false : selected;
    final Color foreground;
    final Color background;
    final Color borderColor;
    if (sortStyle) {
      foreground = selected ? palette.primary : palette.mutedForeground;
      background = Colors.transparent;
      borderColor = selected ? palette.primary : Colors.transparent;
    } else if (activeFill) {
      foreground = palette.background;
      background = palette.foreground;
      borderColor = palette.foreground;
    } else {
      foreground = palette.mutedForeground;
      background = Colors.transparent;
      borderColor = palette.border;
    }
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: MovieRedesignPalette.borderRadius,
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: MovieRedesignPalette.borderRadius,
        hoverColor: palette.foreground.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            style: text.body(
              size: 12,
              weight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
