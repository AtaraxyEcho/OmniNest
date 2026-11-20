part of 'desktop_series_detail_page.dart';

class _SeriesMetaStrip extends StatelessWidget {
  const _SeriesMetaStrip({required this.series, required this.seasons});

  final MovieSeries series;
  final List<MovieSeason> seasons;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final episodeCount = seasons.fold<int>(
      0,
      (sum, season) => sum + (season.episodeCount ?? 0),
    );
    final hasEpisodeCount = seasons.any(
      (season) => season.episodeCount != null,
    );
    final cells = <(String, String, String)>[
      (l10n.videoRating, series.rating?.toStringAsFixed(1) ?? '—', 'TMDB'),
      (
        l10n.videoYear,
        series.firstAirDate?.year.toString() ?? '—',
        series.seriesType,
      ),
      (
        l10n.desktopSeriesEpisodes,
        hasEpisodeCount ? '$episodeCount' : '—',
        l10n.desktopSeriesSeasonCount(seasons.length),
      ),
      (
        l10n.videoGenre,
        series.genres.isEmpty ? '—' : series.genres.take(2).join(' · '),
        '',
      ),
      (
        l10n.videoContentRating,
        series.contentRating?.isNotEmpty == true ? series.contentRating! : '—',
        '',
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var index = 0; index < cells.length; index++)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border:
                      index == 0
                          ? null
                          : Border(left: BorderSide(color: skin.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cells[index].$1.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.eyebrow(skin.text3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cells[index].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.sectionTitle(
                        skin.text,
                      ).copyWith(letterSpacing: -24 * 0.01),
                    ),
                    if (cells[index].$3.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        cells[index].$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.caption(skin.text3),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.detail});

  final MovieSeriesDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final series = detail.series;
    final synopsis =
        series.overview?.trim().isNotEmpty == true
            ? series.overview!
            : l10n.desktopMoviesNoMetadataHint;
    final credits = <Widget>[
      for (final person in detail.cast.take(12))
        _PersonTile(
          name: person.name,
          role: person.character ?? l10n.videoCast,
          image: person.profilePath,
        ),
      for (final person in detail.crew.take(8))
        _PersonTile(
          name: person.name,
          role: person.job ?? l10n.videoCrew,
          image: person.profilePath,
        ),
    ];
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.videoOverview.toUpperCase(),
          style: DesktopType.eyebrow(skin.text3),
        ),
        const SizedBox(height: 8),
        _SeriesSynopsis(text: synopsis),
        if (credits.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            l10n.desktopMoviesCastCrew,
            style: DesktopType.sectionTitle(skin.text),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: credits),
        ],
        if (detail.writable) ...[
          const SizedBox(height: 22),
          _SeriesOverviewActions(series: series),
        ],
      ],
    );
    final right = _SeriesFactsCard(series: series, seasons: detail.seasons);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 20), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 13, child: left),
            const SizedBox(width: 40),
            Expanded(
              flex: 10,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280),
                child: right,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 样例 `.bp-about.clamp`：三行折叠 + accent 链接。
class _SeriesSynopsis extends StatefulWidget {
  const _SeriesSynopsis({required this.text});

  final String text;

  @override
  State<_SeriesSynopsis> createState() => _SeriesSynopsisState();
}

class _SeriesSynopsisState extends State<_SeriesSynopsis> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: DesktopType.body(skin.text2).copyWith(height: 1.65),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 5),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: skin.accent,
              ),
              child: Text(
                _expanded
                    ? l10n.desktopMoviesShowLess
                    : l10n.desktopMoviesReadMore,
                style: DesktopType.button(skin.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesFactsCard extends StatelessWidget {
  const _SeriesFactsCard({required this.series, required this.seasons});

  final MovieSeries series;
  final List<MovieSeason> seasons;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: skin.panel,
        border: Border.all(color: skin.line),
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.videoHeroInfo.toUpperCase(),
            style: DesktopType.eyebrow(skin.text3),
          ),
          const SizedBox(height: 12),
          DesktopKeyValues(
            entries: [
              MapEntry(l10n.videoType, series.seriesType),
              MapEntry(
                l10n.videoYear,
                series.firstAirDate?.year.toString() ?? '—',
              ),
              MapEntry(l10n.desktopSeriesSeasonCountLabel, '${seasons.length}'),
              if (series.contentRating?.isNotEmpty == true)
                MapEntry(l10n.videoContentRating, series.contentRating!),
              MapEntry(l10n.videoScrapeStatus, series.metadataStatus),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeriesOverviewActions extends StatelessWidget {
  const _SeriesOverviewActions({required this.series});

  final MovieSeries series;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        DesktopButton(
          label: l10n.desktopMoviesEditDetails,
          icon: DesktopIcons.edit,
          variant: DesktopButtonVariant.soft,
          onPressed: () {
            unawaited(
              showDesktopDrawer<void>(
                context,
                width: 520,
                barrierDismissible: false,
                builder: (_) => _SeriesEditDialog(series: series),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SeriesEditDialog extends ConsumerStatefulWidget {
  const _SeriesEditDialog({required this.series});

  final MovieSeries series;

  @override
  ConsumerState<_SeriesEditDialog> createState() => _SeriesEditDialogState();
}

class _SeriesEditDialogState extends ConsumerState<_SeriesEditDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.series.title,
  );
  late final TextEditingController _overview = TextEditingController(
    text: widget.series.overview ?? '',
  );
  bool _saving = false;
  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _overview.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = l10n.videoTitleRequired);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .updateSeriesMetadata(
            seriesId: widget.series.id,
            title: title,
            overview: _overview.text.trim(),
          );
      if (!mounted) return;
      ref.invalidate(movieSeriesDetailProvider(widget.series.id));
      showDesktopToast(
        context,
        l10n.videoMetadataSaved,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
      closeDesktopModal(context);
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesEditDetails, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopDrawerFrame(
      eyebrow: l10n.videoMetadataStatus,
      title: l10n.desktopMoviesEditDetails,
      footer: Wrap(
        spacing: 10,
        children: [
          DesktopButton(
            label: l10n.coreCancel,
            onPressed: _saving ? null : () => closeDesktopModal(context),
          ),
          DesktopButton(
            label: l10n.videoDetailSave,
            variant: DesktopButtonVariant.primary,
            busy: _saving,
            onPressed: _saving ? null : () => unawaited(_save()),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 108,
                height: 148,
                child: DesktopCover(
                  url: widget.series.posterImageUrl,
                  fallbackIcon: DesktopIcons.film,
                  cacheKey: 'series-metadata-poster:${widget.series.id}',
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusSmall,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DesktopTextField(
                      controller: _title,
                      label: l10n.videoMetaFieldTitle,
                      required: true,
                      error: _titleError,
                      autofocus: true,
                      onChanged: (_) {
                        if (_titleError != null) {
                          setState(() => _titleError = null);
                        }
                      },
                    ),
                    if (widget.series.genres.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        l10n.videoGenre.toUpperCase(),
                        style: DesktopType.eyebrow(skin.text3),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final genre in widget.series.genres)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: skin.raise,
                                border: Border.all(color: skin.line),
                                borderRadius: BorderRadius.circular(
                                  DesktopMetrics.radiusPill,
                                ),
                              ),
                              child: Text(
                                genre,
                                style: DesktopType.caption(skin.text2),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DesktopTextField(
            controller: _overview,
            label: l10n.videoMetaFieldOverview,
            maxLines: 6,
            height: 140,
          ),
        ],
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.name, required this.role, this.image});

  final String name;
  final String role;
  final String? image;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 38,
              height: 38,
              child: DesktopCover(
                url: image,
                fallbackIcon: DesktopIcons.user,
                cacheKey: 'desktop-series-person:$image',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.denseStrong(skin.text),
                ),
                Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.caption(skin.text3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RelatedSeriesRail extends StatelessWidget {
  const _RelatedSeriesRail({required this.items});

  final List<MovieSeries> items;

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    // 样例 `.poster-grid`：auto-fill minmax(clamp(190px,15vw,250px),1fr)、gap 22。
    const gap = 22.0;
    final minimum = (viewportWidth * 0.15).clamp(190.0, 250.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            math
                .max(
                  1,
                  ((constraints.maxWidth + gap) / (minimum + gap)).floor(),
                )
                .toInt();
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final series in items)
              SizedBox(
                width: cardWidth,
                child: DesktopHoverLift(
                  onTap:
                      () => desktopPush(context, '/video/series/${series.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 2 / 3,
                        child: DesktopCover(
                          url: series.posterImageUrl,
                          fallbackIcon: DesktopIcons.film,
                          cacheKey: 'desktop-related-series:${series.id}',
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        series.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.bodyStrong(
                          DesktopSkin.of(context).text,
                        ).copyWith(fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${series.year} · ${series.genres.take(1).join()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.caption(
                          DesktopSkin.of(context).text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
