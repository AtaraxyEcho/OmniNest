import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_poster_image.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_progress_bar.dart';

/// 继续观看卡片的辅助文案与回调。
///
/// [MovieContinueWatching.title] 对分集已是系列名（后端转换器统一作品名），
/// 卡片主标题直接使用；集数用 [episodeLabel] 表达。
class MovieRedesignContinueItem {
  const MovieRedesignContinueItem({
    required this.data,
    required this.timeText,
    this.episodeLabel,
    this.onPlay,
    this.onDetail,
  });

  final MovieContinueWatching data;
  final String timeText;

  /// 如 `S02E09`；电影为空。
  final String? episodeLabel;
  final VoidCallback? onPlay;
  final VoidCallback? onDetail;
}

/// 新版继续观看横条：衬线小标题 + 横向滚动 16:9 进度卡片（隐藏滚动条）。
class MovieRedesignContinueStrip extends StatelessWidget {
  const MovieRedesignContinueStrip({
    required this.items,
    required this.title,
    this.subtitleEn,
    this.onViewAll,
    super.key,
  });

  final List<MovieRedesignContinueItem> items;
  final String title;
  final String? subtitleEn;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gap = width >= 640 ? 12.0 : 8.0;
    // 横滑卡宽：约一屏 2/3.5 张，保证露出下一张的可滚动暗示。
    final cardWidth =
        width >= 1024
            ? 280.0
            : width >= 640
            ? 240.0
            : 200.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                title,
                style: context.movieRedesignText.display(
                  size: AppTypography.titleLarge,
                ),
              ),
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
              const Spacer(),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  child: Text(
                    AppLocalizations.of(context).videoContinueViewAll,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: cardWidth * 9 / 16 + 72,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(right: 4),
                itemCount: items.length,
                separatorBuilder: (_, _) => SizedBox(width: gap),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: cardWidth,
                    child: MovieRedesignContinueCard(item: items[index]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 新版继续观看卡片：16:9 画面 + 底部进度条 + 标题/时间/百分比。
///
/// [compact] 对应原型电影页顶部的紧凑横条卡（xs 字号/32px 播放钮）；
/// false 对应继续观看整页卡（sm 字号/40px 播放钮/p-3 页脚）。
class MovieRedesignContinueCard extends StatefulWidget {
  const MovieRedesignContinueCard({
    required this.item,
    this.compact = true,
    super.key,
  });

  final MovieRedesignContinueItem item;
  final bool compact;

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
    final compact = widget.compact;
    final playSize = compact ? 32.0 : 40.0;
    final playIconSize = compact ? 18.0 : 20.0;
    final titleSize = compact ? 12.0 : 14.0;
    final metaSize = compact ? 10.0 : 12.0;
    final footerPadding =
        compact
            ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
            : const EdgeInsets.all(12);
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
        clipBehavior: Clip.hardEdge,
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
                      child: _ContinueImage(
                        posterUrl: posterUrl,
                        cacheKey: 'movie-poster:${data.id}',
                      ),
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
                                  child: SizedBox(
                                    width: playSize,
                                    height: playSize,
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      size: playIconSize,
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
                padding: footerPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.body(
                        size: titleSize,
                        weight: FontWeight.w500,
                        color: palette.secondaryForeground,
                      ),
                    ),
                    if (widget.item.episodeLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.item.episodeLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.mono(size: metaSize),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            widget.item.timeText,
                            style: text.mono(size: metaSize),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${data.progressPercent.round()}%',
                          style: text.mono(
                            size: metaSize,
                            color: palette.primary,
                          ),
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
  const _ContinueImage({this.posterUrl, this.cacheKey});

  final String? posterUrl;
  final String? cacheKey;

  @override
  Widget build(BuildContext context) {
    final url = posterUrl;
    if (url == null || url.isEmpty) {
      return const SizedBox.expand();
    }
    return MoviePosterImage(
      imageUrl: url,
      cacheKey: cacheKey,
      cacheWidth: MoviePosterImage.decodeWidth(context, 140, cap: 420),
      fallback: const SizedBox.expand(),
    );
  }
}
