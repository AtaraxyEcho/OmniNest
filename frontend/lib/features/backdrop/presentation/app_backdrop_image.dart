import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 背景素材图片视图:三端统一渲染服务端网络素材。
///
/// 缓存键基于素材 ID,签名 URL 轮换不会击穿缓存。加载顺序:
/// 主 URL → 失败时回落 [fallbackUrl] → 再失败回落 [fallbackAsset](内置海报),
/// 加载中与失败均不透出白底。全部网络地址失败时回调 [onUrlFailed] 供上层刷新签名 URL。
///
/// [BoxFit.cover] 等比放大裁切,不产生拉伸变形;
/// [BoxFit.contain] 完整显示,可选 [blurPad] 用同图模糊铺底填满留白。
class AppBackdropImage extends StatefulWidget {
  const AppBackdropImage({
    required this.url,
    required this.cacheKey,
    required this.fit,
    this.alignment = Alignment.center,
    this.fallbackUrl,
    this.fallbackAsset,
    this.onUrlFailed,
    this.blurPad = false,
    super.key,
  });

  /// 主图片地址(短期签名 URL)。
  final String? url;

  /// 逻辑缓存键:`backdrop:{assetId}`。
  final String cacheKey;

  final BoxFit fit;

  /// cover/fill 时的裁切锚点。
  final Alignment alignment;

  /// contain 模式下是否用模糊同图铺底,避免大面积纯色留白。
  final bool blurPad;

  /// 主地址加载失败时的备用地址(如原图回退缩略图)。
  final String? fallbackUrl;

  /// 全部地址失败时的内置海报兜底。
  final String? fallbackAsset;

  /// 主/备用网络地址均失败时回调一次。
  final VoidCallback? onUrlFailed;

  @override
  State<AppBackdropImage> createState() => _AppBackdropImageState();
}

class _AppBackdropImageState extends State<AppBackdropImage> {
  String? _failedUrl;
  bool _urlFailedNotified = false;

  int? _resolveCacheExtent(double extent, double devicePixelRatio) {
    if (!extent.isFinite || extent <= 0 || !devicePixelRatio.isFinite) {
      return null;
    }
    final value = (extent * devicePixelRatio).round();
    return value.clamp(1, 8192);
  }

  bool get _useBlurPad => widget.fit == BoxFit.contain && widget.blurPad;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final primary = _resolveUrl();
        if (primary == null) {
          return _buildAssetFallback();
        }
        final cacheWidth = _resolveCacheExtent(
          constraints.maxWidth,
          devicePixelRatio,
        );
        final cacheHeight = _resolveCacheExtent(
          constraints.maxHeight,
          devicePixelRatio,
        );
        if (_useBlurPad) {
          return Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: CachedNetworkImage(
                  imageUrl: primary,
                  cacheKey: widget.cacheKey,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.medium,
                  memCacheWidth: cacheWidth,
                  memCacheHeight: cacheHeight,
                  placeholder: (context, url) => _buildAssetFallback(),
                  errorWidget: (context, url, error) => _buildFallback(url),
                ),
              ),
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.18),
                child: CachedNetworkImage(
                  imageUrl: primary,
                  cacheKey: widget.cacheKey,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                  memCacheWidth: cacheWidth,
                  memCacheHeight: cacheHeight,
                  placeholder: (context, url) => const SizedBox.shrink(),
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              ),
            ],
          );
        }
        return CachedNetworkImage(
          imageUrl: primary,
          cacheKey: widget.cacheKey,
          fit: widget.fit,
          alignment: widget.alignment,
          filterQuality: FilterQuality.high,
          memCacheWidth: cacheWidth,
          memCacheHeight: cacheHeight,
          placeholder: (context, url) => _buildAssetFallback(),
          errorWidget: (context, url, error) => _buildFallback(url),
        );
      },
    );
  }

  /// 当前应使用的主地址;已失败则切到备用地址。
  String? _resolveUrl() {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      return null;
    }
    if (_failedUrl == url) {
      return _nonEmpty(widget.fallbackUrl);
    }
    return url;
  }

  Widget _buildFallback(String failedUrl) {
    _notifyUrlFailedOnce();
    if (_failedUrl == null) {
      _failedUrl = failedUrl;
      final next = _resolveUrl();
      if (next != null && next != failedUrl) {
        return CachedNetworkImage(
          imageUrl: next,
          cacheKey: widget.cacheKey,
          fit: widget.fit,
          filterQuality: FilterQuality.high,
          placeholder: (context, url) => _buildAssetFallback(),
          errorWidget: (context, url, error) => _buildAssetFallback(),
        );
      }
    }
    return _buildAssetFallback();
  }

  void _notifyUrlFailedOnce() {
    if (_urlFailedNotified) {
      return;
    }
    _urlFailedNotified = true;
    widget.onUrlFailed?.call();
  }

  Widget _buildAssetFallback() {
    final asset = widget.fallbackAsset;
    if (asset == null) {
      return const SizedBox.shrink();
    }
    return Image.asset(asset, fit: widget.fit);
  }

  String? _nonEmpty(String? value) {
    return value == null || value.isEmpty ? null : value;
  }
}
