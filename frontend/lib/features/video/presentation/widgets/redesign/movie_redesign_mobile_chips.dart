import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';

/// 移动端 Films/Series 段的排序 chip 行（样例 chip-row）：
/// 最新 / 评分 / 年份 + 收藏过滤 + 尾部状态筛选溢出入口
/// （All/Matched/Pending/Failed 收进底部面板，不占常驻行）。
///
/// 与桌面共用件 [MovieRedesignFilterSortBar] 分离实现：桌面三处共用
/// （宽屏分区/居中分区/管理列表）不受移动语义影响。
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
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(
                  context,
                  label: l10n.videoMobileSortRecent,
                  selected: sortBy == MovieSortBy.dateAdded,
                  onTap: () => onSortBy(MovieSortBy.dateAdded),
                ),
                const SizedBox(width: 6),
                _chip(
                  context,
                  label: l10n.videoRating,
                  selected: sortBy == MovieSortBy.rating,
                  onTap: () => onSortBy(MovieSortBy.rating),
                ),
                const SizedBox(width: 6),
                _chip(
                  context,
                  label: l10n.videoYear,
                  selected: sortBy == MovieSortBy.releaseDate,
                  onTap: () => onSortBy(MovieSortBy.releaseDate),
                ),
                const SizedBox(width: 6),
                _chip(
                  context,
                  label: l10n.videoSectionFavorites,
                  selected: favoritesOnly,
                  onTap: () => onFavoritesOnly(!favoritesOnly),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _StatusFilterEntry(
          filter: filter,
          onFilter: onFilter,
          style: text.mono(
            size: 11,
            color: palette.mutedForeground,
          ), // ignore: font_size_whitelist
        ),
      ],
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    // 样例 chip 选中态：酸绿 10% 底 + 38% 描边 + ink 前景。
    final accent = MobileEnvColors.accent;
    return Material(
      color: selected ? accent.withValues(alpha: 0.10) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: MovieRedesignPalette.borderRadius,
        side: BorderSide(
          color: selected ? accent.withValues(alpha: 0.38) : palette.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: text.body(
              size: 12,
              weight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? MobileEnvColors.ink : palette.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

/// 状态筛选溢出入口：点开底部面板选择刮削状态（收藏过滤激活时隐藏）。
class _StatusFilterEntry extends StatelessWidget {
  const _StatusFilterEntry({
    required this.filter,
    required this.onFilter,
    required this.style,
  });

  final MovieLibraryFilter filter;
  final ValueChanged<MovieLibraryFilter> onFilter;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.movieRedesign;
    final active = filter != MovieLibraryFilter.all;
    return IconButton(
      tooltip: l10n.videoMobileStatusFilter,
      onPressed: () => _openSheet(context),
      icon: Icon(
        Icons.tune_rounded,
        size: 18,
        color: active ? palette.foreground : palette.mutedForeground,
      ),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final options = <(MovieLibraryFilter, String)>[
      (MovieLibraryFilter.all, l10n.videoRedesignFilterAll),
      (MovieLibraryFilter.matched, l10n.videoRedesignFilterMatched),
      (MovieLibraryFilter.pending, l10n.videoRedesignFilterPending),
      (MovieLibraryFilter.failed, l10n.videoRedesignFilterFailed),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetContext) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: Material(
                color: palette.background,
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
                            color: palette.border,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                        child: Text(
                          l10n.videoMobileStatusFilter,
                          style: text.body(
                            size: 13,
                            weight: FontWeight.w700,
                          ), // ignore: font_size_whitelist
                        ),
                      ),
                      for (final (value, label) in options)
                        ListTile(
                          title: Text(
                            label,
                            style: text.body(
                              size: 13,
                            ), // ignore: font_size_whitelist
                          ), // ignore: font_size_whitelist
                          trailing:
                              value == filter
                                  ? Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: palette.foreground,
                                  )
                                  : null,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            onFilter(value);
                          },
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final progress = item.progressPercent.clamp(0.0, 100.0).round();
    final episode = _episodeLabel(context);
    final remainingMinutes =
        (item.durationSeconds - item.positionSeconds).clamp(
          0,
          item.durationSeconds,
        ) ~/
        60;
    // 样例 .cinema-hero：固定 348 高、r26；占位底为模块背景色。
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
                    (_, _, _) => ColoredBox(color: palette.background),
              )
            else
              ColoredBox(color: palette.background),
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
                    style: text.mono(
                      size: 8,
                      weight: FontWeight.w800,
                    ), // ignore: font_size_whitelist
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
                    style: text.mono(
                      size: 9,
                      color: const Color(0xA1FFFFFF),
                      weight: FontWeight.w700,
                    ), // ignore: font_size_whitelist
                  ),
                  const SizedBox(height: 9),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.display(
                      size: 35,
                    ), // ignore: font_size_whitelist
                  ),
                  const SizedBox(height: 6),
                  if (metaLine != null && metaLine!.isNotEmpty)
                    Text(
                      metaLine!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.body(
                        size: 11,
                        color: palette.mutedForeground,
                      ),
                    )
                  else if (episode != null)
                    Text(
                      episode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.body(
                        size: 11,
                        color: palette.mutedForeground,
                      ),
                    ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Material(
                        color: palette.foreground,
                        borderRadius: BorderRadius.circular(22),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: onPlay,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 43),
                            padding: const EdgeInsets.symmetric(horizontal: 17),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  size: 16,
                                  color: palette.background,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.videoHeroResume,
                                  style: text.body(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    color: palette.background,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Material(
                        color: const Color(0x8C121817),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                          side: const BorderSide(color: Color(0x38FFFFFF)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: onInfo,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 43),
                            padding: const EdgeInsets.symmetric(horizontal: 17),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.more_horiz_rounded,
                                  size: 16,
                                  color: palette.foreground,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.videoHeroInfo,
                                  style: text.body(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    color: palette.foreground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
