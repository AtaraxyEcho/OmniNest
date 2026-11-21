part of 'desktop_series_detail_page.dart';

/// 样例 `FilmDetail` 的剧集分支与影片共用 `.fd-hero` 构图。
///
/// 这里沿用影视详情的圆角卡：双层 `.cin-shade`、左下文案、右下 2° 海报，
/// 只是徽章换成剧集自身的状态（类型 / 年份 / 季数 / 评分）。
class _SeriesHero extends StatefulWidget {
  const _SeriesHero({
    required this.series,
    required this.seasons,
    required this.favorite,
    required this.busy,
    required this.onBack,
    required this.onPlay,
    required this.onToggleFavorite,
  });

  final MovieSeries series;
  final int seasons;
  final bool favorite;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback onToggleFavorite;

  @override
  State<_SeriesHero> createState() => _SeriesHeroState();
}

class _SeriesHeroState extends State<_SeriesHero> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final series = widget.series;
    final viewport = MediaQuery.sizeOf(context);
    final heroHeight = (viewport.height * 0.48).clamp(360.0, 500.0);
    final leftInset = (viewport.width * 0.034).clamp(28.0, 56.0);
    final rightInset = (viewport.width * 0.04).clamp(28.0, 72.0);
    final bottomInset = (viewport.height * 0.04).clamp(26.0, 44.0);
    final posterWidth = (viewport.width * 0.15).clamp(150.0, 214.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: skin.line2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 40,
              offset: Offset(0, 18),
              spreadRadius: -12,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: SizedBox(
            height: heroHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 1180;
                final copyMaxWidth =
                    narrow
                        ? 680.0
                        : math
                            .min(680.0, constraints.maxWidth - 300)
                            .clamp(280.0, 680.0)
                            .toDouble();
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: DesktopCover(
                        url: series.heroImageUrl,
                        fallbackIcon: DesktopIcons.film,
                        cacheKey: 'desktop-series-hero:${series.id}',
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              Color(0x00040709),
                              Color(0x59040709),
                              Color(0xD9040709),
                            ],
                            stops: [0, 0.45, 1],
                          ),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00040709), Color(0xB3040709)],
                            stops: [0.55, 1],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 22,
                      top: 22,
                      child: DesktopButton(
                        label: l10n.desktopNavMovies,
                        icon: DesktopIcons.left,
                        variant: DesktopButtonVariant.glass,
                        onPressed: widget.onBack,
                      ),
                    ),
                    Positioned(
                      left: leftInset,
                      bottom: bottomInset,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: copyMaxWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                DesktopChip(
                                  series.seriesType.toUpperCase(),
                                  solid: true,
                                ),
                                DesktopChip(series.year),
                                DesktopChip(
                                  l10n.desktopSeriesSeasonCount(widget.seasons),
                                ),
                                if ((series.contentRating ?? '').isNotEmpty)
                                  DesktopChip(series.contentRating!),
                                if (series.rating != null)
                                  DesktopChip(
                                    '★ ${series.rating!.toStringAsFixed(1)}',
                                    tone: skin.warm,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              series.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.displayXl(
                                Colors.white,
                                viewport.width,
                              ),
                            ),
                            if ((series.overview ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                series.overview!.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.quote(
                                  Colors.white.withValues(alpha: 0.82),
                                ).copyWith(
                                  fontSize: DesktopType.sizePanelTitle,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              [
                                series.year,
                                l10n.desktopSeriesSeasonCount(widget.seasons),
                                if (series.genres.isNotEmpty)
                                  series.genres.take(2).join(' · '),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.body(
                                Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                DesktopButton(
                                  label: l10n.videoPlay,
                                  icon: DesktopIcons.play,
                                  variant: DesktopButtonVariant.primary,
                                  large: true,
                                  busy: widget.busy,
                                  onPressed: widget.busy ? null : widget.onPlay,
                                ),
                                DesktopButton.iconOnly(
                                  icon:
                                      widget.favorite
                                          ? DesktopIcons.heartFilled
                                          : DesktopIcons.heart,
                                  variant: DesktopButtonVariant.glass,
                                  large: true,
                                  active: widget.favorite,
                                  foregroundOverride:
                                      widget.favorite ? skin.liked : null,
                                  tooltip: l10n.videoFavorite,
                                  onPressed:
                                      widget.busy
                                          ? null
                                          : widget.onToggleFavorite,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!narrow)
                      Positioned(
                        right: rightInset,
                        bottom: bottomInset,
                        child: AnimatedContainer(
                          duration: DesktopMotion.imageFade,
                          curve: DesktopMotion.spring,
                          transform:
                              _hovered
                                  ? Matrix4.translationValues(0, -4, 0)
                                  : Matrix4.rotationZ(2 * math.pi / 180),
                          child: SizedBox(
                            width: posterWidth,
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xBF000000),
                                      blurRadius: 60,
                                      offset: const Offset(0, 30),
                                      spreadRadius: -16,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      DesktopCover(
                                        url: series.posterImageUrl,
                                        fallbackIcon: DesktopIcons.film,
                                        cacheKey:
                                            'desktop-series-poster:${series.id}',
                                      ),
                                      if (series.rating != null)
                                        Align(
                                          alignment: Alignment.topLeft,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: DesktopChip(
                                              '★ ${series.rating!.toStringAsFixed(1)}',
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
