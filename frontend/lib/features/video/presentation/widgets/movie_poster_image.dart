import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/image_decode_width.dart';
import 'package:omninest/features/video/application/video_cover_recovery.dart';

/// 影视模块海报/缩略图，按显示尺寸限制解码并启用磁盘缓存。
///
/// [cacheKey] 为内容级稳定键（如 movie-poster:{itemId}），与带 token 的
/// 临时 URL 解耦：URL 重签后命中缓存不重复下载；加载失败时上报自愈
/// 控制器，世代号递增后以 :r{generation} 后缀强制重载（同 key 的 URL
/// 轮换不会触发已失败流重试，是过期海报永久灰块的根因）。
class MoviePosterImage extends ConsumerWidget {
  const MoviePosterImage({
    required this.imageUrl,
    this.cacheKey,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.fallback = const SizedBox.expand(),
    this.cacheWidth,
    this.cacheHeight,
    super.key,
  });

  final String? imageUrl;
  final String? cacheKey;
  final BoxFit fit;
  final Alignment alignment;
  final Widget fallback;
  final int? cacheWidth;
  final int? cacheHeight;

  /// 按逻辑像素与设备像素比估算解码宽度；64px 档位量化，减少 resize 重解码。
  static int? decodeWidth(
    BuildContext context,
    double logicalWidth, {
    double cap = 1200,
  }) {
    if (logicalWidth <= 0) {
      return null;
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return quantizedDecodeWidth(
      logicalWidth: logicalWidth,
      devicePixelRatio: dpr,
      step: 64,
      min: 64,
      max: cap.toInt(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return fallback;
    }
    final generation = ref.watch(videoCoverRecoveryProvider);
    final suffix = generation > 0 ? ':r$generation' : '';
    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: cacheKey == null ? null : '$cacheKey$suffix',
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      errorListener: (_) {
        // post-frame 上报，避免图片流回调（可发生于 build 期）中改状态。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(videoCoverRecoveryProvider.notifier).reportFailure();
        });
      },
      placeholder: (context, url) => fallback,
      errorWidget: (context, url, error) => fallback,
      fadeInDuration: const Duration(milliseconds: 250),
    );
  }
}
