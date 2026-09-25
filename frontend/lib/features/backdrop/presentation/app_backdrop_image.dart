import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:omninest/core/utils/image_decode_width.dart';
import 'package:omninest/app/theme/backdrop_scrim_colors.dart';

/// 背景素材图片视图:三端统一渲染服务端网络素材。
///
/// 解码尺寸绑定**显示器物理像素**而非窗口约束,最大化/全屏不改
/// memCache 键,避免重复解码。加载中不使用内置默认壁纸作占位,
/// 仅在地址彻底失败时才回落 [fallbackAsset]。
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
    this.maxDecodeWidth,
    this.previewUrl,
    this.previewCacheKey,
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

  /// 全部地址失败时的内置海报兜底;null 表示失败时只显示深色底,
  /// 不展示其他壁纸(自定义壁纸场景禁止闪默认壁纸)。
  final String? fallbackAsset;

  /// 主/备用网络地址均失败时回调一次。
  final VoidCallback? onUrlFailed;

  /// 强制解码上限(物理像素);模糊背景等场景用低分辨率即可。
  final int? maxDecodeWidth;

  /// 低清先行层地址(瓦片缩略图,磁盘已缓存);主图就绪前立即垫底显示,
  /// 主图加载完成后无缝淡入覆盖,消除首切壁纸的空白等待。
  final String? previewUrl;

  /// 低清层缓存键;与背景库瓦片预览同键可复用磁盘缓存。
  final String? previewCacheKey;

  @override
  State<AppBackdropImage> createState() => _AppBackdropImageState();
}

class _AppBackdropImageState extends State<AppBackdropImage> {
  String? _failedUrl;
  bool _urlFailedNotified = false;

  static const List<int> _decodeTiers = <int>[
    720,
    1080,
    1440,
    1920,
    2560,
    3840,
    4096,
  ];

  static const Color _loadingColor = BackdropStageColors.loading;
  static const Color _transparent = BackdropStageColors.transparent;

  /// 显示器物理像素尺寸;窗口 maximize 不改变该值,解码键保持稳定。
  static ui.Size? _displayPhysicalSize() {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) {
      return null;
    }
    final size = views.first.display.size;
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      return null;
    }
    return size;
  }

  int? _tiered(int value, {int? cap}) {
    var tiered = quantizeDecodeTier(value, _decodeTiers);
    if (cap != null && cap > 0 && tiered > cap) {
      tiered = quantizeDecodeTier(cap, _decodeTiers);
    }
    return tiered;
  }

  int? _resolveDecodeWidth() {
    final display = _displayPhysicalSize();
    if (display == null) {
      return null;
    }
    final physical = math.max(display.width, display.height);
    return _tiered(physical.round(), cap: widget.maxDecodeWidth);
  }

  int? _resolveDecodeHeight() {
    final display = _displayPhysicalSize();
    if (display == null) {
      return null;
    }
    return _tiered(display.height.round());
  }

  int? _resolveConstraintWidth(double constraintsWidth, double dpr) {
    if (!constraintsWidth.isFinite || constraintsWidth <= 0 || dpr <= 0) {
      return null;
    }
    final raw = (constraintsWidth * dpr).round();
    return _tiered(raw, cap: widget.maxDecodeWidth);
  }

  bool get _useBlurPad => widget.fit == BoxFit.contain && widget.blurPad;

  /// 主图加载期间可用低清先行层垫底(有主地址且提供了预览地址)。
  bool get _hasPreview =>
      _nonEmpty(widget.previewUrl) != null && widget.url?.isNotEmpty == true;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final primary = _resolveUrl();
        if (primary == null) {
          return _buildAssetFallback();
        }
        final cacheWidth =
            _resolveDecodeWidth() ??
            _resolveConstraintWidth(constraints.maxWidth, dpr);
        final cacheHeight = _resolveDecodeHeight();
        if (_useBlurPad) {
          // 模糊铺底只需色彩关系,固定低档解码,避免全屏双图高分辨率解码。
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_hasPreview) _buildPreviewLayer(),
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: CachedNetworkImage(
                  imageUrl: primary,
                  cacheKey: widget.cacheKey,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.medium,
                  memCacheWidth: _tiered(720, cap: widget.maxDecodeWidth),
                  placeholder:
                      (context, url) => const ColoredBox(color: _loadingColor),
                  errorWidget: (context, url, error) => _buildAssetFallback(),
                ),
              ),
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.18),
                child: CachedNetworkImage(
                  imageUrl: primary,
                  cacheKey: widget.cacheKey,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.medium,
                  memCacheWidth: cacheWidth,
                  memCacheHeight: cacheHeight,
                  placeholder:
                      (context, url) => const ColoredBox(color: _transparent),
                  errorWidget:
                      (context, url, error) =>
                          const ColoredBox(color: _transparent),
                  errorListener: (_) => _handleLoadError(primary),
                ),
              ),
            ],
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_hasPreview) _buildPreviewLayer(),
            CachedNetworkImage(
              imageUrl: primary,
              cacheKey: widget.cacheKey,
              fit: widget.fit,
              alignment: widget.alignment,
              filterQuality: FilterQuality.medium,
              memCacheWidth: cacheWidth,
              memCacheHeight: cacheHeight,
              // 加载中绝不能显示默认壁纸海报,否则全屏尺寸切换会闪一帧错误壁纸;
              // 有低清先行层时占位与失败态保持透明,让先行层持续可见,
              // 主图由 OctoImage 自带淡入无缝覆盖。
              placeholder:
                  (context, url) =>
                      _hasPreview
                          ? const ColoredBox(color: _transparent)
                          : const ColoredBox(color: _loadingColor),
              // 失败兜底必须是纯展示:地址切换与回调在 [_handleLoadError] 中
              // 于 build 之外完成,禁止在 build 期产生副作用。
              errorWidget:
                  (context, url, error) =>
                      _hasPreview
                          ? const ColoredBox(color: _transparent)
                          : _buildAssetFallback(),
              errorListener: (_) => _handleLoadError(primary),
            ),
          ],
        );
      },
    );
  }

  /// 低清先行层:缩略图按 cover 铺满垫底,失败时静默回深色底。
  Widget _buildPreviewLayer() {
    return CachedNetworkImage(
      imageUrl: widget.previewUrl!,
      cacheKey:
          _nonEmpty(widget.previewCacheKey) ?? 'preview:${widget.cacheKey}',
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      memCacheWidth: _tiered(1440),
      placeholder: (context, url) => const ColoredBox(color: _loadingColor),
      errorWidget:
          (context, url, error) => const ColoredBox(color: _loadingColor),
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

  /// 图片流错误回调(发生在 build 之外):先通知一次上层刷新签名 URL,
  /// 存在备用地址且尚未切换时切换到备用地址重建,否则维持失败兜底。
  void _handleLoadError(String failedUrl) {
    if (!mounted) {
      return;
    }
    if (!_urlFailedNotified) {
      _urlFailedNotified = true;
      widget.onUrlFailed?.call();
    }
    final fallback = _nonEmpty(widget.fallbackUrl);
    if (_failedUrl == null && fallback != null && fallback != failedUrl) {
      setState(() => _failedUrl = failedUrl);
    }
  }

  Widget _buildAssetFallback() {
    final asset = widget.fallbackAsset;
    if (asset == null || asset.isEmpty) {
      return const ColoredBox(color: _loadingColor);
    }
    return Image.asset(asset, fit: widget.fit);
  }

  String? _nonEmpty(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}
