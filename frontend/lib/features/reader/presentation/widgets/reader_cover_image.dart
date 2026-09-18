import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';

/// 认证封面图片组件
///
/// 通过应用层图片 Provider 加载带认证的封面字节。
class AuthCoverImage extends ConsumerWidget {
  const AuthCoverImage({
    required this.itemId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
    super.key,
  });

  final String itemId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          error: (_, _) => fallback ?? const SizedBox.shrink(),
        );
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
  int? _resolveCacheWidth(double? logicalWidth) {
    if (logicalWidth == null || !logicalWidth.isFinite || logicalWidth <= 0) {
      return null;
    }
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final reportedRatio = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    final devicePixelRatio =
        reportedRatio.isFinite && reportedRatio > 0 ? reportedRatio : 1.0;
    final decodeWidth = logicalWidth * devicePixelRatio * 2;
    if (!decodeWidth.isFinite || decodeWidth <= 0) {
      return null;
    }
    return decodeWidth.round().clamp(1, 2048);
  }
}
