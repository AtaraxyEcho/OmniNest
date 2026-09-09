import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 背景素材图片视图:三端统一渲染服务端网络素材。
/// 缓存键基于素材 ID,签名 URL 轮换不会击穿缓存。
class AppBackdropImage extends StatelessWidget {
  const AppBackdropImage({
    required this.url,
    required this.cacheKey,
    required this.fit,
    super.key,
  });

  /// 图片地址(短期签名 URL)。
  final String? url;

  /// 逻辑缓存键:`backdrop:{assetId}`。
  final String cacheKey;

  final BoxFit fit;

  int? _resolveCacheExtent(double extent, double devicePixelRatio) {
    if (!extent.isFinite || extent <= 0 || !devicePixelRatio.isFinite) {
      return null;
    }
    final value = (extent * devicePixelRatio).round();
    return value.clamp(1, 8192);
  }

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        return CachedNetworkImage(
          imageUrl: url,
          cacheKey: cacheKey,
          fit: fit,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          memCacheWidth: _resolveCacheExtent(
            constraints.maxWidth,
            devicePixelRatio,
          ),
          memCacheHeight: _resolveCacheExtent(
            constraints.maxHeight,
            devicePixelRatio,
          ),
          placeholder: (context, url) => const SizedBox.shrink(),
          errorWidget: (context, url, error) => const SizedBox.shrink(),
        );
      },
    );
  }
}
