import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/video/application/movie_controller.dart';

typedef YearRangeChanged = void Function({int? from, int? to});

class MovieFilterBar extends StatefulWidget {
  const MovieFilterBar({super.key});

  @override
  State<MovieFilterBar> createState() => _MovieFilterBarState();
}

class _MovieFilterBarState extends State<MovieFilterBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(movieCenterControllerProvider);
        final value = state.asData?.value;
        if (value == null) return const SizedBox.shrink();

        final controller = ref.read(movieCenterControllerProvider.notifier);
        final genres = value.availableGenres.toList()..sort();
        final years =
            value.availableYears.toList()..sort((a, b) => b.compareTo(a));

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.videoColors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: context.videoColors.outlineVariant.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 第一行：类型（水平滚动）
              if (genres.isNotEmpty)
                _buildGenreRow(context, controller, value, genres),
              const SizedBox(height: 10),
              // 第二行：年份预设（水平滚动）
              if (years.isNotEmpty)
                _buildYearRow(context, controller, value, years),
              // 展开区域
              if (_expanded) ...[
                const SizedBox(height: 10),
                // 第三行：评分（水平滚动）
                _buildRatingRow(context, controller, value),
                const SizedBox(height: 10),
                // 第四行：排序 + 视图 + 清除
                _buildToolbarRow(context, controller, value),
              ],
              const SizedBox(height: 8),
              // 展开/收起按钮
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _expanded
                        ? AppLocalizations.of(context).videoCollapse
                        : AppLocalizations.of(context).videoMoreFilters,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: context.videoColors.onSurfaceVariant,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGenreRow(
    BuildContext context,
    MovieCenterController controller,
    MovieCenterState value,
    List<String> genres,
  ) {
    return _FilterRow(
      label: AppLocalizations.of(context).videoGenre,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: genres.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final genre = genres[index];
          final selected = value.selectedGenres.contains(genre);
          return _CompactChip(
            label: genre,
            selected: selected,
            onTap: () => controller.toggleGenre(genre),
            colors: context.videoColors,
          );
        },
      ),
    );
  }

  Widget _buildYearRow(
    BuildContext context,
    MovieCenterController controller,
    MovieCenterState value,
    List<int> years,
  ) {
    final presets = _YearPresets.fromYears(years);
    return _FilterRow(
      label: AppLocalizations.of(context).videoYear,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: presets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final preset = presets[index];
          final selected =
              value.yearFrom == preset.from && value.yearTo == preset.to;
          return _CompactChip(
            label: preset.label,
            selected: selected,
            onTap: () {
              final same =
                  value.yearFrom == preset.from && value.yearTo == preset.to;
              controller.setYearRange(
                from: same ? null : preset.from,
                to: same ? null : preset.to,
              );
            },
            colors: context.videoColors,
          );
        },
      ),
    );
  }

  Widget _buildRatingRow(
    BuildContext context,
    MovieCenterController controller,
    MovieCenterState value,
  ) {
    return _FilterRow(
      label: AppLocalizations.of(context).videoRating,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final rating = [7.0, 8.0, 9.0][index];
          final selected = value.minRating == rating;
          return _RatingChip(
            rating: rating,
            selected: selected,
            onTap: () => controller.setMinRating(selected ? null : rating),
          );
        },
      ),
    );
  }

  Widget _buildToolbarRow(
    BuildContext context,
    MovieCenterController controller,
    MovieCenterState value,
  ) {
    return Row(
      children: [
        _FilterLabel(text: AppLocalizations.of(context).videoSort),
        const SizedBox(width: 8),
        _SortDropdown(
          sortBy: value.sortBy,
          ascending: value.sortAscending,
          onChanged: (by) => controller.setSort(by),
          onToggleOrder:
              () => controller.setSort(
                value.sortBy,
                ascending: !value.sortAscending,
              ),
        ),
        const Spacer(),
        _ViewModeToggle(
          mode: value.viewMode,
          onChanged: controller.setViewMode,
        ),
        if (value.hasFilters) ...[
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: controller.clearFilters,
            icon: const Icon(Icons.filter_list_off_rounded, size: 16),
            label: Text(AppLocalizations.of(context).videoClear),
            style: TextButton.styleFrom(
              foregroundColor: context.videoColors.onSurfaceVariant,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ],
    );
  }
}

/// 筛选行：标签 + 水平滚动内容
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _FilterLabel(text: label),
        const SizedBox(width: 12),
        Expanded(child: SizedBox(height: 34, child: child)),
      ],
    );
  }
}

/// 紧凑筛选芯片
class _CompactChip extends StatelessWidget {
  const _CompactChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VideoColors colors;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              selected ? colors.primaryContainer : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                selected
                    ? colors.primaryContainer
                    : colors.outlineVariant.withValues(alpha: 0.30),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? colors.onPrimaryContainer : colors.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.videoColors.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// 年份预设：从可用年份中取最近 5 个作为快捷芯片。
class _YearPresets {
  _YearPresets._(this.presets);

  final List<_YearPreset> presets;

  static List<_YearPreset> fromYears(List<int> years) {
    if (years.isEmpty) return const [];
    final sorted = List<int>.from(years)..sort((a, b) => b.compareTo(a));
    return sorted.take(5).map((y) => _YearPreset(y, '$y')).toList();
  }
}

class _YearPreset {
  const _YearPreset(this.year, this.label);
  final int year;
  final String label;

  int? get from => year;
  int? get to => year;
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({
    required this.rating,
    required this.selected,
    required this.onTap,
  });

  final double rating;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              selected
                  ? context.videoColors.primaryContainer
                  : context.videoColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                selected
                    ? context.videoColors.primaryContainer
                    : context.videoColors.outlineVariant.withValues(
                      alpha: 0.30,
                    ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_rounded,
              size: 14,
              color:
                  selected
                      ? context.videoColors.onPrimaryContainer
                      : context.videoColors.tertiary,
            ),
            SizedBox(width: 4),
            Text(
              '${rating.toStringAsFixed(0)}+',
              style: TextStyle(
                color:
                    selected
                        ? context.videoColors.onPrimaryContainer
                        : context.videoColors.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  const _SortDropdown({
    required this.sortBy,
    required this.ascending,
    required this.onChanged,
    required this.onToggleOrder,
  });

  final MovieSortBy sortBy;
  final bool ascending;
  final ValueChanged<MovieSortBy> onChanged;
  final VoidCallback onToggleOrder;

  static Map<MovieSortBy, String> _labels(AppLocalizations l10n) => {
    MovieSortBy.dateAdded: l10n.videoSortDateAdded,
    MovieSortBy.releaseDate: l10n.videoSortReleaseDate,
    MovieSortBy.rating: l10n.videoRating,
    MovieSortBy.title: l10n.videoSortTitle,
  };

  @override
  Widget build(BuildContext context) {
    final labels = _labels(AppLocalizations.of(context));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: context.videoColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: context.videoColors.outlineVariant.withValues(alpha: 0.30),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<MovieSortBy>(
              value: sortBy,
              isDense: true,
              icon: Icon(
                Icons.arrow_drop_down_rounded,
                color: context.videoColors.onSurfaceVariant,
                size: 20,
              ),
              dropdownColor: context.videoColors.surfaceContainerHigh,
              style: TextStyle(
                color: context.videoColors.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: [
                for (final entry in labels.entries)
                  DropdownMenuItem<MovieSortBy>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
        SizedBox(width: 4),
        GestureDetector(
          onTap: onToggleOrder,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.videoColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: context.videoColors.outlineVariant.withValues(
                  alpha: 0.30,
                ),
              ),
            ),
            child: Icon(
              ascending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: context.videoColors.onSurfaceVariant,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.mode, required this.onChanged});

  final MovieViewMode mode;
  final ValueChanged<MovieViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: context.videoColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: context.videoColors.outlineVariant.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewModeButton(
            icon: Icons.grid_view_rounded,
            selected: mode == MovieViewMode.grid,
            onTap: () => onChanged(MovieViewMode.grid),
          ),
          Container(
            width: 1,
            height: 20,
            color: context.videoColors.outlineVariant.withValues(alpha: 0.30),
          ),
          _ViewModeButton(
            icon: Icons.view_list_rounded,
            selected: mode == MovieViewMode.list,
            onTap: () => onChanged(MovieViewMode.list),
          ),
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color:
              selected
                  ? context.videoColors.primary
                  : context.videoColors.onSurfaceVariant,
        ),
      ),
    );
  }
}
