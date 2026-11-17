import 'package:flutter/foundation.dart';

/// 电影和动漫竖版封面网格的响应式度量。
@immutable
class MoviePosterGridMetrics {
  const MoviePosterGridMetrics({
    required this.columns,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.childAspectRatio,
    required this.compact,
  });

  factory MoviePosterGridMetrics.resolve(double width) {
    if (width < 480) {
      return const MoviePosterGridMetrics(
        columns: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 16,
        childAspectRatio: 0.60,
        compact: true,
      );
    }
    if (width < 700) {
      return const MoviePosterGridMetrics(
        columns: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 18,
        childAspectRatio: 0.59,
        compact: true,
      );
    }

    const crossAxisSpacing = 22.0;
    final targetWidth = width >= 1500 ? 184.0 : 170.0;
    final columns = ((width + crossAxisSpacing) /
            (targetWidth + crossAxisSpacing))
        .floor()
        .clamp(4, 10);
    return MoviePosterGridMetrics(
      columns: columns,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: 28,
      childAspectRatio: 0.57,
      compact: false,
    );
  }

  final int columns;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;
  final bool compact;
}

/// 普通剧集横向卡片网格的响应式度量。
@immutable
class SeriesLandscapeGridMetrics {
  const SeriesLandscapeGridMetrics({
    required this.columns,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.childAspectRatio,
  });

  factory SeriesLandscapeGridMetrics.resolve(double width) {
    final columns = switch (width) {
      < 620 => 1,
      < 980 => 2,
      < 1380 => 3,
      < 1840 => 4,
      _ => 5,
    };
    return SeriesLandscapeGridMetrics(
      columns: columns,
      crossAxisSpacing: width < 620 ? 12 : 20,
      mainAxisSpacing: width < 620 ? 16 : 22,
      childAspectRatio: width < 620 ? 1.42 : 1.36,
    );
  }

  final int columns;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;
}

/// 4K 窗口下限制内容宽度，避免海报和阅读距离无限放大。
const double movieDesktopContentMaxWidth = 2200;
