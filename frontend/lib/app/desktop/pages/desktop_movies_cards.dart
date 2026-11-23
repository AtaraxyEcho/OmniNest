part of 'desktop_movies_page.dart';

class _MoviesLoadingTracks extends StatelessWidget {
  const _MoviesLoadingTracks({required this.tab});

  final DesktopMoviesTab tab;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (tab != DesktopMoviesTab.forYou) {
      final title = switch (tab) {
        DesktopMoviesTab.continueWatching => l10n.desktopContinueWatching,
        DesktopMoviesTab.movies => l10n.desktopMoviesFeatureFilms,
        DesktopMoviesTab.series => l10n.videoSectionSeries,
        DesktopMoviesTab.anime => l10n.videoSectionAnime,
        DesktopMoviesTab.favorites => l10n.photosTabFavorites,
        DesktopMoviesTab.watchlist => l10n.desktopWatchlist,
        DesktopMoviesTab.history => l10n.desktopHistory,
        DesktopMoviesTab.forYou => l10n.desktopForYou,
      };
      return DesktopSection(title: title, child: _MoviePosterGridSkeleton());
    }
    return Column(
      children: [
        for (final title in [
          l10n.desktopContinueWatching,
          l10n.desktopMoviesFeatureFilms,
          l10n.videoSectionSeries,
          l10n.videoSectionAnime,
        ])
          DesktopSection(
            title: title,
            child: SizedBox(
              height: 226,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 5,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder:
                    (context, index) => SizedBox(
                      width: 148,
                      child: DesktopSkeletonBox(
                        height: 222,
                        radius: 12,
                        index: index,
                      ),
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MoviePosterGridSkeleton extends StatelessWidget {
  const _MoviePosterGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0) {
          return const SizedBox.shrink();
        }
        final columns = _posterGridColumns(context, constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 22,
            mainAxisSpacing: 22,
            childAspectRatio: 2 / 3,
          ),
          itemCount: columns * 2,
          itemBuilder:
              (context, index) =>
                  DesktopSkeletonBox(height: 300, radius: 12, index: index),
        );
      },
    );
  }
}

/// CSS 的 `vw` 按视口宽度算，不是栅格容器宽度；窄窗口里固定 200/230
/// 会把海报压出两列以下或撑出多余留白。
double _railPosterWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * 0.14).clamp(168.0, 220.0).toDouble();

double _posterGridMinTile(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * 0.15).clamp(190.0, 250.0).toDouble();

int _posterGridColumns(BuildContext context, double maxWidth) {
  final minTile = _posterGridMinTile(context);
  return ((maxWidth + 22) / (minTile + 22)).floor().clamp(2, 8);
}

Future<void> _toggleMovieWatchlist(
  BuildContext context,
  WidgetRef ref,
  MovieVideoItem item,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    final added = await ref.read(movieWatchlistProvider.notifier).toggle(item);
    if (!context.mounted || added == null) {
      return;
    }
    showDesktopToast(
      context,
      added
          ? l10n.desktopMoviesAddedWatchlist
          : l10n.desktopMoviesRemovedWatchlist,
      kind: added ? DesktopToastKind.success : DesktopToastKind.info,
      icon: added ? DesktopIcons.check : DesktopIcons.trash,
    );
  } on Object catch (error) {
    if (!context.mounted) {
      return;
    }
    showDesktopToast(
      context,
      failureToast(l10n, l10n.desktopMoviesWatchlist, error),
      kind: DesktopToastKind.error,
      icon: DesktopIcons.info,
    );
  }
}

class _PosterCard extends ConsumerStatefulWidget {
  const _PosterCard({required this.item});

  final MovieVideoItem item;

  @override
  ConsumerState<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends ConsumerState<_PosterCard> {
  bool _hovered = false;

  void _openContextMenu(BuildContext context, Offset position) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final saved = ref
        .read(movieWatchlistProvider)
        .any((entry) => entry.id == item.id);
    ref.read(desktopShellProvider.notifier).openMenu(position, [
      DesktopMenuItem(
        label: l10n.desktopPlay,
        icon: DesktopIcons.play,
        onPressed: () => desktopPush(context, DesktopRoutes.moviePlay(item.id)),
      ),
      DesktopMenuItem(
        label: l10n.desktopQuickLook,
        icon: DesktopIcons.panel,
        onPressed: () => _showMovieQuickLook(ref, l10n, item),
      ),
      DesktopMenuItem(
        label: l10n.desktopOpenDetails,
        icon: DesktopIcons.info,
        onPressed:
            () => desktopPush(context, DesktopRoutes.movieDetail(item.id)),
      ),
      const DesktopMenuItem.separator(),
      DesktopMenuItem(
        label:
            saved
                ? l10n.desktopMoviesRemoveWatchlist
                : l10n.desktopMoviesAddWatchlist,
        icon: saved ? DesktopIcons.check : DesktopIcons.plus,
        onPressed: () => unawaited(_toggleMovieWatchlist(context, ref, item)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DesktopTilt(
        onTap: () => desktopPush(context, DesktopRoutes.movieDetail(item.id)),
        onSecondaryTapDown:
            (details) => _openContextMenu(context, details.globalPosition),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DesktopCover(
                url: item.posterUrl ?? item.backdropUrl,
                kind: DesktopCoverKind.network,
                fallbackIcon: DesktopIcons.film,
                cacheKey: 'desktop-poster-${item.id}',
              ),
              const _PosterShade(),
              if (item.rating != null)
                Positioned(
                  top: 12,
                  left: 12,
                  child: DesktopChip(
                    '★ ${item.rating!.toStringAsFixed(1)}',
                    tone: Colors.white,
                  ),
                ),
              Positioned(
                left: 14,
                right: 66,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.cardTitle(Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (item.releaseDate != null)
                          '${item.releaseDate!.year}',
                        ...item.genres.take(1),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.caption(
                        Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: _HoverCardPlay(
                  visible: _hovered,
                  label: l10n.desktopPlayTitle(item.title),
                  onTap:
                      () => desktopPush(
                        context,
                        DesktopRoutes.moviePlay(item.id),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoverCardPlay extends StatelessWidget {
  const _HoverCardPlay({
    required this.visible,
    required this.label,
    required this.onTap,
  });

  final bool visible;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: MotionToken.reduced(
          context,
          const Duration(milliseconds: 280),
        ),
        opacity: visible ? 1 : 0,
        alwaysIncludeSemantics: true,
        child: AnimatedSlide(
          duration: MotionToken.reduced(context, DesktopMotion.cardSlide),
          curve: DesktopMotion.spring,
          offset: visible ? Offset.zero : const Offset(0, 0.18),
          child: _CardPlay(label: label, onTap: onTap),
        ),
      ),
    );
  }
}

class _CardPlay extends StatelessWidget {
  const _CardPlay({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => Tooltip(
            message: label,
            child: GestureDetector(
              onTap: onTap,
              child: AnimatedScale(
                scale: hovered ? 1.1 : 1.0,
                duration: DesktopMotion.of(context, DesktopMotion.springHover),
                curve: DesktopMotion.spring,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: skin.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                        spreadRadius: -6,
                      ),
                    ],
                  ),
                  child: Icon(
                    DesktopIcons.play,
                    size: 18,
                    color: skin.accentInk,
                  ),
                ),
              ),
            ),
          ),
    );
  }
}

class _PosterShade extends StatelessWidget {
  const _PosterShade();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.10),
            Colors.black.withValues(alpha: 0.82),
          ],
          stops: const [0.40, 0.62, 1.0],
        ),
      ),
    );
  }
}

class _PosterRail extends StatelessWidget {
  const _PosterRail({required this.items});

  final List<MovieVideoItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 340,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder:
            (context, index) => SizedBox(
              width: _railPosterWidth(context),
              child: DesktopStagger(
                index: index,
                child: _PosterCard(item: items[index]),
              ),
            ),
      ),
    );
  }
}

class _SeriesRail extends StatelessWidget {
  const _SeriesRail({required this.items});

  final List<MovieSeries> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 340,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder:
            (context, index) => SizedBox(
              width: _railPosterWidth(context),
              child: DesktopStagger(
                index: index,
                child: _SeriesPoster(series: items[index]),
              ),
            ),
      ),
    );
  }
}

class _SeriesPoster extends ConsumerStatefulWidget {
  const _SeriesPoster({required this.series});

  final MovieSeries series;

  @override
  ConsumerState<_SeriesPoster> createState() => _SeriesPosterState();
}

class _SeriesPosterState extends ConsumerState<_SeriesPoster> {
  bool _hovered = false;

  void _openContextMenu(BuildContext context, Offset position) {
    final l10n = AppLocalizations.of(context);
    final series = widget.series;
    ref.read(desktopShellProvider.notifier).openMenu(position, [
      DesktopMenuItem(
        label: l10n.desktopQuickLook,
        icon: DesktopIcons.panel,
        onPressed: () => _showSeriesQuickLook(ref, l10n, series),
      ),
      DesktopMenuItem(
        label: l10n.desktopOpenDetails,
        icon: DesktopIcons.info,
        onPressed: () => desktopPush(context, '/video/series/${series.id}'),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final series = widget.series;
    final meta = [
      if (series.firstAirDate != null) '${series.firstAirDate!.year}',
      ...series.genres.take(1),
    ].join(' · ');
    final subtitle = meta.isEmpty ? l10n.videoSectionSeries : meta;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DesktopTilt(
        onTap: () => desktopPush(context, '/video/series/${series.id}'),
        onSecondaryTapDown:
            (details) => _openContextMenu(context, details.globalPosition),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DesktopCover(
                url: series.posterUrl ?? series.backdropUrl,
                kind: DesktopCoverKind.network,
                fallbackIcon: DesktopIcons.film,
                cacheKey: 'desktop-series-${series.id}',
              ),
              const _PosterShade(),
              if (series.rating != null)
                Positioned(
                  top: 12,
                  left: 12,
                  child: DesktopChip(
                    '★ ${series.rating!.toStringAsFixed(1)}',
                    tone: Colors.white,
                  ),
                ),
              Positioned(
                left: 14,
                right: 66,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      series.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.cardTitle(Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.caption(
                        Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: _HoverCardPlay(
                  visible: _hovered,
                  label: l10n.desktopPlayTitle(series.title),
                  onTap:
                      () => desktopPush(context, '/video/series/${series.id}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideRail extends StatelessWidget {
  const _WideRail({required this.items});

  final List<MovieContinueWatching> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 214,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder:
            (context, index) => SizedBox(
              width: 340,
              child: DesktopStagger(
                index: index,
                child: _WideCard(item: items[index]),
              ),
            ),
      ),
    );
  }
}

class _WideCard extends ConsumerStatefulWidget {
  const _WideCard({required this.item});

  final MovieContinueWatching item;

  @override
  ConsumerState<_WideCard> createState() => _WideCardState();
}

class _WideCardState extends ConsumerState<_WideCard> {
  bool _hovered = false;

  void _openContextMenu(BuildContext context, Offset position) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final detailRoute =
        item.seriesId != null && item.seriesId!.isNotEmpty
            ? '/video/series/${item.seriesId}'
            : DesktopRoutes.movieDetail(item.id);
    ref.read(desktopShellProvider.notifier).openMenu(position, [
      DesktopMenuItem(
        label: l10n.desktopContinue,
        icon: DesktopIcons.play,
        onPressed: () => desktopPush(context, DesktopRoutes.moviePlay(item.id)),
      ),
      DesktopMenuItem(
        label: l10n.desktopQuickLook,
        icon: DesktopIcons.panel,
        onPressed: () => _showContinueQuickLook(ref, l10n, item, detailRoute),
      ),
      DesktopMenuItem(
        label: l10n.desktopOpenDetails,
        icon: DesktopIcons.info,
        onPressed: () => desktopPush(context, detailRoute),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final center = ref.watch(movieCenterControllerProvider).asData?.value;
    double? rating;
    if (center != null) {
      for (final movie in center.movies) {
        if (movie.id == item.id) {
          rating = movie.rating;
          break;
        }
      }
      if (rating == null && item.seriesId != null) {
        for (final s in [...center.tvSeries, ...center.animeSeries]) {
          if (s.id == item.seriesId) {
            rating = s.rating;
            break;
          }
        }
      }
    }
    final episodeTag =
        item.seasonNumber != null && item.episodeNumber != null
            ? 'S${item.seasonNumber}E${item.episodeNumber}'
            : null;
    final subtitle = [
      if (episodeTag != null) episodeTag,
      '${item.progressPercent.round()}%',
      l10n.desktopContinue,
    ].join(' · ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DesktopTilt(
        radius: 16,
        maxDegrees: 5,
        onTap: () => desktopPush(context, DesktopRoutes.moviePlay(item.id)),
        onSecondaryTapDown:
            (details) => _openContextMenu(context, details.globalPosition),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DesktopCover(
                url: item.posterUrl,
                kind: DesktopCoverKind.network,
                fallbackIcon: DesktopIcons.film,
                cacheKey: 'desktop-continue-${item.id}',
              ),
              const _PosterShade(),
              if (rating != null)
                Positioned(
                  top: 12,
                  left: 12,
                  child: DesktopChip(
                    '★ ${rating.toStringAsFixed(1)}',
                    tone: Colors.white,
                  ),
                ),
              Positioned(
                left: 16,
                right: 66,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.cardTitle(Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.caption(
                        Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: _HoverCardPlay(
                  visible: _hovered,
                  label: l10n.desktopPlayTitle(item.title),
                  onTap:
                      () => desktopPush(
                        context,
                        DesktopRoutes.moviePlay(item.id),
                      ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 3,
                  color: Colors.white.withValues(alpha: 0.20),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (item.progressPercent / 100).clamp(0.0, 1.0),
                    child: ColoredBox(
                      color: DesktopSkin.of(context).accent,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideGrid extends StatelessWidget {
  const _WideGrid({required this.items});

  final List<MovieContinueWatching> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 22,
      runSpacing: 22,
      children: [
        for (var i = 0; i < items.length; i++)
          SizedBox(
            width: 340,
            child: DesktopStagger(index: i, child: _WideCard(item: items[i])),
          ),
      ],
    );
  }
}
