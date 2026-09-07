part of 'movie_series.dart';

// ──────────────────────────────────────────────
// 剧集海报网格
// ──────────────────────────────────────────────

/// 剧集与动漫使用不同卡片比例的响应式网格。
class SeriesPosterGrid extends StatelessWidget {
  const SeriesPosterGrid({
    required this.series,
    required this.variant,
    super.key,
  });

  final List<MovieSeries> series;
  final SeriesCatalogVariant variant;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final posterMetrics = MoviePosterGridMetrics.resolve(
          constraints.maxWidth,
        );
        final landscapeMetrics = SeriesLandscapeGridMetrics.resolve(
          constraints.maxWidth,
        );
        final landscape = variant == SeriesCatalogVariant.tv;
        return GridView.builder(
          itemCount: series.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                landscape ? landscapeMetrics.columns : posterMetrics.columns,
            crossAxisSpacing:
                landscape
                    ? landscapeMetrics.crossAxisSpacing
                    : posterMetrics.crossAxisSpacing,
            mainAxisSpacing:
                landscape
                    ? landscapeMetrics.mainAxisSpacing
                    : posterMetrics.mainAxisSpacing,
            childAspectRatio:
                landscape
                    ? landscapeMetrics.childAspectRatio
                    : posterMetrics.childAspectRatio,
          ),
          itemBuilder:
              (context, index) =>
                  landscape
                      ? _TvSeriesGridCard(item: series[index])
                      : SeriesGridCard(
                        item: series[index],
                        compact: posterMetrics.compact,
                      ),
        );
      },
    );
  }
}

/// 剧集海报卡片 — 与 MoviePosterCard 视觉风格一致
class SeriesGridCard extends StatefulWidget {
  const SeriesGridCard({required this.item, this.compact = false, super.key});

  final MovieSeries item;
  final bool compact;

  @override
  State<SeriesGridCard> createState() => _SeriesGridCardState();
}

class _SeriesGridCardState extends State<SeriesGridCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        scale: _hovered ? 1.018 : 1.0,
        child: Transform.translate(
          offset: Offset(0, _hovered ? -6.0 : 0.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _hovered ? 0.42 : 0.18),
                  blurRadius: _hovered ? 30 : 18,
                  offset: Offset(0, _hovered ? 16 : 10),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push('/video/series/${item.id}'),
                splashColor: context.videoColors.primary.withValues(
                  alpha: 0.10,
                ),
                highlightColor: Colors.transparent,
                hoverColor: context.videoColors.primary.withValues(alpha: 0.04),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _SeriesPosterArt(item: item, hovered: _hovered),
                    ),
                    SizedBox(height: widget.compact ? 8 : 12),
                    AnimatedDefaultTextStyle(
                      duration: Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        color:
                            _hovered
                                ? context.videoColors.primary
                                : context.videoColors.onSurface,
                        fontSize: widget.compact ? 12 : 14,
                        height: widget.compact ? 16 / 12 : 20 / 14,
                        fontWeight: FontWeight.w800,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.videoColors.onSurfaceVariant.withValues(
                          alpha: _hovered ? 0.92 : 0.72,
                        ),
                        fontSize: widget.compact ? 10 : 12,
                        height: widget.compact ? 13 / 10 : 16 / 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 普通剧集使用横向背景图卡，突出按季连续观看的上下文。
class _TvSeriesGridCard extends StatefulWidget {
  const _TvSeriesGridCard({required this.item});

  final MovieSeries item;

  @override
  State<_TvSeriesGridCard> createState() => _TvSeriesGridCardState();
}

class _TvSeriesGridCardState extends State<_TvSeriesGridCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final imageUrl = item.backdropImageUrl ?? item.posterImageUrl;
    final genre = item.genres.isEmpty ? null : item.genres.first;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: MotionToken.resolve(context, MotionToken.fast),
        curve: MotionToken.pageCurve,
        scale: _hovered ? 1.012 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.push('/video/series/${item.id}'),
            child: AnimatedContainer(
              duration: MotionToken.resolve(context, MotionToken.fast),
              curve: MotionToken.pageCurve,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: context.videoColors.surfaceContainerHigh.withValues(
                  alpha: _hovered ? 0.92 : 0.72,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      _hovered
                          ? context.videoColors.primary.withValues(alpha: 0.34)
                          : context.videoColors.outlineVariant.withValues(
                            alpha: 0.24,
                          ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl != null)
                          CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 720,
                            errorWidget:
                                (context, url, error) =>
                                    const _SeriesLandscapeFallback(),
                          )
                        else
                          const _SeriesLandscapeFallback(),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.videoColors.surface.withValues(
                                alpha: 0.82,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                Icons.tv_rounded,
                                size: 17,
                                color: context.videoColors.onSurface,
                              ),
                            ),
                          ),
                        ),
                        if (_hovered)
                          Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 44,
                              color: context.videoColors.onSurface.withValues(
                                alpha: 0.92,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
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
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              item.year,
                              style: TextStyle(
                                color: context.videoColors.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (genre != null) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  '·',
                                  style: TextStyle(
                                    color: context.videoColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  genre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.videoColors.onSurfaceVariant,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ] else
                              const Spacer(),
                            if (item.rating != null) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: context.videoColors.tertiary,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                item.rating!.toStringAsFixed(1),
                                style: TextStyle(
                                  color: context.videoColors.tertiary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
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

class _SeriesLandscapeFallback extends StatelessWidget {
  const _SeriesLandscapeFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.videoColors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.tv_rounded,
          size: 36,
          color: context.videoColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SeriesPosterArt extends StatelessWidget {
  const _SeriesPosterArt({required this.item, required this.hovered});

  final MovieSeries item;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final posterUrl = item.posterImageUrl;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.videoColors.outlineVariant.withValues(alpha: 0.25),
        ),
        gradient: LinearGradient(
          colors: [
            context.videoColors.primaryContainer.withValues(alpha: 0.84),
            Color(0xFF252337),
            context.videoColors.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (posterUrl != null)
            Positioned.fill(
              child: Image.network(
                posterUrl,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
                cacheWidth: 300,
                errorBuilder: (context, error, stackTrace) => SizedBox.shrink(),
              ),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: AnimatedScale(
              duration: Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              scale: hovered ? 1.08 : 1.0,
              child: Icon(
                Icons.animation_rounded,
                color:
                    hovered
                        ? context.videoColors.primary.withValues(alpha: 0.92)
                        : context.videoColors.onSurface.withValues(alpha: 0.74),
              ),
            ),
          ),
          if (hovered)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    size: 52,
                    color: Color(0xE6FFFFFF),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 剧集分类栏 — 按类型横向滚动
class SeriesCategoryBars extends StatelessWidget {
  const SeriesCategoryBars({
    required this.series,
    required this.variant,
    super.key,
  });

  final List<MovieSeries> series;
  final SeriesCatalogVariant variant;

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections(series);
    if (sections.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < sections.length; i++) ...[
          _SeriesCategoryRow(
            title: sections[i].title,
            items: sections[i].items,
            variant: variant,
          ),
          if (i < sections.length - 1) const SizedBox(height: 24),
        ],
      ],
    );
  }

  List<_SeriesCategorySection> _buildSections(List<MovieSeries> series) {
    final sections = <_SeriesCategorySection>[];
    final genreMap = <String, List<MovieSeries>>{};
    for (final s in series) {
      for (final genre in s.genres) {
        genreMap.putIfAbsent(genre, () => []).add(s);
      }
    }
    final sortedGenres = genreMap.keys.toList()..sort();
    for (final genre in sortedGenres) {
      final items = genreMap[genre]!;
      if (items.length >= 2) {
        sections.add(_SeriesCategorySection(title: genre, items: items));
      }
    }
    return sections;
  }
}

class _SeriesCategorySection {
  const _SeriesCategorySection({required this.title, required this.items});

  final String title;
  final List<MovieSeries> items;
}

class _SeriesCategoryRow extends StatelessWidget {
  const _SeriesCategoryRow({
    required this.title,
    required this.items,
    required this.variant,
  });

  final String title;
  final List<MovieSeries> items;
  final SeriesCatalogVariant variant;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final landscape = variant == SeriesCatalogVariant.tv;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            title,
            style: TextStyle(
              color: context.videoColors.onSurface,
              fontSize: 18,
              height: 24 / 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height:
              landscape
                  ? compact
                      ? 190
                      : 220
                  : compact
                  ? 200
                  : 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: items.length,
            separatorBuilder: (ctx, idx) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              if (landscape) {
                return SizedBox(
                  width: compact ? 230 : 270,
                  child: _TvSeriesGridCard(item: items[index]),
                );
              }
              return SeriesPosterCard(item: items[index], compact: compact);
            },
          ),
        ),
      ],
    );
  }
}

/// 剧集海报卡片 — 横向滚动行中使用
class SeriesPosterCard extends StatefulWidget {
  const SeriesPosterCard({required this.item, this.compact = false, super.key});

  final MovieSeries item;
  final bool compact;

  @override
  State<SeriesPosterCard> createState() => _SeriesPosterCardState();
}

class _SeriesPosterCardState extends State<SeriesPosterCard> {
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
        onTap: () => context.push('/video/series/${item.id}'),
        child: AnimatedScale(
          duration: Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          scale: _hovered ? 1.04 : 1.0,
          child: SizedBox(
            width: widget.compact ? 118 : 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      boxShadow: [
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
                            memCacheWidth: 300,
                            errorWidget:
                                (ctx, url, err) => _SeriesPosterFallback(),
                          )
                        else
                          _SeriesPosterFallback(),
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
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Icon(
                            Icons.animation_rounded,
                            size: widget.compact ? 16 : 18,
                            color:
                                _hovered
                                    ? context.videoColors.primary.withValues(
                                      alpha: 0.92,
                                    )
                                    : context.videoColors.onSurface.withValues(
                                      alpha: 0.74,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 8),
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

class _SeriesPosterFallback extends StatelessWidget {
  const _SeriesPosterFallback();

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
          Icons.animation_rounded,
          color: context.videoColors.onSurfaceVariant,
          size: 32,
        ),
      ),
    );
  }
}
