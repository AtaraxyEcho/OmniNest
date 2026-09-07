import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_progress_bar.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_status.dart';

/// 海报卡片视图模型：统一电影条目与系列两类数据源。
@immutable
class MovieRedesignCardData {
  const MovieRedesignCardData({
    required this.id,
    required this.title,
    this.subtitle,
    required this.year,
    this.rating,
    required this.status,
    this.posterUrl,
    this.progressPercent,
    this.onTap,
    this.onPlay,
  });

  final String id;
  final String title;

  /// 英文原标题，与主标题相同时不展示。
  final String? subtitle;
  final String year;
  final double? rating;
  final MovieRedesignStatus status;
  final String? posterUrl;

  /// 观看进度百分比 0-100，为空时不显示进度条。
  final double? progressPercent;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  /// 从影视条目构建。
  factory MovieRedesignCardData.fromVideoItem(MovieVideoItem item) {
    return MovieRedesignCardData(
      id: item.id,
      title: item.title,
      subtitle: _distinctOriginalTitle(item.title, item.originalTitle),
      year: item.year,
      rating: item.rating,
      status: movieRedesignStatusFrom(item.metadataStatus),
      posterUrl: item.posterImageUrl,
    );
  }

  /// 复制并覆盖回调。
  MovieRedesignCardData copyWith({VoidCallback? onTap, VoidCallback? onPlay}) {
    return MovieRedesignCardData(
      id: id,
      title: title,
      subtitle: subtitle,
      year: year,
      rating: rating,
      status: status,
      posterUrl: posterUrl,
      progressPercent: progressPercent,
      onTap: onTap ?? this.onTap,
      onPlay: onPlay ?? this.onPlay,
    );
  }

  /// 从系列构建。
  factory MovieRedesignCardData.fromSeries(MovieSeries series) {
    return MovieRedesignCardData(
      id: series.id,
      title: series.title,
      subtitle: _distinctOriginalTitle(series.title, series.originalTitle),
      year: series.year,
      rating: series.rating,
      status: movieRedesignStatusFrom(series.metadataStatus),
      posterUrl: series.posterImageUrl,
    );
  }

  static String? _distinctOriginalTitle(String title, String? original) {
    final trimmed = original?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (trimmed.toLowerCase() == title.trim().toLowerCase()) {
      return null;
    }
    return trimmed;
  }
}

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
  static const double _textExtent = 72;

  /// 列数/间距按视口宽（对应原型 md/lg/xl 与 gap-3 sm:gap-4），
  /// 单元尺寸按内容宽（扣除侧栏后的实际网格宽度）。
  factory MovieRedesignGridMetrics.resolve({
    required double viewportWidth,
    required double contentWidth,
  }) {
    final columns = switch (viewportWidth) {
      < 768 => 3,
      < 1024 => 4,
      < 1280 => 5,
      _ => 6,
    };
    final spacing = movieRedesignAtSm(viewportWidth) ? 16.0 : 12.0;
    final cellWidth =
        (contentWidth - spacing * (columns - 1)) / columns;
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
  const MovieRedesignPosterCard({required this.data, super.key});

  final MovieRedesignCardData data;

  @override
  State<MovieRedesignPosterCard> createState() =>
      _MovieRedesignPosterCardState();
}

class _MovieRedesignPosterCardState extends State<MovieRedesignPosterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    final onPlay = data.onPlay;
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
                    child: _PosterImage(posterUrl: data.posterUrl),
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
                            AnimatedScale(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              scale: _hovered ? 1.0 : 0.75,
                              child: _PlayButton(onPlay: onPlay),
                            ),
                            const SizedBox(height: 8),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: data.onTap,
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
                  if (data.progressPercent != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: MovieRedesignProgressBar(
                        value: data.progressPercent! / 100,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: InkWell(
              onTap: data.onTap ?? data.onPlay,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      // 原型 text-xs sm:text-sm。
                      final atSm = movieRedesignAtSm(
                        MediaQuery.sizeOf(context).width,
                      );
                      final titleSize = atSm ? 14.0 : 12.0;
                      final smallSize = atSm ? 12.0 : 10.0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.body(
                              size: titleSize,
                              weight: FontWeight.w500,
                              color:
                                  _hovered
                                      ? palette.primary
                                      : palette.foreground,
                              height: 16 / titleSize,
                            ),
                          ),
                          if (data.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              data.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.body(
                                size: smallSize,
                                color: palette.mutedForeground,
                                height: 14 / smallSize,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  data.year,
                                  style: text.mono(size: smallSize),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _MetaDot(palette: palette),
                              if (data.rating != null) ...[
                                Icon(
                                  Icons.star,
                                  size: 10,
                                  color: MovieRedesignPalette.star,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  data.rating!.toStringAsFixed(1),
                                  style: text.mono(size: smallSize),
                                ),
                                _MetaDot(palette: palette),
                              ],
                              MovieRedesignStatusDot(status: data.status),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
  const _PosterImage({this.posterUrl});

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
  const MovieRedesignPosterGrid({required this.items, super.key});

  final List<MovieRedesignCardData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = MovieRedesignGridMetrics.resolve(
          viewportWidth: MediaQuery.sizeOf(context).width,
          contentWidth: constraints.maxWidth,
        );
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
          itemBuilder:
              (context, index) => MovieRedesignPosterCard(data: items[index]),
        );
      },
    );
  }
}

/// 滚动区内的海报 Sliver 网格。
class MovieRedesignPosterSliverGrid extends StatelessWidget {
  const MovieRedesignPosterSliverGrid({required this.items, super.key});

  final List<MovieRedesignCardData> items;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final metrics = MovieRedesignGridMetrics.resolve(
          viewportWidth: MediaQuery.sizeOf(context).width,
          contentWidth: constraints.crossAxisExtent,
        );
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: metrics.columns,
            crossAxisSpacing: metrics.spacing,
            mainAxisSpacing: metrics.spacing,
            childAspectRatio: metrics.childAspectRatio,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => MovieRedesignPosterCard(data: items[index]),
            childCount: items.length,
          ),
        );
      },
    );
  }
}
