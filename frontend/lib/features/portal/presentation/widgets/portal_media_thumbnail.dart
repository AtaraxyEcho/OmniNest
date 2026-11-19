import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/image_decode_width.dart';
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
    final hasUrl = url != null && url.isNotEmpty;
    // 本地音乐封面是稳定鉴权 API 路径：相对地址要经 baseUrl 拼接且带 Bearer；
    // 其他模块的签名直链返回 null，走默认缓存路径与历史行为一致。
    final manager =
        hasUrl ? ref.watch(musicCoverCacheManagerProvider(url)) : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget child;
        if (url == null || url.isEmpty) {
          child = fallback;
        } else {
          child = CachedNetworkImage(
            imageUrl: url,
            cacheKey: cacheKey,
            cacheManager: manager,
            // Web 端默认 HtmlImage 会绕过管理器直连页面 origin 且不带 Bearer。
            imageRenderMethodForWeb: musicCoverRenderMethodForWeb(manager),
            fit: fit,
            width: width,
            height: height,
            memCacheWidth: _resolveCacheWidth(context, constraints),
            memCacheHeight: cacheHeight,
            filterQuality: FilterQuality.medium,
            // 签名地址刷新或卡片尺寸变化时沿用上一帧，直到新提供器就绪；
            // 原型的 `<img>` 也不会先退回一张深色占位卡。
            imageBuilder:
                (context, imageProvider) => Image(
                  image: imageProvider,
                  fit: fit,
                  width: width,
                  height: height,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
            // 原型直接使用 `<img>`，图片可见后没有额外的淡入遮罩；
            // 占位仍由调用方决定，但不会再叠一段旧版淡入动画。
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholderFadeInDuration: Duration.zero,
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
      },
    );
  }

  /// 未显式给解码尺寸时，按实际显示宽度做 2 倍超采样解码。
  ///
  /// 卡片一旦全量挂载，位图处于 live 状态，ImageCache 的 LRU 预算对它们
  /// 失效；按原图尺寸解码会让每张卡占数十 MiB。2 倍超采样高于显示采样率，
  /// 不引入任何可辨像素差，只去掉永不被采样的像素。已有显式宽度/高度约束
  /// 的调用方保持原值，避免改变它们的构图。
  int? _resolveCacheWidth(BuildContext context, BoxConstraints constraints) {
    if (cacheWidth != null || cacheHeight != null) {
      return cacheWidth;
    }
    final logicalWidth =
        constraints.hasBoundedWidth && constraints.maxWidth > 0
            ? constraints.maxWidth
            : (width ?? MediaQuery.sizeOf(context).width);
    return quantizedDecodeWidth(
      logicalWidth: logicalWidth,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      step: 128,
      min: 128,
      max: 1200,
      scale: 2,
    );
  }
}
