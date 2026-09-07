import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_hero_carousel.dart';

List<MovieVideoItem> movieHeroItems(List<MovieVideoItem> items) {
  final withImage = [
    for (final item in items)
      if (item.heroImageUrl != null) item,
  ];
  final source = withImage.isEmpty ? items : withImage;
  final sorted = List<MovieVideoItem>.from(source)..sort((a, b) {
    final aDate = a.releaseDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.releaseDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  });
  return sorted.take(9).toList(growable: false);
}

double movieHeroHeight(double width) {
  if (width >= 3200) return 780;
  if (width >= 2560) return 720;
  if (width >= 1920) return 620;
  if (width >= 1600) return 540;
  if (width >= 1280) return 460;
  if (width >= 960) return 380;
  if (width >= 720) return 320;
  if (width >= 480) return 240;
  return 200;
}

/// 电影 Hero 轮播：基于通用 [MediaHeroCarousel] 的电影侧封装。
class MovieHeroCarousel extends StatelessWidget {
  const MovieHeroCarousel({required this.items, super.key});

  final List<MovieVideoItem> items;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final item in items)
        MediaHeroEntry(
          id: item.id,
          backdropUrl: item.backdropImageUrl,
          posterUrl: item.posterImageUrl,
          overlay: _MovieHeroOverlay(item: item),
        ),
    ];
    return MediaHeroCarousel(
      entries: entries,
      onOpen: (id) => context.push('/video/$id'),
      heightFor: movieHeroHeight,
      compactLayout: true,
      overlayWithinCenterCard: true,
      emptyPlaceholder: const _HeroPlaceholder(),
    );
  }
}

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      key: ValueKey('movie-hero-placeholder'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF201F3B), Color(0xFF35213B), Color(0xFF1A1825)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
    );
  }
}

class _MovieHeroOverlay extends StatelessWidget {
  const _MovieHeroOverlay({required this.item});

  final MovieVideoItem? item;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final current = item;
    return AnimatedSwitcher(
      duration:
          disableAnimations ? Duration.zero : const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child:
          current == null
              ? const _HeroContentFallback(key: ValueKey('movie-hero-empty'))
              : _HeroContent(key: ValueKey(current.id), item: current),
    );
  }
}

class _HeroContentFallback extends StatelessWidget {
  const _HeroContentFallback({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeroPill(label: l10n.videoHeroFeatured),
        const SizedBox(height: 12),
        Text(
          l10n.videoHeroCenterTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            height: 38 / 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.videoHeroCenterSubtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: 15,
            height: 22 / 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({super.key, required this.item});

  final MovieVideoItem item;

  static const _textShadow = Shadow(
    color: Color(0x99000000),
    blurRadius: 12,
    offset: Offset(0, 2),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;
    final titleFontSize = isNarrow ? 18.0 : 40.0;
    final titleHeight = isNarrow ? 24.0 / 18.0 : 46.0 / 40.0;
    final descFontSize = isNarrow ? 11.0 : 15.0;
    final descHeight = isNarrow ? 15.0 / 11.0 : 22.0 / 15.0;
    final descMaxLines = isNarrow ? 1 : 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _HeroPill(label: l10n.videoHeroFeatured),
            _HeroPill(
              label:
                  item.mediaType == 'MOVIE'
                      ? l10n.videoHeroMovie
                      : l10n.videoHeroTv,
            ),
            _HeroPill(label: item.year),
          ],
        ),
        SizedBox(height: isNarrow ? 8 : 14),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: titleFontSize,
            height: titleHeight,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
            shadows: [_textShadow],
          ),
        ),
        SizedBox(height: isNarrow ? 6 : 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isNarrow ? screenWidth - 40 : 520,
          ),
          child: Text(
            item.overview ?? l10n.videoHeroFallbackOverview,
            maxLines: descMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: descFontSize,
              height: descHeight,
              fontWeight: FontWeight.w500,
              shadows: const [_textShadow],
            ),
          ),
        ),
        SizedBox(height: isNarrow ? 6 : 18),
        FilledButton.icon(
          onPressed:
              item.id.isEmpty
                  ? null
                  : () => context.go('/video/${item.id}/play'),
          icon: Icon(Icons.play_arrow_rounded, size: isNarrow ? 16 : 18),
          label: Text(l10n.videoHeroWatchNow),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF171717),
            padding:
                isNarrow
                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                    : const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            textStyle: TextStyle(
              fontSize: isNarrow ? 11 : 14,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
