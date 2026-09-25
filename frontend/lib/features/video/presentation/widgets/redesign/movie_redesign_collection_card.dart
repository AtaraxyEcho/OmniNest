import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/residual_chrome_colors.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_poster_image.dart';

/// 合集卡片数据。
class MovieRedesignCollectionCardData {
  const MovieRedesignCollectionCardData({
    required this.name,
    this.nameEn,
    required this.count,
    this.coverUrl,
    this.onTap,
  });

  final String name;
  final String? nameEn;
  final int count;
  final String? coverUrl;
  final VoidCallback? onTap;
}

/// 新版合集卡：横向封面 + 深色遮罩 + 名称/计数页脚。
class MovieRedesignCollectionCard extends StatefulWidget {
  const MovieRedesignCollectionCard({required this.data, super.key});

  final MovieRedesignCollectionCardData data;

  @override
  State<MovieRedesignCollectionCard> createState() =>
      _MovieRedesignCollectionCardState();
}

class _MovieRedesignCollectionCardState
    extends State<MovieRedesignCollectionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final data = widget.data;
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return MouseRegion(
      cursor: data.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: MovieRedesignPalette.borderRadius,
          side: BorderSide(
            color: _hovered ? palette.foreground : palette.border,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: data.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: wide ? 128 : 112,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedScale(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                      scale: _hovered ? 1.05 : 1.0,
                      child: _CollectionImage(
                        url: data.coverUrl,
                        cacheKey: 'movie-collection:${data.name}',
                      ),
                    ),
                    const ColoredBox(
                      color: MovieChromeColors.collectionCardScrim,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.body(
                        size: 14,
                        weight: FontWeight.w500,
                        color: _hovered ? palette.primary : palette.foreground,
                      ),
                    ),
                    if (data.nameEn != null && data.nameEn!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        data.nameEn!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.body(
                          size: 12,
                          color: palette.mutedForeground,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(
                        context,
                      ).videoRedesignItemsCount(data.count),
                      style: text.mono(size: AppTypography.bodySmall),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionImage extends StatelessWidget {
  const _CollectionImage({this.url, this.cacheKey});

  final String? url;
  final String? cacheKey;

  @override
  Widget build(BuildContext context) {
    final coverUrl = url;
    if (coverUrl == null || coverUrl.isEmpty) {
      return ColoredBox(color: context.movieRedesign.muted);
    }
    return MoviePosterImage(
      imageUrl: coverUrl,
      cacheKey: cacheKey,
      cacheWidth: MoviePosterImage.decodeWidth(context, 180, cap: 480),
      fallback: ColoredBox(color: context.movieRedesign.muted),
    );
  }
}
