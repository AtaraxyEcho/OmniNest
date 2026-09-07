import 'package:flutter/material.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_progress_bar.dart';

/// 继续观看卡片的辅助文案与回调。
class MovieRedesignContinueItem {
  const MovieRedesignContinueItem({
    required this.data,
    required this.timeText,
    this.onPlay,
    this.onDetail,
  });

  final MovieContinueWatching data;
  final String timeText;
  final VoidCallback? onPlay;
  final VoidCallback? onDetail;
}

/// 新版继续观看横条：衬线小标题 + 2/4 列 16:9 进度卡片。
class MovieRedesignContinueStrip extends StatelessWidget {
  const MovieRedesignContinueStrip({
    required this.items,
    required this.title,
    this.subtitleEn,
    super.key,
  });

  final List<MovieRedesignContinueItem> items;
  final String title;
  final String? subtitleEn;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 640 ? 4 : 2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title, style: context.movieRedesignText.display(size: 18)),
              if (subtitleEn != null) ...[
                const SizedBox(width: 8),
                Text(
                  subtitleEn!,
                  style: context.movieRedesignText.body(
                    size: 12,
                    color: context.movieRedesign.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final gap = width >= 640 ? 12.0 : 8.0;
              final cardWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: cardWidth,
                      child: MovieRedesignContinueCard(item: item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 新版继续观看卡片：16:9 画面 + 底部进度条 + 标题/时间/百分比。
class MovieRedesignContinueCard extends StatefulWidget {
  const MovieRedesignContinueCard({required this.item, super.key});

  final MovieRedesignContinueItem item;

  @override
  State<MovieRedesignContinueCard> createState() =>
      _MovieRedesignContinueCardState();
}

class _MovieRedesignContinueCardState extends State<MovieRedesignContinueCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final data = widget.item.data;
    final posterUrl = data.posterUrl;
    final hasAction = widget.item.onPlay != null;
    return MouseRegion(
      cursor: hasAction ? SystemMouseCursors.click : MouseCursor.defer,
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
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.item.onPlay,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedScale(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                      scale: _hovered ? 1.05 : 1.0,
                      child: _ContinueImage(posterUrl: posterUrl),
                    ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: _hovered ? 1 : 0,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.40),
                        alignment: Alignment.center,
                        child:
                            _hovered
                                ? Material(
                                  color: palette.primary,
                                  shape: const CircleBorder(),
                                  child: const SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                                : const SizedBox.shrink(),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: MovieRedesignProgressBar(
                        value: (data.progressPercent / 100).clamp(0.0, 1.0),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.body(
                        size: 12,
                        weight: FontWeight.w500,
                        color: palette.secondaryForeground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            widget.item.timeText,
                            style: text.mono(size: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${data.progressPercent.round()}%',
                          style: text.mono(size: 10, color: palette.primary),
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
    );
  }
}

class _ContinueImage extends StatelessWidget {
  const _ContinueImage({this.posterUrl});

  final String? posterUrl;

  @override
  Widget build(BuildContext context) {
    final url = posterUrl;
    if (url == null || url.isEmpty) {
      return const SizedBox.expand();
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return const SizedBox.expand();
      },
    );
  }
}
