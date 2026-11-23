import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/desktop/desktop_ambient_hints.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover_field.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_select.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/features/video/domain/series_play_target.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart'
    show MovieCastMember;
import 'package:omninest/features/video/presentation/widgets/subtitle_file_decoder.dart';
import 'package:omninest/features/video/video_dashboard.dart';
import 'package:omninest/platform/file_pick.dart';

part 'desktop_series_detail_hero.dart';
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
  String? _lastSyncedAmbientCover;

  @override
  void didUpdateWidget(covariant DesktopSeriesDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seriesId != widget.seriesId) {
      _lastSyncedAmbientCover = null;
    }
  }

  void _syncAmbientCover(String? url) {
    final normalized = url?.trim();
    final effective =
        (normalized != null && normalized.isNotEmpty) ? normalized : null;
    if (effective == null || _lastSyncedAmbientCover == effective) {
      return;
    }
    _lastSyncedAmbientCover = effective;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(desktopAmbientHintProvider.notifier).setMoviesCover(effective);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final detailAsync = ref.watch(movieSeriesDetailProvider(widget.seriesId));
    return detailAsync.when(
      loading:
          () => const Center(
            child: SizedBox(
              width: 320,
              child: DesktopSkeletonRows(count: 6, avatar: false),
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
        _syncAmbientCover(series.backdropImageUrl ?? series.posterImageUrl);
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
        return SingleChildScrollView(
          child: DesktopPage(
            topPadding: DesktopMetrics.pageTopPaddingCompact,
            children: [
              const SizedBox(height: 6),
              _SeriesHero(
                series: series,
                seasons: detail.seasons.length,
                favorite: favorite,
                busy: _playing || _savingFavorite,
                onBack: () => exitDetailRoute(context, fallbackRoute: '/video'),
                onPlay: _play,
                onToggleFavorite: () => _toggleFavorite(favorite),
              ),
              const SizedBox(height: 22),
              _SeriesMetaStrip(series: series, seasons: detail.seasons),
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerLeft,
                child: DesktopSeg<_SeriesTab>(
                  options: tabs.map((entry) => entry.$1).toList(),
                  value: _tab,
                  labelOf:
                      (tab) => tabs.firstWhere((entry) => entry.$1 == tab).$2,
                  onChanged: (value) => setState(() => _tab = value),
                  small: true,
                ),
              ),
              const SizedBox(height: 20),
              switch (_tab) {
                _SeriesTab.overview => _OverviewTab(detail: detail),
                _SeriesTab.episodes => _EpisodesTab(
                  detail: detail,
                  onPlay: (episode) => _playEpisode(episode.id),
                ),
                _SeriesTab.files => _FilesTab(seriesId: series.id),
                _SeriesTab.subtitles => _SubtitlesTab(seriesId: series.id),
              },
              if (related.isNotEmpty) ...[
                const SizedBox(height: 40),
                Text(
                  l10n.desktopMoviesMoreLikeThis,
                  style: DesktopType.sectionTitle(skin.text),
                ),
                const SizedBox(height: 18),
                _RelatedSeriesRail(items: related),
              ],
            ],
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
    final radius = BorderRadius.circular(16);
    return DesktopGlassSurface(
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: skin.panel,
          borderRadius: radius,
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
      ),
    );
  }
}
