import 'package:cached_network_image/cached_network_image.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_category_bars.dart';
import 'package:omninest/features/video/presentation/widgets/movie_common_widgets.dart';
import 'package:omninest/features/video/presentation/widgets/movie_hero_carousel.dart';
import 'package:omninest/features/video/presentation/widgets/movie_filters.dart';
import 'package:omninest/features/video/presentation/widgets/movie_poster_grid.dart';
import 'package:omninest/features/video/presentation/widgets/movie_responsive_layout.dart';
import 'package:omninest/features/video/presentation/widgets/movie_styles.dart';

part 'movie_series_catalog.dart';

enum SeriesCatalogVariant { tv, anime }

List<MovieSeries> seriesHeroItems(List<MovieSeries> series) {
  final withImage = [
    for (final s in series)
      if (s.heroImageUrl != null) s,
  ];
  final source = withImage.isEmpty ? series : withImage;
  final sorted = List<MovieSeries>.from(source)..sort((a, b) {
    final aDate = a.firstAirDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.firstAirDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  });
  return sorted.take(9).toList(growable: false);
}

double seriesHeroHeight(double width) {
  if (width >= 3200) return 780;
  if (width >= 2560) return 720;
  if (width >= 1920) return 620;
  if (width >= 1600) return 540;
  if (width >= 1280) return 460;
  if (width >= 960) return 380;
  if (width >= 720) return 320;
  return 280;
}

/// 剧集主页面 — 轮播 + 筛选栏 + 网格 + 分类栏
class SeriesSection extends ConsumerWidget {
  const SeriesSection({
    required this.allSeries,
    required this.series,
    required this.episodes,
    this.title,
    this.subtitle,
    this.categoryFilter,
    this.variant = SeriesCatalogVariant.tv,
    super.key,
  });

  final List<MovieSeries> allSeries;
  final List<MovieSeries> series;
  final List<MovieVideoItem> episodes;
  final String? title;
  final String? subtitle;
  final bool Function(MovieVideoItem)? categoryFilter;
  final SeriesCatalogVariant variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(movieCenterControllerProvider).asData?.value;
    final heroItems = seriesHeroItems(series);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SeriesHeroCarousel(items: heroItems),
        const SizedBox(height: 24),
        MovieSectionHeading(
          title: title ?? AppLocalizations.of(context).videoSeriesLibrary,
          subtitle:
              subtitle ??
              AppLocalizations.of(context).videoSeriesLibrarySubtitle,
        ),
        const SizedBox(height: 22),
        const MovieFilterBar(),
        const SizedBox(height: 24),
        if (series.isEmpty)
          EmptyMovieState(message: AppLocalizations.of(context).videoNoSeries)
        else
          SeriesPosterGrid(series: series, variant: variant),
        if (series.isEmpty && episodes.isNotEmpty) ...[
          const SizedBox(height: 28),
          MoviePosterGrid(items: episodes),
        ],
        if (allSeries.isNotEmpty) ...[
          const SizedBox(height: 28),
          SeriesCategoryBars(series: allSeries, variant: variant),
        ],
        if (state != null) ...[
          const SizedBox(height: 28),
          MovieCategoryBars(
            items:
                state.movies
                    .where(
                      categoryFilter ?? (item) => item.mediaType != 'MOVIE',
                    )
                    .toList(),
            viewMode: state.viewMode,
            onViewMore:
                ref.read(movieCenterControllerProvider.notifier).toggleGenre,
          ),
        ],
      ],
    );
  }
}

// ──────────────────────────────────────────────
// 剧集 3D 轮播
// ──────────────────────────────────────────────

/// 剧集 Hero 轮播：基于通用 [MediaHeroCarousel] 的剧集侧封装。
class SeriesHeroCarousel extends StatelessWidget {
  const SeriesHeroCarousel({required this.items, super.key});

  final List<MovieSeries> items;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final s in items)
        MediaHeroEntry(
          id: s.id,
          backdropUrl: s.backdropImageUrl,
          posterUrl: s.posterImageUrl,
          overlay: _SeriesHeroOverlay(item: s),
        ),
    ];
    return MediaHeroCarousel(
      entries: entries,
      onOpen: (id) => context.push('/video/series/$id'),
      heightFor: seriesHeroHeight,
      compactLayout: false,
      sideDim: 0.60,
      scrimGradient: true,
      overlayWithinCenterCard: false,
      activeIndicatorColor: context.videoColors.primary,
      inactiveIndicatorColor: context.videoColors.onSurface.withValues(
        alpha: 0.36,
      ),
      emptyPlaceholder: const _SeriesHeroPlaceholder(),
    );
  }
}

class _SeriesHeroPlaceholder extends StatelessWidget {
  const _SeriesHeroPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: ValueKey('series-hero-placeholder'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF201F3B),
            Color(0xFF35213B),
            context.videoColors.surface,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
    );
  }
}

class _SeriesHeroOverlay extends StatelessWidget {
  const _SeriesHeroOverlay({required this.item});

  final MovieSeries? item;

  @override
  Widget build(BuildContext context) {
    final current = item;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child:
          current == null
              ? const _SeriesHeroContentFallback(
                key: ValueKey('series-hero-empty'),
              )
              : _SeriesHeroContent(key: ValueKey(current.id), item: current),
    );
  }
}

class _SeriesHeroContentFallback extends StatelessWidget {
  const _SeriesHeroContentFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SeriesHeroPill(
          label: AppLocalizations.of(context).videoSeriesFeatured,
        ),
        SizedBox(height: 12),
        Text(
          'Series Center',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.videoColors.onSurface,
            fontSize: 32,
            height: 38 / 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Browse your TV series library and start watching.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.videoColors.onSurfaceVariant,
            fontSize: 15,
            height: 22 / 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _SeriesHeroContent extends StatelessWidget {
  const _SeriesHeroContent({super.key, required this.item});

  final MovieSeries item;

  static const _textShadow = Shadow(
    color: Color(0x99000000),
    blurRadius: 12,
    offset: Offset(0, 2),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SeriesHeroPill(
              label: AppLocalizations.of(context).videoSeriesFeatured,
            ),
            _SeriesHeroPill(label: item.year),
            if (item.contentRating != null)
              _SeriesHeroPill(label: item.contentRating!),
          ],
        ),
        SizedBox(height: 14),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.videoColors.onSurface,
            fontSize: 40,
            height: 46 / 40,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            shadows: [_textShadow],
          ),
        ),
        SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520),
          child: Text(
            item.overview ?? 'A curated series ready for your next binge.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.videoColors.onSurfaceVariant.withValues(
                alpha: 0.92,
              ),
              fontSize: 15,
              height: 22 / 15,
              fontWeight: FontWeight.w500,
              shadows: const [_textShadow],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed:
                  item.id.isEmpty
                      ? null
                      : () => context.push('/video/series/${item.id}'),
              icon: const Icon(Icons.tv_rounded),
              label: const Text('View Series'),
              style: movieFilledButtonStyle(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _SeriesHeroPill extends StatelessWidget {
  const _SeriesHeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.videoColors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: context.videoColors.primary.withValues(alpha: 0.30),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.videoColors.primary,
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
