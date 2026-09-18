import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 影视模块海报/缩略图，按显示尺寸限制解码并启用磁盘缓存。
class MoviePosterImage extends StatelessWidget {
  const MoviePosterImage({
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.fallback = const SizedBox.expand(),
    this.cacheWidth,
    this.cacheHeight,
    super.key,
  });

  final String? imageUrl;
  final BoxFit fit;
  final Alignment alignment;
  final Widget fallback;
  final int? cacheWidth;
  final int? cacheHeight;

  /// 按逻辑像素与设备像素比估算解码宽度。
  static int? decodeWidth(
    BuildContext context,
    double logicalWidth, {
    double cap = 1200,
  }) {
    if (logicalWidth <= 0) {
      return null;
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (logicalWidth * dpr).round().clamp(64, cap.toInt());
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return fallback;
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      placeholder: (context, url) => fallback,
      errorWidget: (context, url, error) => fallback,
      fadeInDuration: Duration.zero,
    );
  }
}
