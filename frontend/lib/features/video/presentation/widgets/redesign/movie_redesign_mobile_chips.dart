import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';

/// 托管 Films/Series 段的排序 chip 行（样例 `.chip-row` 胶囊）：
/// 最新 / 评分 / 年份 + 收藏过滤 + 尾部状态筛选溢出入口
/// （All/Matched/Pending/Failed 收进底部玻璃面板，不占常驻行）。
///
/// 仅供托管态使用；桌面三处共用件是 [MovieRedesignFilterSortBar]
/// （宽屏分区/居中分区/管理列表），工位直角形态不随本件变化。
class MovieRedesignMobileChips extends StatelessWidget {
  const MovieRedesignMobileChips({
    required this.sortBy,
    required this.onSortBy,
    required this.favoritesOnly,
    required this.onFavoritesOnly,
    required this.filter,
    required this.onFilter,
    super.key,
  });

  final MovieSortBy sortBy;
  final ValueChanged<MovieSortBy> onSortBy;

  /// 收藏过滤为本地展示态（不写入控制器筛选枚举）。
  final bool favoritesOnly;
  final ValueChanged<bool> onFavoritesOnly;

  final MovieLibraryFilter filter;
  final ValueChanged<MovieLibraryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(
                  label: l10n.videoMobileSortRecent,
                  selected: sortBy == MovieSortBy.dateAdded,
                  onTap: () => onSortBy(MovieSortBy.dateAdded),
                ),
                const SizedBox(width: 6),
                _chip(
                  label: l10n.videoRating,
                  selected: sortBy == MovieSortBy.rating,
                  onTap: () => onSortBy(MovieSortBy.rating),
                ),
                const SizedBox(width: 6),
                _chip(
                  label: l10n.videoYear,
                  selected: sortBy == MovieSortBy.releaseDate,
                  onTap: () => onSortBy(MovieSortBy.releaseDate),
                ),
                const SizedBox(width: 6),
                _chip(
                  label: l10n.videoSectionFavorites,
                  selected: favoritesOnly,
                  onTap: () => onFavoritesOnly(!favoritesOnly),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _StatusFilterEntry(filter: filter, onFilter: onFilter),
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    // 样例胶囊：r12、白 7% 底 + 白 9% 描边、inkMuted 前景；
    // 选中态换成酸绿 10% 底 + 38% 描边 + ink 前景。
    final accent = MobileEnvColors.accent;
    return Material(
      color:
          selected ? accent.withValues(alpha: 0.10) : const Color(0x12FFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color:
              selected
                  ? accent.withValues(alpha: 0.38)
                  : MobileEnvColors.line09,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12, // ignore: font_size_whitelist
              height: 1.2,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? MobileEnvColors.ink : MobileEnvColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// 状态筛选溢出入口：点开底部面板选择刮削状态（收藏过滤激活时隐藏）。
class _StatusFilterEntry extends StatelessWidget {
  const _StatusFilterEntry({required this.filter, required this.onFilter});

  final MovieLibraryFilter filter;
  final ValueChanged<MovieLibraryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = filter != MovieLibraryFilter.all;
    return Tooltip(
      message: l10n.videoMobileStatusFilter,
      child: InkWell(
        onTap: () => _openSheet(context),
        borderRadius: BorderRadius.circular(10),
        child: SizedBox.square(
          dimension: 38,
          child: Icon(
            Icons.tune_rounded,
            size: 18,
            color: active ? MobileEnvColors.ink : MobileEnvColors.inkMuted,
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final options = <(MovieLibraryFilter, String)>[
      (MovieLibraryFilter.all, l10n.videoRedesignFilterAll),
      (MovieLibraryFilter.matched, l10n.videoRedesignFilterMatched),
      (MovieLibraryFilter.pending, l10n.videoRedesignFilterPending),
      (MovieLibraryFilter.failed, l10n.videoRedesignFilterFailed),
    ];
    // 面板经根导航器呈现，默认落在壳层之外：捕获宿主环境再重放。
    final ambience = MobileSheetAmbience.capture(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder:
          (sheetContext) => ambience.wrap(
            _StatusFilterSheet(
              filter: filter,
              options: options,
              title: l10n.videoMobileStatusFilter,
              onSelected: (value) {
                Navigator.of(sheetContext).pop();
                onFilter(value);
              },
            ),
          ),
    );
  }
}

/// 状态筛选面板（样例 `.glass-sheet`：实底 #171E1C + 顶部 r28 + 把手）。
class _StatusFilterSheet extends StatelessWidget {
  const _StatusFilterSheet({
    required this.filter,
    required this.options,
    required this.title,
    required this.onSelected,
  });

  final MovieLibraryFilter filter;
  final List<(MovieLibraryFilter, String)> options;
  final String title;
  final ValueChanged<MovieLibraryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ColoredBox(
            color: MobileEnvColors.sheetSolid,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: MobileEnvColors.line15,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13, // ignore: font_size_whitelist
                        fontWeight: FontWeight.w700,
                        color: MobileEnvColors.ink,
                      ),
                    ),
                  ),
                  for (final (value, label) in options)
                    _StatusFilterOptionRow(
                      label: label,
                      selected: value == filter,
                      onTap: () => onSelected(value),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 面板选项行：发丝线分隔、选中项酸绿勾。
class _StatusFilterOptionRow extends StatelessWidget {
  const _StatusFilterOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: MobileEnvColors.line07)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12, // ignore: font_size_whitelist
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected ? MobileEnvColors.ink : MobileEnvColors.inkMuted,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: MobileEnvColors.accent,
              ),
          ],
        ),
      ),
    );
  }
}

/// 移动端 For you 段的影院 hero 卡（样例 cinema-hero）：续播首项满宽
/// 压题图 + 渐变 + 进度眉标 + 衬线标题 + 续播/详情双钮。
class MovieMobileCinemaHero extends StatelessWidget {
  const MovieMobileCinemaHero({
    required this.item,
    required this.onPlay,
    required this.onInfo,
    this.metaLine,
    this.badgeText,
    super.key,
  });

  final MovieContinueWatching item;
  final VoidCallback onPlay;
  final VoidCallback onInfo;

  /// 元数据行（★ 评分 · 年份 · 时长 · 类型），由调用方从匹配的影片
  /// 元数据拼装；样例 cinema-hero 的 p 行。
  final String? metaLine;

  /// 右上角规格徽标（样例 cinema-badge：4K · HDR）。
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = item.progressPercent.clamp(0.0, 100.0).round();
    final episode = _episodeLabel(context);
    final remainingMinutes =
        (item.durationSeconds - item.positionSeconds).clamp(
          0,
          item.durationSeconds,
        ) ~/
        60;
    // 样例 .cinema-hero：固定 348 高、r26；占位底用环境舞台色，
    // 文本层走环境墨阶（题图上永远是浅字）。
    return SizedBox(
      height: 348,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.posterUrl != null)
              Image.network(
                item.posterUrl!,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, _, _) => const ColoredBox(color: MobileEnvColors.stage),
              )
            else
              const ColoredBox(color: MobileEnvColors.stage),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.42, 1],
                ),
              ),
            ),
            if (badgeText != null && badgeText!.isNotEmpty)
              Positioned(
                right: 14,
                top: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x8C090D0C),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x29FFFFFF)),
                  ),
                  child: Text(
                    badgeText!,
                    style: _heroMonoStyle(size: 8, weight: FontWeight.w800),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 23),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.videoSectionContinueWatching.toUpperCase()} · $progress% · ${l10n.videoHeroMinutesLeft(remainingMinutes)}',
                    style: _heroMonoStyle(
                      size: 9,
                      color: const Color(0xA1FFFFFF),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _heroTitleStyle(),
                  ),
                  const SizedBox(height: 6),
                  if (metaLine != null && metaLine!.isNotEmpty)
                    Text(
                      metaLine!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _heroMetaStyle,
                    )
                  else if (episode != null)
                    Text(
                      episode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _heroMetaStyle,
                    ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      _HeroButton(
                        label: l10n.videoHeroResume,
                        icon: Icons.play_arrow_rounded,
                        filled: true,
                        onTap: onPlay,
                      ),
                      const SizedBox(width: 9),
                      _HeroButton(
                        label: l10n.videoHeroInfo,
                        icon: Icons.more_horiz_rounded,
                        onTap: onInfo,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _episodeLabel(BuildContext context) {
    final seriesId = item.seriesId;
    if (seriesId == null || seriesId.isEmpty) {
      return null;
    }
    final season = item.seasonNumber;
    final episode = item.episodeNumber;
    if (season == null || episode == null) {
      return null;
    }
    return 'S$season E$episode';
  }
}

/// hero 等宽眉标/徽标（样例 mono 9/8，字重 700/800）。
TextStyle _heroMonoStyle({
  required double size,
  Color color = MobileEnvColors.ink,
  FontWeight weight = FontWeight.w700,
}) {
  return TextStyle(
    fontFamily: AppTypography.monoFamily,
    fontFamilyFallback: AppTypography.monoFamilyFallback,
    fontSize: size,
    letterSpacing: 1.5,
    height: 1.2,
    fontWeight: weight,
    color: color,
  );
}

/// hero 标题：Instrument Serif 35，样例 cinema-info h2。
TextStyle _heroTitleStyle() {
  return const TextStyle(
    fontFamily: AppTypography.serifFamily,
    fontFamilyFallback: AppTypography.serifFamilyFallback,
    // ignore: font_size_whitelist
    fontSize: 35,
    height: 1.05,
    fontWeight: FontWeight.w400,
    color: MobileEnvColors.ink,
  );
}

/// hero 元数据行：白 70%，题图上比 inkMuted 更贴样例。
const TextStyle _heroMetaStyle = TextStyle(
  // ignore: font_size_whitelist
  fontSize: 11,
  height: 1.4,
  color: MobileEnvColors.white70,
);

/// hero 动作钮：主钮米白实底深字（样例 .btn-primary），次钮深玻璃描边。
class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground =
        filled ? MobileEnvColors.onButtonInk : MobileEnvColors.ink;
    return Material(
      color: filled ? MobileEnvColors.buttonInk : const Color(0x8C121817),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: filled ? Colors.transparent : const Color(0x38FFFFFF),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 43),
          padding: const EdgeInsets.symmetric(horizontal: 17),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  // ignore: font_size_whitelist
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
