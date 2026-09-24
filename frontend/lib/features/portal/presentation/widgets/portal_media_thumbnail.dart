import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/music_portal.dart';

/// Portal 通用媒体缩略图。
class PortalMediaThumbnail extends ConsumerWidget {
  const PortalMediaThumbnail({
    required this.imageUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.cacheWidth,
    this.cacheHeight,
    this.cacheKey,
    this.onLoadError,
    super.key,
  });

  final String? imageUrl;
  final Widget fallback;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final int? cacheWidth;
  final int? cacheHeight;

  /// 稳定缓存键（内容标识构造），与签名 URL 解耦，避免 URL 重签后重复下载。
  final String? cacheKey;

  /// 加载失败回调；调用方据此触发对应数据分区重签刷新。
  final VoidCallback? onLoadError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = imageUrl?.trim();
    Widget child;
    if (url == null || url.isEmpty) {
      child = fallback;
    } else {
      // 本地音乐封面是稳定鉴权 API 路径：相对地址要经 baseUrl 拼接，
      // 且必须带 Bearer；其他模块的签名直链与非音乐地址返回 null，
      // 走默认缓存路径与历史行为一致。
      final manager = ref.watch(musicCoverCacheManagerProvider(url));
      child = CachedNetworkImage(
        imageUrl: url,
        cacheKey: cacheKey,
        cacheManager: manager,
        // Web 端默认 HtmlImage 会绕过管理器直连页面 origin 且不带 Bearer。
        imageRenderMethodForWeb: musicCoverRenderMethodForWeb(manager),
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheHeight,
        filterQuality: FilterQuality.medium,
        errorListener: (_) {
          // post-frame 通知上层，避免在图片流回调（可发生于 build 期）
          // 中直接触发状态改写。
          final callback = onLoadError;
          if (callback != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => callback());
          }
        },
        placeholder: (context, url) => fallback,
        errorWidget: (context, url, error) => fallback,
      );
    }
    if (borderRadius == null) {
      return child;
    }
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }
}
