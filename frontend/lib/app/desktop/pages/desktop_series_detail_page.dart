import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_select.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/features/video/domain/series_play_target.dart';
import 'package:omninest/features/video/presentation/widgets/subtitle_file_decoder.dart';
import 'package:omninest/features/video/video_dashboard.dart';
import 'package:omninest/platform/file_pick.dart';

part 'desktop_series_detail_sections.dart';
part 'desktop_series_detail_episode_sections.dart';
part 'desktop_series_detail_subtitle_sections.dart';

/// 桌面剧集详情使用 series/season/episode 真实数据，不复用移动详情的黑金画布。
class DesktopSeriesDetailPage extends ConsumerStatefulWidget {
  const DesktopSeriesDetailPage({required this.seriesId, super.key});

  final String seriesId;

  @override
  ConsumerState<DesktopSeriesDetailPage> createState() =>
      _DesktopSeriesDetailPageState();
}

enum _SeriesTab { overview, episodes, files, subtitles }

class _DesktopSeriesDetailPageState
    extends ConsumerState<DesktopSeriesDetailPage> {
  _SeriesTab _tab = _SeriesTab.overview;
  bool _playing = false;
  bool _savingFavorite = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final detailAsync = ref.watch(movieSeriesDetailProvider(widget.seriesId));
    return detailAsync.when(
      loading:
          () => ColoredBox(
            color: skin.bg,
            child: const Center(
              child: SizedBox(
                width: 320,
                child: DesktopSkeletonRows(count: 6, avatar: false),
              ),
            ),
          ),
      error:
          (error, _) => DesktopErrorView(
            message: failureToast(l10n, l10n.desktopNavMovies, error),
            onRetry:
                () =>
                    ref.invalidate(movieSeriesDetailProvider(widget.seriesId)),
          ),
      data: (detail) {
        final dashboard = ref.watch(movieDashboardProvider).asData?.value;
        final favoriteAsync = ref.watch(
          seriesFavoriteProvider(widget.seriesId),
        );
        final favorite =
            favoriteAsync.asData?.value ?? detail.series.isFavorite;
        final series = detail.series;
        final related = <MovieSeries>[
          for (final candidate in dashboard?.series ?? const <MovieSeries>[])
            if (candidate.id != series.id &&
                (candidate.genres.any(series.genres.contains) ||
                    candidate.seriesType == series.seriesType))
              candidate,
        ].take(8).toList(growable: false);
        final tabs = <(_SeriesTab, String)>[
          (_SeriesTab.overview, l10n.videoDetailTabOverview),
          (_SeriesTab.episodes, l10n.desktopSeriesEpisodes),
          (_SeriesTab.files, l10n.desktopSeriesFiles),
          (_SeriesTab.subtitles, l10n.desktopSeriesSubtitles),
        ];
        return ColoredBox(
          color: skin.bg,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SeriesHero(
                  series: series,
                  seasons: detail.seasons.length,
                  favorite: favorite,
                  busy: _playing || _savingFavorite,
                  onBack:
                      () => exitDetailRoute(context, fallbackRoute: '/video'),
                  onPlay: _play,
                  onToggleFavorite: () => _toggleFavorite(favorite),
                ),
                DesktopPage(
                  topPadding: 24,
                  children: [
                    _SeriesMetaStrip(series: series, seasons: detail.seasons),
                    const SizedBox(height: 22),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DesktopSeg<_SeriesTab>(
                        options: tabs.map((entry) => entry.$1).toList(),
                        value: _tab,
                        labelOf:
                            (tab) =>
                                tabs.firstWhere((entry) => entry.$1 == tab).$2,
                        onChanged: (value) => setState(() => _tab = value),
                        small: true,
                      ),
                    ),
                    const SizedBox(height: 22),
                    switch (_tab) {
                      _SeriesTab.overview => _OverviewTab(detail: detail),
                      _SeriesTab.episodes => _EpisodesTab(
                        detail: detail,
                        onPlay: (episode) => _playEpisode(episode.id),
                      ),
                      _SeriesTab.files => _FilesTab(seriesId: series.id),
                      _SeriesTab.subtitles => _SubtitlesTab(
                        seriesId: series.id,
                      ),
                    },
                    if (related.isNotEmpty) ...[
                      const SizedBox(height: 36),
                      Text(
                        l10n.desktopMoviesMoreLikeThis.toUpperCase(),
                        style: DesktopType.eyebrow(skin.text3),
                      ),
                      const SizedBox(height: 14),
                      _RelatedSeriesRail(items: related),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _play() async {
    if (_playing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _playing = true);
    try {
      final intent = await ref.read(
        seriesPlayIntentProvider(widget.seriesId).future,
      );
      if (!mounted) return;
      String? targetId = intent.videoItemId;
      if (intent.kind != SeriesPlayIntentKind.resume || targetId == null) {
        final episodes = await ref.read(
          movieSeriesEpisodesProvider(widget.seriesId).future,
        );
        if (!mounted) return;
        targetId = pickSeriesPlayEpisodeId(
          orderedEpisodes: sortEpisodesForPlay(episodes),
          afterVideoItemId:
              intent.kind == SeriesPlayIntentKind.nextEpisode
                  ? intent.afterVideoItemId
                  : null,
        );
      }
      if (targetId == null || targetId.isEmpty) {
        showDesktopToast(
          context,
          l10n.videoDetailNoPlayableEpisode,
          kind: DesktopToastKind.warn,
          icon: DesktopIcons.info,
        );
        return;
      }
      desktopPush(context, DesktopRoutes.moviePlay(targetId));
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.videoPlay, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _playEpisode(String episodeId) async {
    if (episodeId.isEmpty) return;
    desktopPush(context, DesktopRoutes.moviePlay(episodeId));
  }

  Future<void> _toggleFavorite(bool current) async {
    if (_savingFavorite) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _savingFavorite = true);
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .setSeriesFavorite(widget.seriesId, favorite: !current);
      if (!mounted) return;
      ref.invalidate(seriesFavoriteProvider(widget.seriesId));
      showDesktopToast(
        context,
        current ? l10n.favoriteRemoved : l10n.favoriteAdded,
        icon: current ? DesktopIcons.heart : DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.videoFavorite, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }
}

class _SeriesHero extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final heroWidth = viewport.width;
    final heroHeight = (viewport.height * 0.48).clamp(360.0, 500.0);
    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DesktopCover(
            url: series.heroImageUrl,
            fallbackIcon: DesktopIcons.film,
            cacheKey: 'desktop-series-hero:${series.id}',
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  skin.bg.withValues(alpha: 0.96),
                  skin.bg.withValues(alpha: 0.82),
                  skin.bg.withValues(alpha: 0.18),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [skin.bg, Colors.transparent],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: DesktopIconButton(
                icon: DesktopIcons.left,
                tooltip: l10n.desktopBack,
                onPressed: onBack,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  heroWidth < 760 ? 24 : 48,
                  24,
                  heroWidth < 760 ? 24 : 48,
                  28,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (heroWidth >= 760) ...[
                      SizedBox(
                        width: 190,
                        height: 270,
                        child: DesktopCover(
                          url: series.posterImageUrl,
                          fallbackIcon: DesktopIcons.film,
                          cacheKey: 'desktop-series-poster:${series.id}',
                          borderRadius: BorderRadius.circular(
                            DesktopMetrics.radiusCard,
                          ),
                        ),
                      ),
                      const SizedBox(width: 26),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _Badge(
                                label: series.seriesType,
                                color: skin.accent,
                              ),
                              _Badge(label: series.year, color: skin.text2),
                              _Badge(
                                label: l10n.desktopSeriesSeasonCount(seasons),
                                color: skin.text2,
                              ),
                              if (series.rating != null)
                                _Badge(
                                  label:
                                      '★ ${series.rating!.toStringAsFixed(1)}',
                                  color: skin.warm,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            series.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.displayXl(skin.text, heroWidth),
                          ),
                          if (series.overview?.trim().isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: Text(
                                series.overview!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.body(skin.text2),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              DesktopButton(
                                label: l10n.videoPlay,
                                icon: DesktopIcons.play,
                                variant: DesktopButtonVariant.primary,
                                busy: busy,
                                onPressed: busy ? null : onPlay,
                              ),
                              DesktopIconButton(
                                icon:
                                    favorite
                                        ? DesktopIcons.heartFilled
                                        : DesktopIcons.heart,
                                tooltip: l10n.videoFavorite,
                                active: favorite,
                                onPressed: busy ? null : onToggleFavorite,
                              ),
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
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusPill),
      ),
      child: Text(label, style: DesktopType.caption(color)),
    );
  }
}
