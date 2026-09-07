import 'package:cached_network_image/cached_network_image.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

/// 按类型分组的横向海报行
class MovieCategoryBars extends StatelessWidget {
  const MovieCategoryBars({
    required this.items,
    required this.onViewMore,
    this.viewMode = MovieViewMode.grid,
    super.key,
  });

  final List<MovieVideoItem> items;
  final ValueChanged<String> onViewMore;
  final MovieViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sections = _buildSections(items, l10n);
    if (sections.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < sections.length; i++) ...[
          _CategoryRow(
            title: sections[i].title,
            items: sections[i].items,
            viewMode: viewMode,
            onViewMore:
                sections[i].genre != null
                    ? () => onViewMore(sections[i].genre!)
                    : null,
          ),
          if (i < sections.length - 1) const SizedBox(height: 28),
        ],
      ],
    );
  }

  List<_CategorySection> _buildSections(
    List<MovieVideoItem> items,
    AppLocalizations l10n,
  ) {
    final sections = <_CategorySection>[];

    // 最近添加（按更新时间倒序，取前 12）
    final recent = List<MovieVideoItem>.from(items)..sort((a, b) {
      final aDate = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    if (recent.isNotEmpty) {
      sections.add(
        _CategorySection(
          title: l10n.videoSectionRecent,
          items: recent.take(12).toList(),
        ),
      );
    }

    // 高分推荐（评分 ≥ 8，按评分倒序）
    final highRated =
        items.where((item) => (item.rating ?? 0) >= 8.0).toList()
          ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    if (highRated.length >= 3) {
      sections.add(
        _CategorySection(
          title: l10n.videoHighRated,
          items: highRated.take(12).toList(),
        ),
      );
    }

    // 最新上映（按上映日期倒序）
    final newest = List<MovieVideoItem>.from(items)..sort((a, b) {
      final aDate = a.releaseDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.releaseDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    if (newest.length >= 3) {
      sections.add(
        _CategorySection(
          title: l10n.videoNewest,
          items: newest.take(12).toList(),
        ),
      );
    }

    // 按类型分组（≥ 3 项的类型）
    final genreMap = <String, List<MovieVideoItem>>{};
    for (final item in items) {
      for (final genre in item.genres) {
        genreMap.putIfAbsent(genre, () => []).add(item);
      }
    }
    final sortedGenres = genreMap.keys.toList()..sort();
    for (final genre in sortedGenres) {
      final genreItems = genreMap[genre]!;
      if (genreItems.length >= 3) {
        sections.add(
          _CategorySection(
            title: genre,
            items: genreItems.take(12).toList(),
            genre: genre,
          ),
        );
      }
    }

    return sections;
  }
}

class _CategorySection {
  const _CategorySection({
    required this.title,
    required this.items,
    this.genre,
  });

  final String title;
  final List<MovieVideoItem> items;
  final String? genre;
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.title,
    required this.items,
    required this.viewMode,
    this.onViewMore,
  });

  final String title;
  final List<MovieVideoItem> items;
  final MovieViewMode viewMode;
  final VoidCallback? onViewMore;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: context.videoColors.onSurface,
                  fontSize: 18,
                  height: 24 / 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Spacer(),
              if (onViewMore != null)
                GestureDetector(
                  onTap: onViewMore,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLocalizations.of(context).videoViewMore,
                        style: TextStyle(
                          color: context.videoColors.primary.withValues(
                            alpha: 0.85,
                          ),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: context.videoColors.primary.withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (viewMode == MovieViewMode.list)
          _CategoryListRows(items: items)
        else
          SizedBox(
            height: compact ? 190 : 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: items.length,
              separatorBuilder: (ctx, idx) => const SizedBox(width: 14),
              itemBuilder:
                  (context, index) =>
                      CategoryPosterCard(item: items[index], compact: compact),
            ),
          ),
      ],
    );
  }
}

/// 分类栏列表视图 — 紧凑横向行
class _CategoryListRows extends StatelessWidget {
  const _CategoryListRows({required this.items});

  final List<MovieVideoItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [for (final item in items) _CategoryListRow(item: item)],
    );
  }
}

class _CategoryListRow extends StatefulWidget {
  const _CategoryListRow({required this.item});

  final MovieVideoItem item;

  @override
  State<_CategoryListRow> createState() => _CategoryListRowState();
}

class _CategoryListRowState extends State<_CategoryListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 180),
        margin: EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color:
              _hovered
                  ? context.videoColors.surfaceContainerHigh
                  : context.videoColors.surfaceContainerHigh.withValues(
                    alpha: 0.50,
                  ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: context.videoColors.outlineVariant.withValues(
              alpha: _hovered ? 0.35 : 0.18,
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (item.mediaType == 'TV') {
                context.push('/video/series/${item.id}');
              } else {
                context.push('/video/${item.id}');
              }
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 45,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: context.videoColors.surfaceContainerHighest,
                    ),
                    child:
                        item.posterImageUrl != null
                            ? CachedNetworkImage(
                              imageUrl: item.posterImageUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: 160,
                              errorWidget:
                                  (ctx, url, err) => Icon(
                                    Icons.movie_rounded,
                                    color: context.videoColors.onSurfaceVariant,
                                    size: 20,
                                  ),
                            )
                            : Icon(
                              Icons.movie_rounded,
                              color: context.videoColors.onSurfaceVariant,
                              size: 20,
                            ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                _hovered
                                    ? context.videoColors.primary
                                    : context.videoColors.onSurface,
                            fontSize: 14,
                            height: 18 / 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '${item.year} · ${item.runtimeText}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.videoColors.onSurfaceVariant
                                .withValues(alpha: _hovered ? 0.92 : 0.72),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.rating != null) ...[
                    Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: context.videoColors.tertiary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      item.rating!.toStringAsFixed(1),
                      style: TextStyle(
                        color: context.videoColors.tertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 8),
                  ],
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: context.videoColors.onSurfaceVariant.withValues(
                      alpha: 0.50,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分类栏专用的横向海报卡片
class CategoryPosterCard extends StatefulWidget {
  const CategoryPosterCard({
    required this.item,
    this.compact = false,
    super.key,
  });

  final MovieVideoItem item;
  final bool compact;

  @override
  State<CategoryPosterCard> createState() => _CategoryPosterCardState();
}

class _CategoryPosterCardState extends State<CategoryPosterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final posterUrl = item.posterImageUrl;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          if (item.mediaType == 'TV') {
            context.push('/video/series/${item.id}');
          } else {
            context.push('/video/${item.id}');
          }
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          scale: _hovered ? 1.04 : 1.0,
          child: SizedBox(
            width: widget.compact ? 112 : 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 海报图
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: context.videoColors.outlineVariant.withValues(
                          alpha: 0.25,
                        ),
                      ),
                      boxShadow:
                          widget.compact
                              ? const []
                              : [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: _hovered ? 0.40 : 0.18,
                                  ),
                                  blurRadius: _hovered ? 24 : 16,
                                  offset: Offset(0, _hovered ? 12 : 8),
                                ),
                              ],
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (posterUrl != null)
                          CachedNetworkImage(
                            imageUrl: posterUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 280,
                            errorWidget:
                                (context, url, error) => _PosterFallback(),
                          )
                        else
                          _PosterFallback(),
                        if (_hovered)
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: Center(
                                child: Icon(
                                  Icons.play_circle_fill_rounded,
                                  size: 42,
                                  color: Color(0xE6FFFFFF),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 8),
                // 标题
                AnimatedDefaultTextStyle(
                  duration: Duration(milliseconds: 180),
                  style: TextStyle(
                    color:
                        _hovered
                            ? context.videoColors.primary
                            : context.videoColors.onSurface,
                    fontSize: widget.compact ? 12 : 13,
                    height: widget.compact ? 16 / 12 : 18 / 13,
                    fontWeight: FontWeight.w700,
                  ),
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  item.year,
                  style: TextStyle(
                    color: context.videoColors.onSurfaceVariant.withValues(
                      alpha: 0.72,
                    ),
                    fontSize: widget.compact ? 10 : 11,
                    height: widget.compact ? 13 / 10 : 14 / 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.videoColors.primaryContainer.withValues(alpha: 0.60),
            context.videoColors.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          color: context.videoColors.onSurfaceVariant,
          size: 32,
        ),
      ),
    );
  }
}
