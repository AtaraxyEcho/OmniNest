import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/residual_chrome_colors.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_common_widgets.dart';
import 'package:omninest/features/video/presentation/widgets/movie_poster_image.dart';

String _formatProgress(int position, int duration) {
  String fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  if (duration > 0) return '${fmt(position)} / ${fmt(duration)}';
  return fmt(position);
}

class ContinueSection extends StatelessWidget {
  const ContinueSection({required this.items, super.key});

  final List<MovieContinueWatching> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MovieSectionHeading(
          title: AppLocalizations.of(context).videoSectionContinueWatching,
          subtitle: AppLocalizations.of(context).videoContinueSubtitle,
        ),
        const SizedBox(height: 22),
        if (items.isEmpty)
          EmptyMovieState(
            message: AppLocalizations.of(context).videoNoContinueRecord,
          )
        else if (MediaQuery.sizeOf(context).width < 600)
          ContinueCard(item: items.first, width: double.infinity)
        else
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [for (final item in items) ContinueCard(item: item)],
          ),
      ],
    );
  }
}

class ContinueCard extends StatelessWidget {
  const ContinueCard({required this.item, this.width = 330, super.key});

  final MovieContinueWatching item;
  final double width;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(MobileLayoutTokens.radius),
      onTap: () => context.go('/video/${item.id}/play'),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.videoColors.surfaceContainerHigh.withValues(
            alpha: 0.78,
          ),
          borderRadius: BorderRadius.circular(MobileLayoutTokens.radius),
          border: Border.all(
            color: context.videoColors.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: context.videoColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.posterUrl != null)
                      MoviePosterImage(
                        imageUrl: item.posterUrl,
                        cacheKey: 'movie-poster:${item.id}',
                        cacheWidth: 400,
                      ),
                    // 渐变遮罩
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.70),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: MovieChromeColors.continueLabelOnImage,
                        size: 48,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.videoColors.onSurface,
                fontSize: AppTypography.titleMedium,
                height: 20 / 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: (item.progressPercent / 100).clamp(0, 1),
                backgroundColor: context.videoColors.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(context.videoColors.primary),
              ),
            ),
            SizedBox(height: 6),
            Text(
              _formatProgress(item.positionSeconds, item.durationSeconds),
              style: TextStyle(
                color: context.videoColors.onSurfaceVariant.withValues(
                  alpha: 0.72,
                ),
                fontSize: AppTypography.bodySmall,
                height: 16 / 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
