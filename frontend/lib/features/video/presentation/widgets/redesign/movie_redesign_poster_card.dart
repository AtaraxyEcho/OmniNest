import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_progress_bar.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_status.dart';

/// 海报网格度量：按可用宽度决定列数与单元纵横比。
class MovieRedesignGridMetrics {
  const MovieRedesignGridMetrics._({
    required this.columns,
    required this.spacing,
    required this.childAspectRatio,
  });

  final int columns;
  final double spacing;
  final double childAspectRatio;

  /// 单元高度 = 海报宽高比 2:3 + 文本区固定高度。
  static const double _textExtent = 64;

  /// 按内容宽度解析列数（对应原型 grid-cols-3/4/5/6 断点）。
  factory MovieRedesignGridMetrics.resolve(double width) {
    final (columns, spacing) = switch (width) {
      < 480 => (3, 10.0),
      < 768 => (3, 12.0),
      < 1024 => (4, 12.0),
      < 1280 => (5, 14.0),
      _ => (6, 16.0),
    };
    final cellWidth = (width - spacing * (columns - 1)) / columns;
    final cellHeight = cellWidth * 1.5 + _textExtent;
    return MovieRedesignGridMetrics._(
      columns: columns,
      spacing: spacing,
      childAspectRatio: cellWidth / cellHeight,
    );
  }
}

/// 新版海报卡：2:3 海报 + hover 播放浮层 + 进度条 + 双语标题 + 等宽元信息行。
class MovieRedesignPosterCard extends StatefulWidget {
  const MovieRedesignPosterCard({
    required this.item,
    required this.onDetail,
    this.onPlay,
    this.progressPercent,
    super.key,
  });

  final MovieVideoItem item;

  /// 点击卡片（海报或文本区）打开详情。
  final ValueChanged<MovieVideoItem> onDetail;

  /// hover 播放按钮；为空时不显示浮层播放入口。
  final ValueChanged<MovieVideoItem>? onPlay;

  /// 观看进度百分比 0-100，为空时不显示进度条。
  final double? progressPercent;

  @override
  State<MovieRedesignPosterCard> createState() =>
      _MovieRedesignPosterCardState();
}

class _MovieRedesignPosterCardState extends State<MovieRedesignPosterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    final onPlay = widget.onPlay;
    final originalTitle = _originalTitle(item);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Material(
              color: palette.muted,
              borderRadius: MovieRedesignPalette.borderRadius,
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedScale(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    scale: _hovered ? 1.05 : 1.0,
                    child: _PosterImage(item: item),
                  ),
                  if (onPlay != null)
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: _hovered ? 1 : 0,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _PlayButton(onPlay: () => onPlay(item)),
                            const SizedBox(height: 8),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => widget.onDetail(item),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    l10n.videoRedesignDetail,
                                    style: text.mono(
                                      size: 10,
                                      color: Colors.white.withValues(
                                        alpha: 0.70,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (widget.progressPercent != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: MovieRedesignProgressBar(
                        value: widget.progressPercent! / 100,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.body(
                    size: 13,
                    weight: FontWeight.w500,
                    color: _hovered ? palette.primary : palette.foreground,
                    height: 16 / 13,
                  ),
                ),
                if (originalTitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    originalTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.body(
                      size: 11,
                      color: palette.mutedForeground,
                      height: 14 / 11,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.year,
                        style: text.mono(size: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _MetaDot(palette: palette),
                    if (item.rating != null) ...[
                      Icon(
                        Icons.star,
                        size: 10,
                        color: MovieRedesignPalette.star,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        item.rating!.toStringAsFixed(1),
                        style: text.mono(size: 10),
                      ),
                      _MetaDot(palette: palette),
                    ],
                    MovieRedesignStatusDot(
                      status: movieRedesignStatusFrom(item.metadataStatus),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _originalTitle(MovieVideoItem item) {
    final original = item.originalTitle;
    if (original == null || original.trim().isEmpty) {
      return null;
    }
    if (original.trim().toLowerCase() == item.title.trim().toLowerCase()) {
      return null;
    }
    return original;
  }
}

class _MetaDot extends StatelessWidget {
  const _MetaDot({required this.palette});

  final MovieRedesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text('·', style: context.movieRedesignText.mono(size: 10)),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onPlay});

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    return Material(
      color: palette.primary,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPlay,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context) {
    final posterUrl = item.posterImageUrl;
    if (posterUrl == null || posterUrl.isEmpty) {
      return const SizedBox.expand();
    }
    return Image.network(
      posterUrl,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
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

/// 非滚动区的静态海报网格。
class MovieRedesignPosterGrid extends StatelessWidget {
  const MovieRedesignPosterGrid({
    required this.items,
    required this.onDetail,
    this.onPlay,
    super.key,
  });

  final List<MovieVideoItem> items;
  final ValueChanged<MovieVideoItem> onDetail;
  final ValueChanged<MovieVideoItem>? onPlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = MovieRedesignGridMetrics.resolve(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: metrics.columns,
            crossAxisSpacing: metrics.spacing,
            mainAxisSpacing: metrics.spacing,
            childAspectRatio: metrics.childAspectRatio,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return MovieRedesignPosterCard(
              item: item,
              onDetail: onDetail,
              onPlay: onPlay,
            );
          },
        );
      },
    );
  }
}

/// 滚动区内的海报 Sliver 网格。
class MovieRedesignPosterSliverGrid extends StatelessWidget {
  const MovieRedesignPosterSliverGrid({
    required this.items,
    required this.onDetail,
    this.onPlay,
    super.key,
  });

  final List<MovieVideoItem> items;
  final ValueChanged<MovieVideoItem> onDetail;
  final ValueChanged<MovieVideoItem>? onPlay;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final metrics = MovieRedesignGridMetrics.resolve(
          constraints.crossAxisExtent,
        );
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: metrics.columns,
            crossAxisSpacing: metrics.spacing,
            mainAxisSpacing: metrics.spacing,
            childAspectRatio: metrics.childAspectRatio,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final item = items[index];
            return MovieRedesignPosterCard(
              item: item,
              onDetail: onDetail,
              onPlay: onPlay,
            );
          }, childCount: items.length),
        );
      },
    );
  }
}
