import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/application/movie_detail_action_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_poster_image.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_feedback.dart';

part 'series_detail_header_widgets.dart';
part 'series_detail_overview_cast.dart';
part 'series_detail_episodes.dart';

/// 剧集/动漫详情页：暗色金调整页视图（对应 Movies Module Design 的
/// Detail.tsx 剧集形态：压题图 + 海报/元信息 + PLAY + 简介/CAST/季集折叠）。
/// 路由 `/video/series/:seriesId`。
class SeriesDetailPage extends ConsumerWidget {
  const SeriesDetailPage({required this.seriesId, super.key});

  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(movieSeriesDetailProvider(seriesId));
    return detailAsync.when(
      loading:
          () => const _DarkScaffold(
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      error:
          (error, _) => _DarkScaffold(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      movieErrorMessage(error),
                      textAlign: TextAlign.center,
                      style: MovieDetailTheme.body(
                        14,
                        color: MovieDetailTheme.secondaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: MovieRedesignPalette.borderRadius,
                      side: const BorderSide(color: MovieDetailTheme.mutedText),
                    ),
                    child: InkWell(
                      onTap:
                          () => ref.invalidate(
                            movieSeriesDetailProvider(seriesId),
                          ),
                      borderRadius: MovieRedesignPalette.borderRadius,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          'RETRY',
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: AppTypography.bodySmall,
                            color: MovieDetailTheme.secondaryText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      data:
          (detail) => _SeriesDetailView(
            key: ValueKey(detail.series.id),
            detail: detail,
          ),
    );
  }
}

class _DarkScaffold extends StatelessWidget {
  const _DarkScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: MovieDetailTheme.background, body: child);
  }
}

class _SeriesDetailView extends ConsumerStatefulWidget {
  const _SeriesDetailView({required this.detail, super.key});

  final MovieSeriesDetail detail;

  @override
  ConsumerState<_SeriesDetailView> createState() => _SeriesDetailViewState();
}

class _SeriesDetailViewState extends ConsumerState<_SeriesDetailView> {
  String? _openSeasonId;
  bool _resolvingPlay = false;
  bool _editMode = false;
  String? _initializedForId;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _overviewController = TextEditingController();

  MovieSeries get series => widget.detail.series;

  @override
  void dispose() {
    _titleController.dispose();
    _overviewController.dispose();
    super.dispose();
  }

  /// 进入编辑态时按当前系列初始化输入框（按系列 id 防重初始化）。
  void _ensureControllers(MovieSeries series) {
    if (_initializedForId == series.id) {
      return;
    }
    _initializedForId = series.id;
    _titleController.text = series.title;
    _overviewController.text = series.overview ?? '';
  }

  Future<void> _saveEdits(MovieSeries series) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      return;
    }
    final actions = ref.read(movieDetailActionProvider.notifier);
    try {
      final saved = await actions.save(() async {
        await ref
            .read(movieCenterControllerProvider.notifier)
            .updateSeriesMetadata(
              seriesId: series.id,
              title: title,
              overview: _overviewController.text.trim(),
            );
      });
      if (!saved || !mounted) {
        return;
      }
      ref.invalidate(movieSeriesDetailProvider(series.id));
      setState(() => _editMode = false);
    } on Exception catch (error) {
      if (mounted) {
        showMovieFeedback(context, movieErrorMessage(error), isError: true);
      }
    }
  }

  List<MovieSeason> get _sortedSeasons {
    final seasons = [...widget.detail.seasons]
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return seasons;
  }

  Future<void> _toggleFavorite(bool current) async {
    final actions = ref.read(movieDetailActionProvider.notifier);
    try {
      await actions.toggleFavorite(
        current: current,
        apply: (_) async {
          await ref
              .read(movieCenterControllerProvider.notifier)
              .toggleSeriesFavorite(series.id);
        },
      );
      if (!mounted) {
        return;
      }
      ref.invalidate(seriesFavoriteProvider(series.id));
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      showMovieFeedback(context, movieErrorMessage(error), isError: true);
    }
  }

  /// PLAY：播放最早一季的第一个可播分集（分集续播由播放器按分集进度处理）。
  Future<void> _playFirstEpisode() async {
    if (_resolvingPlay) {
      return;
    }
    final seasons = _sortedSeasons;
    if (seasons.isEmpty) {
      return;
    }
    setState(() => _resolvingPlay = true);
    try {
      for (final season in seasons) {
        final seasonDetail = await ref.read(
          movieSeasonDetailProvider(
            SeasonKey(seriesId: series.id, seasonNumber: season.seasonNumber),
          ).future,
        );
        final playable = seasonDetail.episodes.where(
          (episode) => episode.availabilityStatus == 'AVAILABLE',
        );
        if (playable.isEmpty) {
          continue;
        }
        if (!mounted) {
          return;
        }
        context.push('/video/${playable.first.id}/play');
        return;
      }
    } on Exception catch (error) {
      if (mounted) {
        showMovieFeedback(context, movieErrorMessage(error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _resolvingPlay = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllers(series);
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final canEdit = user?.permissions.contains('media:write') ?? false;
    final actionState = ref.watch(movieDetailActionProvider);
    final favoriteAsync = ref.watch(seriesFavoriteProvider(series.id));
    final favorited =
        actionState.favoritedOverride ?? favoriteAsync.asData?.value ?? false;
    final saving = actionState.saving;
    return Scaffold(
      backgroundColor: MovieDetailTheme.background,
      // 压题图与内容同处一个滚动域：-64px 海报叠压不会被滚动区上边缘裁切。
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Backdrop(
              backdropUrl: series.backdropImageUrl ?? series.posterImageUrl,
              backdropCacheKey: 'movie-series-backdrop:${series.id}',
              favorited: favorited,
              canEdit: canEdit && !saving,
              editMode: _editMode,
              saving: saving,
              onBack: () => exitDetailRoute(context, fallbackRoute: '/video'),
              onToggleEdit: () {
                if (_editMode) {
                  unawaited(_saveEdits(series));
                } else {
                  setState(() {
                    _editMode = true;
                  });
                }
              },
              onToggleFavorite: () => unawaited(_toggleFavorite(favorited)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1024),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -64),
                        child: _SeriesPosterMetaRow(
                          series: series,
                          seasonCount: widget.detail.seasons.length,
                          editMode: _editMode,
                          titleController: _titleController,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _SeriesPlayButton(
                        onTap: _playFirstEpisode,
                        busy: _resolvingPlay,
                      ),
                      const SizedBox(height: 32),
                      _SeriesOverviewText(
                        overview: series.overview ?? '',
                        editMode: _editMode,
                        overviewController: _overviewController,
                      ),
                      if (widget.detail.cast.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        const _SeriesCastHeader(),
                        const SizedBox(height: 16),
                        _SeriesCastGrid(cast: widget.detail.cast),
                      ],
                      const SizedBox(height: 32),
                      const _SeriesEpisodesHeader(),
                      const SizedBox(height: 16),
                      _SeasonAccordion(
                        seriesId: series.id,
                        seasons: _sortedSeasons,
                        openSeasonId: _openSeasonId,
                        onToggle: (seasonId) {
                          setState(() {
                            _openSeasonId =
                                _openSeasonId == seasonId ? null : seasonId;
                          });
                        },
                      ),
                      const SizedBox(height: 48),
                    ],
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
