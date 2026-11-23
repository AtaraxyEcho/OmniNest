part of 'desktop_series_detail_page.dart';

class _EpisodesTab extends ConsumerStatefulWidget {
  const _EpisodesTab({required this.detail, required this.onPlay});

  final MovieSeriesDetail detail;
  final ValueChanged<MovieVideoItem> onPlay;

  @override
  ConsumerState<_EpisodesTab> createState() => _EpisodesTabState();
}

class _EpisodesTabState extends ConsumerState<_EpisodesTab> {
  int? _selectedSeasonNumber;
  String? _busyEpisodeId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final seasons = widget.detail.seasons;
    if (seasons.isEmpty) {
      return DesktopEmpty(
        icon: DesktopIcons.film,
        message: l10n.desktopSeriesEpisodesEmpty,
        actionLabel: null,
      );
    }

    final activeSeason =
        seasons
            .where((s) => s.seasonNumber == _selectedSeasonNumber)
            .firstOrNull ??
        seasons.first;
    final seasonAsync = ref.watch(
      movieSeasonDetailProvider(
        SeasonKey(
          seriesId: widget.detail.series.id,
          seasonNumber: activeSeason.seasonNumber,
        ),
      ),
    );
    final historyList =
        ref
            .watch(movieSeriesHistoryProvider(widget.detail.series.id))
            .asData
            ?.value ??
        const <MovieWatchHistory>[];
    final historyByItem = <String, MovieWatchHistory>{
      for (final h in historyList) h.videoItemId: h,
    };
    final playIntent =
        ref
            .watch(seriesPlayIntentProvider(widget.detail.series.id))
            .asData
            ?.value;

    final episodes =
        seasonAsync.asData?.value.episodes ?? const <MovieVideoItem>[];
    final totalCount =
        episodes.isNotEmpty
            ? episodes.length
            : (activeSeason.episodeCount ?? 0);
    final watchedCount =
        episodes.where((ep) => historyByItem[ep.id]?.completed == true).length;
    final seasonRatio =
        totalCount > 0 ? (watchedCount / totalCount).clamp(0.0, 1.0) : 0.0;

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (seasons.length > 1)
                  SizedBox(
                    width: 240,
                    child: DesktopSelect<int>(
                      value: activeSeason.seasonNumber,
                      variant: DesktopSelectVariant.field,
                      options: [
                        for (final s in seasons)
                          DesktopSelectOption(
                            value: s.seasonNumber,
                            label:
                                s.title?.trim().isNotEmpty == true
                                    ? '${l10n.desktopSeriesSeasonTitle(s.seasonNumber)} · ${s.title}'
                                    : l10n.desktopSeriesSeasonTitle(
                                      s.seasonNumber,
                                    ),
                            hint:
                                s.episodeCount != null
                                    ? l10n.videoSeriesEpisodeCount(
                                      s.episodeCount!,
                                    )
                                    : null,
                          ),
                      ],
                      onChanged:
                          (value) =>
                              setState(() => _selectedSeasonNumber = value),
                    ),
                  )
                else
                  Text(
                    activeSeason.title?.trim().isNotEmpty == true
                        ? '${l10n.desktopSeriesSeasonTitle(activeSeason.seasonNumber)} · ${activeSeason.title}'
                        : l10n.desktopSeriesSeasonTitle(
                          activeSeason.seasonNumber,
                        ),
                    style: DesktopType.sectionTitle(skin.text),
                  ),
                const Spacer(),
                Text(
                  isZh
                      ? '已看 $watchedCount / $totalCount 集'
                      : 'Watched $watchedCount / $totalCount',
                  style: DesktopType.numeric(skin.text3),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                height: 3,
                color: skin.raise2,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: seasonRatio,
                  child: Container(color: skin.accent),
                ),
              ),
            ),
            const SizedBox(height: 14),
            seasonAsync.when(
              loading: () => const DesktopSkeletonRows(count: 4, avatar: false),
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
                  return DesktopEmpty(
                    icon: DesktopIcons.film,
                    message: l10n.desktopSeriesEpisodesEmpty,
                    actionLabel: null,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < season.episodes.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == season.episodes.length - 1 ? 0 : 8,
                        ),
                        child: _EpisodeRow(
                          episode: season.episodes[i],
                          history: historyByItem[season.episodes[i].id],
                          isResumeTarget:
                              playIntent?.kind == SeriesPlayIntentKind.resume &&
                              playIntent?.videoItemId == season.episodes[i].id,
                          busy: _busyEpisodeId == season.episodes[i].id,
                          anyBusy: _busyEpisodeId != null,
                          onPlay: () => widget.onPlay(season.episodes[i]),
                          onProbe:
                              () =>
                                  unawaited(_probeEpisode(season.episodes[i])),
                          onExportNfo:
                              () => unawaited(
                                _exportEpisodeNfo(season.episodes[i]),
                              ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _probeEpisode(MovieVideoItem episode) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busyEpisodeId = episode.id);
    try {
      await ref.read(movieApiProvider).probeItem(episode.id);
      if (!mounted) return;
      ref.invalidate(movieSeriesEpisodesProvider(widget.detail.series.id));
      ref.invalidate(
        movieSeasonDetailProvider(
          SeasonKey(
            seriesId: widget.detail.series.id,
            seasonNumber: episode.seasonNumber ?? 1,
          ),
        ),
      );
      showDesktopToast(
        context,
        l10n.desktopMoviesProbeDone,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesReprobe, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _busyEpisodeId = null);
    }
  }

  Future<void> _exportEpisodeNfo(MovieVideoItem episode) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busyEpisodeId = episode.id);
    try {
      final result = await ref.read(movieApiProvider).exportNfo(episode.id);
      if (!mounted) return;
      showDesktopToast(
        context,
        result.exportPath.isNotEmpty
            ? '${l10n.desktopMoviesExportNfo}: ${result.exportPath}'
            : l10n.desktopMoviesExportNfo,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesExportNfo, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _busyEpisodeId = null);
    }
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.history,
    required this.isResumeTarget,
    required this.busy,
    required this.anyBusy,
    required this.onPlay,
    required this.onProbe,
    required this.onExportNfo,
  });

  final MovieVideoItem episode;
  final MovieWatchHistory? history;
  final bool isResumeTarget;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onPlay;
  final VoidCallback onProbe;
  final VoidCallback onExportNfo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final watched = history?.completed == true;
    final progress =
        history != null && history!.durationSeconds > 0
            ? (history!.positionSeconds / history!.durationSeconds).clamp(
              0.0,
              1.0,
            )
            : 0.0;
    final runtime = episode.runtimeText.trim();

    return DesktopHover(
      enabled: episode.available,
      builder:
          (context, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: episode.available ? onPlay : null,
            child: AnimatedContainer(
              duration: DesktopMotion.of(
                context,
                const Duration(milliseconds: 140),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color:
                    isResumeTarget
                        ? skin.accent.withValues(alpha: hovered ? 0.14 : 0.09)
                        : hovered
                        ? skin.raise
                        : skin.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      isResumeTarget
                          ? skin.accent.withValues(alpha: 0.45)
                          : hovered
                          ? skin.line2
                          : skin.line,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${episode.episodeNumber ?? 0}'.padLeft(2, '0'),
                      textAlign: TextAlign.center,
                      style: DesktopType.numeric(
                        isResumeTarget ? skin.accent : skin.text3,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 136,
                    height: 76,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DesktopCover(
                            url:
                                episode.backdropImageUrl ??
                                episode.posterImageUrl,
                            fallbackIcon: DesktopIcons.film,
                            cacheKey: 'desktop-episode:${episode.id}',
                            borderRadius: BorderRadius.circular(9),
                          ),
                          AnimatedOpacity(
                            opacity: hovered && episode.available ? 1 : 0,
                            duration: DesktopMotion.of(
                              context,
                              const Duration(milliseconds: 140),
                            ),
                            alwaysIncludeSemantics: true,
                            child: ColoredBox(
                              color: const Color(0x7A000000),
                              child: Center(
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    color: Color(0xE6FFFFFF),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    DesktopIcons.play,
                                    size: 18,
                                    color: Color(0xFF141414),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (progress > 0 && !watched)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: 3,
                                color: const Color(0x66000000),
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: progress,
                                  child: Container(color: skin.accent),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                episode.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.rowTitle(skin.text),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: skin.raise2,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                l10n.videoEpisodeShortLabel(
                                  episode.seasonNumber ?? 0,
                                  episode.episodeNumber ?? 0,
                                ),
                                style: DesktopType.mono(
                                  skin.text2,
                                ).copyWith(fontSize: DesktopType.sizeCaption),
                              ),
                            ),
                            if (runtime.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                runtime,
                                style: DesktopType.numeric(skin.text3),
                              ),
                            ],
                          ],
                        ),
                        if (episode.overview?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 5),
                          Text(
                            episode.overview!.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.caption(
                              skin.text3,
                            ).copyWith(height: 1.45),
                          ),
                        ],
                        if (!episode.available) ...[
                          const SizedBox(height: 4),
                          Text(
                            l10n.videoEpisodeSourceUnavailable,
                            style: DesktopType.caption(skin.bad),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isResumeTarget)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: skin.accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: skin.accent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                DesktopIcons.play,
                                size: 13,
                                color: skin.accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isZh ? '继续播放' : 'Continue',
                                style: DesktopType.micro(
                                  skin.accent,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        )
                      else if (watched)
                        Tooltip(
                          message: isZh ? '已看完' : 'Watched',
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: skin.ok.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              DesktopIcons.check,
                              size: 14,
                              color: skin.ok,
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      if (busy)
                        const SizedBox.square(
                          dimension: 24,
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else ...[
                        DesktopIconButton(
                          icon: DesktopIcons.retry,
                          tooltip: l10n.desktopMoviesReprobe,
                          onPressed: anyBusy ? null : onProbe,
                        ),
                        DesktopIconButton(
                          icon: DesktopIcons.download,
                          tooltip: isZh ? '导出单集 NFO' : 'Export episode NFO',
                          onPressed: anyBusy ? null : onExportNfo,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _FilesTab extends ConsumerStatefulWidget {
  const _FilesTab({required this.seriesId});

  final String seriesId;

  @override
  ConsumerState<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends ConsumerState<_FilesTab> {
  String? _busyEpisodeId;

  Future<void> _probeEpisode(MovieVideoItem episode) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busyEpisodeId = episode.id);
    try {
      await ref.read(movieApiProvider).probeItem(episode.id);
      if (!mounted) return;
      ref.invalidate(movieSeriesEpisodesProvider(widget.seriesId));
      showDesktopToast(
        context,
        l10n.desktopMoviesProbeDone,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesReprobe, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _busyEpisodeId = null);
    }
  }

  Future<void> _exportEpisodeNfo(MovieVideoItem episode) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busyEpisodeId = episode.id);
    try {
      final result = await ref.read(movieApiProvider).exportNfo(episode.id);
      if (!mounted) return;
      showDesktopToast(
        context,
        result.exportPath.isNotEmpty
            ? '${l10n.desktopMoviesExportNfo}: ${result.exportPath}'
            : l10n.desktopMoviesExportNfo,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesExportNfo, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _busyEpisodeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final state = ref.watch(movieSeriesEpisodesProvider(widget.seriesId));
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
        return Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < episodes.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == episodes.length - 1 ? 0 : 8,
                    ),
                    child: _SeriesFileRow(
                      episode: episodes[i],
                      busy: _busyEpisodeId == episodes[i].id,
                      anyBusy: _busyEpisodeId != null,
                      isZh: isZh,
                      onProbe: () => unawaited(_probeEpisode(episodes[i])),
                      onExportNfo:
                          () => unawaited(_exportEpisodeNfo(episodes[i])),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
