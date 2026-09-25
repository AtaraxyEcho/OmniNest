part of 'series_detail_page.dart';

/// 季集折叠列表与分集行。
class _SeriesEpisodesHeader extends StatelessWidget {
  const _SeriesEpisodesHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Text(
      l10n.videoDetailEpisodesHeader,
      style: MovieDetailTheme.mono(AppTypography.bodySmall, letterSpacing: 2),
    );
  }
}

/// 季折叠列表：展开时懒加载该季分集。
class _SeasonAccordion extends ConsumerWidget {
  const _SeasonAccordion({
    required this.seriesId,
    required this.seasons,
    required this.openSeasonId,
    required this.onToggle,
  });

  final String seriesId;
  final List<MovieSeason> seasons;
  final String? openSeasonId;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.movieDetailPalette;
    final text = context.movieDetailText;
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        for (final season in seasons)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              border: Border.all(color: palette.border),
            ),
            child: Column(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onToggle(season.id),
                    hoverColor: palette.card,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'S${season.seasonNumber.toString().padLeft(2, '0')}'
                              ' — ${season.title ?? l10n.videoSectionTvShows}',
                              style: text
                                  .mono(
                                    size: AppTypography.bodySmall,
                                    color: palette.foreground,
                                  )
                                  .copyWith(letterSpacing: 1),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (season.episodeCount != null)
                            Text(
                              l10n.videoSeriesEpisodeCount(
                                season.episodeCount!,
                              ),
                              style: text.mono(size: AppTypography.bodySmall),
                            ),
                          const SizedBox(width: 8),
                          Icon(
                            openSeasonId == season.id
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: palette.mutedForeground,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (openSeasonId == season.id)
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: MovieDetailTheme.border),
                      ),
                    ),
                    child: _SeasonEpisodeList(
                      seriesId: seriesId,
                      seasonNumber: season.seasonNumber,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SeasonEpisodeList extends ConsumerWidget {
  const _SeasonEpisodeList({
    required this.seriesId,
    required this.seasonNumber,
  });

  final String seriesId;
  final int seasonNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodesAsync = ref.watch(
      movieSeasonDetailProvider(
        SeasonKey(seriesId: seriesId, seasonNumber: seasonNumber),
      ),
    );
    return episodesAsync.when(
      loading:
          () => const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      error:
          (error, _) => Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              movieErrorMessage(error),
              style: MovieDetailTheme.mono(AppTypography.bodySmall),
            ),
          ),
      data: (seasonDetail) {
        final episodes = seasonDetail.episodes;
        if (episodes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              AppLocalizations.of(context).videoCollectionEmpty,
              style: MovieDetailTheme.mono(AppTypography.bodySmall),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < episodes.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: MovieDetailTheme.border,
                ),
              _EpisodeRow(episode: episodes[i]),
            ],
          ],
        );
      },
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode});

  final MovieVideoItem episode;

  @override
  Widget build(BuildContext context) {
    final available = episode.availabilityStatus == 'AVAILABLE';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:
            available ? () => context.push('/video/${episode.id}/play') : null,
        hoverColor: MovieDetailTheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                height: 48,
                child: Opacity(
                  opacity: 0.70,
                  child: _CoverImage(
                    url: episode.posterImageUrl,
                    cacheKey: 'movie-episode-poster:${episode.id}',
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MovieDetailTheme.body(
                        14,
                        color:
                            available
                                ? MovieDetailTheme.foreground
                                : MovieDetailTheme.mutedText,
                      ),
                    ),
                    if (episode.overview != null &&
                        episode.overview!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        episode.overview!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MovieDetailTheme.mono(AppTypography.bodySmall),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.play_arrow_rounded,
                size: 18,
                color:
                    available
                        ? MovieDetailTheme.secondaryText
                        : MovieDetailTheme.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
