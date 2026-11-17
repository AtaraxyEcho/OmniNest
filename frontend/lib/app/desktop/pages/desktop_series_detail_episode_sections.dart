part of 'desktop_series_detail_page.dart';

class _EpisodesTab extends StatelessWidget {
  const _EpisodesTab({required this.detail, required this.onPlay});

  final MovieSeriesDetail detail;
  final ValueChanged<MovieVideoItem> onPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (detail.seasons.isEmpty) {
      return DesktopEmpty(
        icon: DesktopIcons.film,
        message: l10n.desktopSeriesEpisodesEmpty,
        actionLabel: null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < detail.seasons.length; i++)
          _SeasonEpisodes(
            key: ValueKey(detail.seasons[i].id),
            seriesId: detail.series.id,
            season: detail.seasons[i],
            initiallyExpanded: i == 0,
            onPlay: onPlay,
          ),
      ],
    );
  }
}

class _SeasonEpisodes extends ConsumerWidget {
  const _SeasonEpisodes({
    required this.seriesId,
    required this.season,
    required this.initiallyExpanded,
    required this.onPlay,
    super.key,
  });

  final String seriesId;
  final MovieSeason season;
  final bool initiallyExpanded;
  final ValueChanged<MovieVideoItem> onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: skin.panel,
        border: Border.all(color: skin.line),
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          title: Text(
            l10n.desktopSeriesSeasonTitle(season.seasonNumber),
            style: DesktopType.bodyStrong(skin.text),
          ),
          subtitle: Text(
            season.title?.isNotEmpty == true
                ? season.title!
                : l10n.videoSeriesEpisodeCount(season.episodeCount ?? 0),
            style: DesktopType.caption(skin.text3),
          ),
          children: [
            _SeasonEpisodeRows(
              seriesId: seriesId,
              seasonNumber: season.seasonNumber,
              onPlay: onPlay,
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonEpisodeRows extends ConsumerWidget {
  const _SeasonEpisodeRows({
    required this.seriesId,
    required this.seasonNumber,
    required this.onPlay,
  });

  final String seriesId;
  final int seasonNumber;
  final ValueChanged<MovieVideoItem> onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final state = ref.watch(
      movieSeasonDetailProvider(
        SeasonKey(seriesId: seriesId, seasonNumber: seasonNumber),
      ),
    );
    return state.when(
      loading:
          () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      error:
          (error, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              failureToast(l10n, l10n.desktopSeriesEpisodes, error),
              style: DesktopType.caption(skin.bad),
            ),
          ),
      data: (season) {
        if (season.episodes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.desktopSeriesEpisodesEmpty,
              style: DesktopType.caption(skin.text3),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < season.episodes.length; i++)
              _EpisodeRow(
                episode: season.episodes[i],
                first: i == 0,
                onPlay: () => onPlay(season.episodes[i]),
              ),
          ],
        );
      },
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.first,
    required this.onPlay,
  });

  final MovieVideoItem episode;
  final bool first;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            height: 64,
            child: DesktopCover(
              url: episode.posterUrl,
              fallbackIcon: DesktopIcons.film,
              cacheKey: 'desktop-episode:${episode.id}',
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  episode.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.rowTitle(skin.text),
                ),
                if (episode.overview?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    episode.overview!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.caption(skin.text3),
                  ),
                ],
                if (!episode.available) ...[
                  const SizedBox(height: 3),
                  Text(
                    l10n.videoEpisodeSourceUnavailable,
                    style: DesktopType.caption(skin.bad),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l10n.videoEpisodeShortLabel(
              episode.seasonNumber ?? 0,
              episode.episodeNumber ?? 0,
            ),
            style: DesktopType.numeric(skin.text3),
          ),
          const SizedBox(width: 12),
          DesktopIconButton(
            icon: DesktopIcons.play,
            tooltip: l10n.videoPlay,
            onPressed: episode.available ? onPlay : null,
          ),
        ],
      ),
    );
  }
}

class _FilesTab extends ConsumerWidget {
  const _FilesTab({required this.seriesId});

  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final state = ref.watch(movieSeriesEpisodesProvider(seriesId));
    return state.when(
      loading: () => const DesktopSkeletonRows(count: 4, avatar: false),
      error:
          (error, _) => Text(
            failureToast(l10n, l10n.desktopSeriesFiles, error),
            style: DesktopType.caption(skin.bad),
          ),
      data: (episodes) {
        if (episodes.isEmpty) {
          return DesktopEmpty(
            icon: DesktopIcons.folder,
            message: l10n.desktopSeriesFilesEmpty,
            actionLabel: null,
          );
        }
        return Column(
          children: [
            for (final episode in episodes)
              ListTile(
                leading: Icon(
                  DesktopIcons.film,
                  color: episode.available ? skin.text2 : skin.bad,
                ),
                title: Text(
                  episode.title,
                  style: DesktopType.rowTitle(skin.text),
                ),
                subtitle: Text(
                  [
                        if (episode.versionLabel?.isNotEmpty == true)
                          episode.versionLabel!,
                        if (episode.containerFormat?.isNotEmpty == true)
                          episode.containerFormat!,
                        if (episode.videoCodec?.isNotEmpty == true)
                          episode.videoCodec!,
                      ]
                      .join(' · ')
                      .ifEmpty(l10n.desktopSeriesFileDetailsUnavailable),
                  style: DesktopType.caption(skin.text3),
                ),
                trailing: Text(
                  episode.available
                      ? l10n.videoEpisodeAvailable
                      : l10n.videoEpisodeSourceUnavailable,
                  style: DesktopType.caption(
                    episode.available ? skin.ok : skin.bad,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
