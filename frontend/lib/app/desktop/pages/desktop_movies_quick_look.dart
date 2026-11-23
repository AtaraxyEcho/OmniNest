part of 'desktop_movies_page.dart';

/// 影视页右键「侧栏快速查看」：把条目折成详情坞数据，动作回调由坞传入活跃 context。
void _showMovieQuickLook(
  WidgetRef ref,
  AppLocalizations l10n,
  MovieVideoItem item,
) {
  final rawYear =
      item.releaseDate?.year.toString() ??
      item.metadata['year']?.toString().trim() ??
      '';
  final hasYear =
      item.metadataStatus.toUpperCase() != 'PENDING' && rawYear.isNotEmpty;
  final yearText = hasYear ? rawYear : '';
  final runtimeText = item.runtimeText.trim();
  final subtitle = [
    if (hasYear) yearText,
    if (runtimeText.isNotEmpty) runtimeText,
    if (item.genres.isNotEmpty) item.genres.join(' / '),
  ].join(' · ');
  final facts = <MapEntry<String, String>>[
    if (hasYear) MapEntry(l10n.desktopSortYear, yearText),
    if (runtimeText.isNotEmpty) MapEntry(l10n.musicFieldDuration, runtimeText),
    if (item.rating != null)
      MapEntry(l10n.desktopSortRating, '★ ${item.rating!.toStringAsFixed(1)}'),
    if (item.genres.isNotEmpty)
      MapEntry(l10n.desktopBookType, item.genres.join(' · ')),
  ];
  ref
      .read(desktopShellProvider.notifier)
      .showDetail(
        DesktopDetailData(
          id: 'film:${item.id}',
          kind: 'film',
          title: item.title,
          subtitle: subtitle.isEmpty ? null : subtitle,
          imageUrl:
              item.backdropImageUrl ??
              item.posterImageUrl ??
              item.posterUrl ??
              item.backdropUrl,
          badge:
              item.rating != null
                  ? '★ ${item.rating!.toStringAsFixed(1)}'
                  : null,
          about: item.overview,
          chips: item.castMembers.map((e) => e.name).take(8).toList(),
          factsLabel: l10n.desktopOpenDetails,
          facts: facts,
          primary: DesktopDetailAction(
            label: l10n.desktopPlay,
            icon: DesktopIcons.play,
            onPressed:
                (ctx, r) => desktopPush(ctx, DesktopRoutes.moviePlay(item.id)),
          ),
          secondary: DesktopDetailAction(
            label: l10n.desktopOpenDetails,
            icon: DesktopIcons.info,
            onPressed:
                (ctx, r) =>
                    desktopPush(ctx, DesktopRoutes.movieDetail(item.id)),
          ),
        ),
      );
}

void _showSeriesQuickLook(
  WidgetRef ref,
  AppLocalizations l10n,
  MovieSeries series,
) {
  final yearText =
      series.firstAirDate != null ? '${series.firstAirDate!.year}' : '';
  final subtitle = [
    if (yearText.isNotEmpty) yearText,
    if (series.genres.isNotEmpty) series.genres.join(' / '),
  ].join(' · ');
  final facts = <MapEntry<String, String>>[
    if (yearText.isNotEmpty) MapEntry(l10n.desktopSortYear, yearText),
    if (series.rating != null)
      MapEntry(
        l10n.desktopSortRating,
        '★ ${series.rating!.toStringAsFixed(1)}',
      ),
    if (series.genres.isNotEmpty)
      MapEntry(l10n.desktopBookType, series.genres.join(' · ')),
  ];
  final route = '/video/series/${series.id}';
  ref
      .read(desktopShellProvider.notifier)
      .showDetail(
        DesktopDetailData(
          id: 'series:${series.id}',
          kind: 'film',
          title: series.title,
          subtitle: subtitle.isEmpty ? l10n.videoSectionSeries : subtitle,
          imageUrl: series.backdropUrl ?? series.posterUrl,
          badge:
              series.rating != null
                  ? '★ ${series.rating!.toStringAsFixed(1)}'
                  : null,
          about: series.overview,
          factsLabel: l10n.desktopOpenDetails,
          facts: facts,
          primary: DesktopDetailAction(
            label: l10n.desktopOpenDetails,
            icon: DesktopIcons.info,
            onPressed: (ctx, r) => desktopPush(ctx, route),
          ),
        ),
      );
}

void _showContinueQuickLook(
  WidgetRef ref,
  AppLocalizations l10n,
  MovieContinueWatching item,
  String detailRoute,
) {
  final episodeTag =
      item.seasonNumber != null && item.episodeNumber != null
          ? 'S${item.seasonNumber}E${item.episodeNumber}'
          : null;
  final subtitle = [
    if (episodeTag != null) episodeTag,
    if (item.mediaType != null && item.mediaType!.isNotEmpty) item.mediaType!,
  ].join(' · ');
  ref
      .read(desktopShellProvider.notifier)
      .showDetail(
        DesktopDetailData(
          id: 'continue:${item.id}',
          kind: 'film',
          title: item.title,
          subtitle: subtitle.isEmpty ? null : subtitle,
          imageUrl: item.posterUrl,
          progress: (item.progressPercent / 100).clamp(0.0, 1.0),
          factsLabel: l10n.desktopOpenDetails,
          facts: [
            if (episodeTag != null)
              MapEntry(l10n.videoSectionSeries, episodeTag),
            MapEntry(
              l10n.desktopBookProgress,
              '${item.progressPercent.round()}%',
            ),
          ],
          primary: DesktopDetailAction(
            label: l10n.desktopContinue,
            icon: DesktopIcons.play,
            onPressed:
                (ctx, r) => desktopPush(ctx, DesktopRoutes.moviePlay(item.id)),
          ),
          secondary: DesktopDetailAction(
            label: l10n.desktopOpenDetails,
            icon: DesktopIcons.info,
            onPressed: (ctx, r) => desktopPush(ctx, detailRoute),
          ),
        ),
      );
}
