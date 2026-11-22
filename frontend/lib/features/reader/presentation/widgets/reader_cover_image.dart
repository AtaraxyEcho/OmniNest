import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/image_decode_width.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';

/// 认证封面图片组件
///
/// 通过应用层图片 Provider 加载带认证的封面字节。
class AuthCoverImage extends ConsumerWidget {
  const AuthCoverImage({
    required this.itemId,
    this.coverUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
    super.key,
  });

  final String itemId;
  final String? coverUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_isExternalUrl(coverUrl)) {
      return _buildExternalImage(context);
    }
    final coverAsync = ref.watch(coverBytesProvider(itemId));

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveWidth = _resolveFiniteExtent(
          width,
          constraints.maxWidth,
        );
        final effectiveHeight = _resolveFiniteExtent(
          height,
          constraints.maxHeight,
        );
        final cacheWidth = _resolveCacheWidth(
          effectiveWidth ??
              (effectiveHeight == null ? null : effectiveHeight * 0.75),
        );
        return coverAsync.when(
          data: (bytes) {
            if (bytes == null || bytes.isEmpty) {
              return fallback ?? const SizedBox.shrink();
            }
            Widget image = Image.memory(
              bytes,
              fit: fit,
              width: effectiveWidth,
              height: effectiveHeight,
              cacheWidth: cacheWidth,
              filterQuality: FilterQuality.medium,
              isAntiAlias: true,
              // 与 CachedNetworkImage 卡片的默认淡入过渡保持一致；
              // 同步解码（缓存命中重挂）不做动画避免闪烁。
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) {
                  return child;
                }
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: MotionToken.reduced(
                    context,
                    const Duration(milliseconds: 300),
                  ),
                  alwaysIncludeSemantics: true,
                  child: child,
                );
              },
              errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
            );
            if (borderRadius != null) {
              image = ClipRRect(borderRadius: borderRadius!, child: image);
            }
            return image;
          },
          loading:
              () => SizedBox(
                width: effectiveWidth,
                height: effectiveHeight,
                child: fallback ?? const SizedBox.shrink(),
              ),
          error: (_, _) => fallback ?? const SizedBox.shrink(),
        );
      },
    );
  }

  bool _isExternalUrl(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Widget _buildExternalImage(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveWidth = _resolveFiniteExtent(
          width,
          constraints.maxWidth,
        );
        final effectiveHeight = _resolveFiniteExtent(
          height,
          constraints.maxHeight,
        );
        final cacheWidth = _resolveCacheWidth(
          effectiveWidth ??
              (effectiveHeight == null ? null : effectiveHeight * 0.75),
        );
        Widget image = Image.network(
          coverUrl!,
          fit: fit,
          width: effectiveWidth,
          height: effectiveHeight,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.medium,
          isAntiAlias: true,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: MotionToken.reduced(
                context,
                const Duration(milliseconds: 300),
              ),
              alwaysIncludeSemantics: true,
              child: child,
            );
          },
          errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
        );
        if (borderRadius != null) {
          image = ClipRRect(borderRadius: borderRadius!, child: image);
        }
        return image;
      },
    );
  }

  double? _resolveFiniteExtent(double? requested, double constrained) {
    if (requested != null && requested.isFinite && requested > 0) {
      return requested;
    }
    if (constrained.isFinite && constrained > 0) {
      return constrained;
    }
    return null;
  }

  /// 封面解码尺寸：以设备像素比放大显示宽度，避免大封面原图全分辨率解码。
  /// 按 128px 档位量化，窗口尺寸变动时不反复重解码。
  int? _resolveCacheWidth(double? logicalWidth) {
    if (logicalWidth == null || !logicalWidth.isFinite || logicalWidth <= 0) {
      return null;
    }
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final reportedRatio = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    final devicePixelRatio =
        reportedRatio.isFinite && reportedRatio > 0 ? reportedRatio : 1.0;
    return quantizedDecodeWidth(
      logicalWidth: logicalWidth,
      devicePixelRatio: devicePixelRatio,
      step: 128,
      min: 128,
      max: 2048,
      scale: 2,
    );
  }
}
