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

/// 海报右上角的「加入待看清单」（样例 `Movies.tsx:38` 的菜单项与
/// `MovieDetail.tsx:65` 的按钮）。清单与其他设备同步，卡片自己读 provider，
/// 不必把回调从页面一路穿到网格里。
class _WatchlistButton extends ConsumerWidget {
  const _WatchlistButton({required this.item, required this.visible});

  final MovieVideoItem item;
  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final saved = ref
        .watch(movieWatchlistProvider)
        .any((watchlistItem) => watchlistItem.id == item.id);
    final interactive = visible || saved;
    return AnimatedOpacity(
      opacity: interactive ? 1 : 0,
      duration: DesktopMotion.fast,
      child: IgnorePointer(
        ignoring: !interactive,
        child: Tooltip(
          message:
              saved
                  ? l10n.desktopMoviesRemoveWatchlist
                  : l10n.desktopMoviesAddWatchlist,
          child: GestureDetector(
            onTap: () async {
              try {
                final added = await ref
                    .read(movieWatchlistProvider.notifier)
                    .toggle(item);
                if (!context.mounted || added == null) {
                  return;
                }
                showDesktopToast(
                  context,
                  added
                      ? l10n.desktopMoviesAddedWatchlist
                      : l10n.desktopMoviesRemovedWatchlist,
                  kind:
                      added ? DesktopToastKind.success : DesktopToastKind.info,
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
            },
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Icon(
                saved ? DesktopIcons.check : DesktopIcons.plus,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
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

class _PosterCard extends StatefulWidget {
  const _PosterCard({required this.item});

  final MovieVideoItem item;

  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DesktopTilt(
        onTap: () => desktopPush(context, DesktopRoutes.movieDetail(item.id)),
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
              Positioned(
                top: 10,
                right: 10,
                child: _WatchlistButton(item: item, visible: _hovered),
              ),
              if (item.rating != null)
                Positioned(
                  top: 12,
                  left: 12,
                  child: DesktopChip(
                    '★ ${item.rating!.toStringAsFixed(1)}',
                    tone: Colors.white,
                  ),
                ),
              AnimatedPositioned(
                duration: DesktopMotion.of(
                  context,
                  const Duration(milliseconds: 400),
                ),
                curve: DesktopMotion.spring,
                right: 14,
                bottom: _hovered ? 66 : 56,
                child: AnimatedOpacity(
                  duration: DesktopMotion.of(
                    context,
                    const Duration(milliseconds: 400),
                  ),
                  opacity: _hovered ? 1 : 0,
                  child: _CardPlay(
                    label: l10n.desktopPlayTitle(item.title),
                    onTap:
                        () => desktopPush(
                          context,
                          DesktopRoutes.moviePlay(item.id),
                        ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
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
              if (skin.isDark) const SizedBox.shrink(),
            ],
          ),
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
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
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
          child: Icon(DesktopIcons.play, size: 18, color: skin.accentInk),
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

class _SeriesPoster extends StatelessWidget {
  const _SeriesPoster({required this.series});

  final MovieSeries series;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DesktopTilt(
      onTap: () => desktopPush(context, '/video/series/${series.id}'),
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
            Positioned(
              left: 14,
              right: 14,
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
                    l10n.videoSectionSeries,
                    style: DesktopType.caption(
                      Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

class _WideCard extends StatelessWidget {
  const _WideCard({required this.item});

  final MovieContinueWatching item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DesktopTilt(
      radius: 16,
      maxDegrees: 5,
      onTap: () => desktopPush(context, DesktopRoutes.moviePlay(item.id)),
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
            Positioned(
              left: 16,
              right: 16,
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
                    '${item.progressPercent.round()}% · ${l10n.desktopContinue}',
                    style: DesktopType.caption(
                      Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
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

/// History 沿用影片浏览的海报网格，观看进度压在海报底缘。
class _HistoryGrid extends StatelessWidget {
  const _HistoryGrid({required this.entries, required this.onClear});

  final List<MovieWatchHistory> entries;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DesktopSection(
      title: l10n.videoSectionHistory,
      actionLabel: entries.isEmpty ? null : l10n.videoClearHistory,
      onAction: entries.isEmpty ? null : onClear,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _posterGridColumns(context, constraints.maxWidth);
          const gap = 22.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var index = 0; index < entries.length; index++)
                SizedBox(
                  width: width,
                  child: DesktopStagger(
                    index: index,
                    child: _HistoryPoster(entry: entries[index]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryPoster extends StatefulWidget {
  const _HistoryPoster({required this.entry});

  final MovieWatchHistory entry;

  @override
  State<_HistoryPoster> createState() => _HistoryPosterState();
}

class _HistoryPosterState extends State<_HistoryPoster> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final progress = _historyProgress(entry);
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DesktopTilt(
        onTap:
            entry.videoItemId.isEmpty
                ? null
                : () => desktopPush(
                  context,
                  DesktopRoutes.movieDetail(entry.videoItemId),
                ),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DesktopCover(
                  url: entry.posterUrl,
                  kind: DesktopCoverKind.network,
                  fallbackIcon: DesktopIcons.film,
                  cacheKey: 'desktop-history-${entry.id}',
                ),
                const _PosterShade(),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.rowTitle(Colors.white),
                      ),
                      if (entry.playedAt != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          l10n.videoLastPlayed(_shortDateTime(entry.playedAt!)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.caption(
                            Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_hovered && entry.videoItemId.isNotEmpty)
                  Center(
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: DesktopMotion.fast,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: skin.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            DesktopIcons.play,
                            size: 18,
                            color: skin.accentInk,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                    color: skin.accent,
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

double _historyProgress(MovieWatchHistory entry) {
  if (entry.durationSeconds <= 0) {
    return 0;
  }
  return (entry.positionSeconds / entry.durationSeconds).clamp(0.0, 1.0);
}

String _shortDateTime(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.items});

  final List<MovieVideoItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
          itemCount: items.length,
          itemBuilder:
              (context, index) => DesktopStagger(
                index: index,
                child: _PosterCard(item: items[index]),
              ),
        );
      },
    );
  }
}

class _SeriesGrid extends StatelessWidget {
  const _SeriesGrid({required this.items});

  final List<MovieSeries> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
          itemCount: items.length,
          itemBuilder:
              (context, index) => DesktopStagger(
                index: index,
                child: _SeriesPoster(series: items[index]),
              ),
        );
      },
    );
  }
}
