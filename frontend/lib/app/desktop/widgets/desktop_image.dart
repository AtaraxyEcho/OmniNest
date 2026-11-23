part of 'desktop_surfaces.dart';

/// 图片与悬停抬升：从 `desktop_surfaces.dart` 拆出，保持单文件行数预算。
/// 样例 `.img`：加载期为微光底，解码后 600ms 淡入；失败保留底面不露破图。
class DesktopImage extends StatelessWidget {
  const DesktopImage({
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheWidth,
    this.fallbackIcon,
    super.key,
  });

  final String? url;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// 缩略图场景按显示尺寸限制解码宽度；null 保持原图解码（全屏查看器用）。
  final int? cacheWidth;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final placeholder = _ImageShimmer(borderRadius: borderRadius);
    final skin = DesktopSkin.of(context);
    final fallback = ColoredBox(
      color: skin.raise2,
      child:
          fallbackIcon == null
              ? null
              : Center(child: Icon(fallbackIcon, size: 28, color: skin.text3)),
    );
    Widget content = fallback;
    final source = url;
    if (source != null && source.isNotEmpty) {
      content = Image.network(
        source,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        cacheWidth: cacheWidth,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return _ImageFadeIn(child: child);
          }
          return placeholder;
        },
        loadingBuilder:
            (context, child, progress) =>
                progress == null ? child : placeholder,
        errorBuilder: (context, error, stack) => fallback,
      );
    }
    if (borderRadius != null) {
      content = ClipRRect(borderRadius: borderRadius!, child: content);
    }
    return content;
  }
}

/// 图片加载期的微光底（样例 `.img:not(.ok){animation:shimmer 1.8s}`）。
class DesktopHoverLift extends StatelessWidget {
  const DesktopHoverLift({
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.lift = 4,
    this.tooltip,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final double lift;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget content = DesktopHover(
      enabled: onTap != null,
      builder:
          (context, hovered) => TweenAnimationBuilder<double>(
            tween: Tween<double>(end: hovered ? -lift : 0),
            duration: MotionToken.reduced(context, DesktopMotion.lift),
            curve: DesktopMotion.spring,
            builder:
                (context, dy, child) =>
                    Transform.translate(offset: Offset(0, dy), child: child),
            child: child,
          ),
    );
    content = GestureDetector(
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
    if (tooltip != null) {
      content = Tooltip(message: tooltip!, child: content);
    }
    return content;
  }
}
