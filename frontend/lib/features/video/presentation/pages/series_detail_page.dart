import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_feedback.dart';

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
  bool? _favoritedOverride;
  bool _resolvingPlay = false;

  MovieSeries get series => widget.detail.series;

  List<MovieSeason> get _sortedSeasons {
    final seasons = [...widget.detail.seasons]
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return seasons;
  }

  Future<void> _toggleFavorite(bool current) async {
    final next = !current;
    setState(() => _favoritedOverride = next);
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .toggleSeriesFavorite(series.id);
      if (!mounted) {
        return;
      }
      ref.invalidate(seriesFavoriteProvider(series.id));
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _favoritedOverride = current);
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
    final favoriteAsync = ref.watch(seriesFavoriteProvider(series.id));
    final favorited =
        _favoritedOverride ?? favoriteAsync.asData?.value ?? false;
    return Scaffold(
      backgroundColor: MovieDetailTheme.background,
      // 压题图与内容同处一个滚动域：-64px 海报叠压不会被滚动区上边缘裁切。
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Backdrop(
              backdropUrl: series.backdropImageUrl ?? series.posterImageUrl,
              favorited: favorited,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/video');
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
                        ),
                      ),
                      const SizedBox(height: 32),
                      _SeriesPlayButton(
                        onTap: _playFirstEpisode,
                        busy: _resolvingPlay,
                      ),
                      const SizedBox(height: 32),
                      _SeriesOverviewText(overview: series.overview ?? ''),
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

class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.backdropUrl,
    required this.favorited,
    required this.onBack,
    required this.onToggleFavorite,
  });

  final String? backdropUrl;
  final bool favorited;
  final VoidCallback onBack;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 256,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdropUrl != null && backdropUrl!.isNotEmpty)
            Image.network(
              backdropUrl!,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.medium,
              errorBuilder:
                  (context, error, stackTrace) =>
                      const ColoredBox(color: MovieDetailTheme.surface),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                return const ColoredBox(color: MovieDetailTheme.surface);
              },
            )
          else
            const ColoredBox(color: MovieDetailTheme.surface),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.5, 1],
                colors: [
                  Colors.black26,
                  Colors.black54,
                  MovieDetailTheme.background,
                ],
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 20,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('←', style: MovieDetailBackTextStyle()),
                      const SizedBox(width: 8),
                      Text(
                        l10n.videoDetailBack,
                        style: MovieDetailTheme.mono(
                          AppTypography.bodySmall,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 20,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onToggleFavorite,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 22,
                    color: favorited ? MovieDetailTheme.accent : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 深链返回箭头的等宽文字样式。
class MovieDetailBackTextStyle extends TextStyle {
  const MovieDetailBackTextStyle()
    : super(
        inherit: true,
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: const ['NotoSansSC'],
        fontSize: AppTypography.bodySmall,
        color: MovieDetailTheme.secondaryText,
      );
}

class _SeriesPosterMetaRow extends StatelessWidget {
  const _SeriesPosterMetaRow({required this.series, required this.seasonCount});

  final MovieSeries series;
  final int seasonCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 112,
          height: 160,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: MovieDetailTheme.border),
          ),
          child: _CoverImage(url: series.posterImageUrl),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.title,
                  style: MovieDetailTheme.serif(
                    AppTypography.headlineLarge,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (series.rating != null)
                      Text(
                        series.rating!.toStringAsFixed(1),
                        style: MovieDetailTheme.mono(
                          12,
                          color: MovieDetailTheme.accent,
                        ),
                      ),
                    Text(
                      series.year,
                      style: MovieDetailTheme.mono(AppTypography.bodySmall),
                    ),
                    Text(
                      AppLocalizations.of(
                        context,
                      ).videoDetailSeasonCount(seasonCount),
                      style: MovieDetailTheme.mono(AppTypography.bodySmall),
                    ),
                    for (final genre in series.genres.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: MovieDetailTheme.border),
                        ),
                        child: Text(
                          genre,
                          style: MovieDetailTheme.mono(AppTypography.bodySmall),
                        ),
                      ),
                    _SeriesStatusChip(status: series.metadataStatus),
                  ],
                ),
                const SizedBox(height: 8),
                if (series.overview != null &&
                    series.overview!.trim().isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 672),
                    child: Text(
                      series.overview!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: MovieDetailTheme.body(
                        14,
                        color: MovieDetailTheme.secondaryText,
                        height: 1.6,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final resolved = url;
    if (resolved == null || resolved.isEmpty) {
      return const ColoredBox(color: MovieDetailTheme.surface);
    }
    return Image.network(
      resolved,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.medium,
      errorBuilder:
          (context, error, stackTrace) =>
              const ColoredBox(color: MovieDetailTheme.surface),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return const ColoredBox(color: MovieDetailTheme.surface);
      },
    );
  }
}

class _SeriesStatusChip extends StatelessWidget {
  const _SeriesStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toUpperCase();
    final (color, hasBackground) = switch (normalized) {
      'MATCHED' => (MovieDetailTheme.mutedText, false),
      'PENDING' => (MovieDetailTheme.statusPending, true),
      _ => (MovieDetailTheme.statusFailed, true),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:
            hasBackground ? color.withValues(alpha: 0.10) : Colors.transparent,
      ),
      child: Text(
        normalized,
        style: MovieDetailTheme.mono(AppTypography.bodySmall, color: color),
      ),
    );
  }
}

class _SeriesPlayButton extends StatelessWidget {
  const _SeriesPlayButton({required this.onTap, required this.busy});

  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MouseRegion(
      cursor: busy ? MouseCursor.defer : SystemMouseCursors.click,
      child: Material(
        color: busy ? MovieDetailTheme.mutedText : MovieDetailTheme.foreground,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(size: const Size(10, 12), painter: _PlayGlyph()),
                const SizedBox(width: 12),
                Text(
                  l10n.videoDetailPlay,
                  style: MovieDetailTheme.mono(
                    14,
                    color: MovieDetailTheme.background,
                    letterSpacing: 2,
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

class _PlayGlyph extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, size.height / 2)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(path, Paint()..color = MovieDetailTheme.background);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SeriesOverviewText extends StatelessWidget {
  const _SeriesOverviewText({required this.overview});

  final String overview;

  @override
  Widget build(BuildContext context) {
    if (overview.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 672),
      child: Text(
        overview,
        style: MovieDetailTheme.body(
          14,
          color: MovieDetailTheme.secondaryText,
          height: 1.6,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: MovieDetailTheme.mono(AppTypography.bodySmall, letterSpacing: 2),
    );
  }
}

class _SeriesCastHeader extends StatelessWidget {
  const _SeriesCastHeader();

  @override
  Widget build(BuildContext context) {
    return const _SectionHeader(label: 'CAST');
  }
}

class _SeriesCastGrid extends StatelessWidget {
  const _SeriesCastGrid({required this.cast});

  final List<MovieCastMember> cast;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 800 ? 3 : 2;
        const gap = 12.0;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final member in cast.take(12))
              SizedBox(
                width: itemWidth,
                child: Row(
                  children: [
                    _CastAvatar(
                      name: member.name,
                      profileUrl: member.profilePath,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MovieDetailTheme.body(
                              14,
                              color: MovieDetailTheme.foreground,
                            ),
                          ),
                          if (member.character != null &&
                              member.character!.isNotEmpty)
                            Text(
                              member.character!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MovieDetailTheme.mono(
                                AppTypography.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CastAvatar extends StatelessWidget {
  const _CastAvatar({required this.name, this.profileUrl});

  final String name;
  final String? profileUrl;

  @override
  Widget build(BuildContext context) {
    final url = profileUrl;
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: MovieDetailTheme.surface,
      ),
      child:
          url != null && url.isNotEmpty
              ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 96,
                errorWidget:
                    (context, error, stackTrace) => _CastInitials(name: name),
              )
              : _CastInitials(name: name),
    );
  }
}

class _CastInitials extends StatelessWidget {
  const _CastInitials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: MovieDetailTheme.mono(
          AppTypography.titleMedium,
          color: MovieDetailTheme.accent,
        ),
      ),
    );
  }
}

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
                  child: _CoverImage(url: episode.posterImageUrl),
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
