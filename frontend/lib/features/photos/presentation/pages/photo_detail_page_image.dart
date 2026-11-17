part of 'photo_detail_page.dart';

/// 查看器解码档位与渐进图层：从页面主文件拆出的图片流水线。
///
/// 拆出原因：预取键与渲染键必须逐参数一致，逻辑独立且体量足以单独成段，
/// 主文件保留页面编排与交互状态。

/// 查看器两层图片的解码宽度档位：预取与渲染共用，保证图片缓存键一致。
///
/// 原图层按屏宽 256 步进量化；封面层 128 步进、上限 1024。256 档位避免
/// 最大化/还原时屏宽连续变化反复重解码。
({int source, int cover}) viewerDecodeWidths(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final dpr = MediaQuery.devicePixelRatioOf(context);
  return (
    source: quantizedDecodeWidth(
      logicalWidth: size.width,
      devicePixelRatio: dpr,
      step: 256,
      min: 512,
      max: 4096,
    ),
    cover: quantizedDecodeWidth(
      logicalWidth: size.width,
      devicePixelRatio: dpr,
      step: 128,
      min: 400,
      max: 1024,
    ),
  );
}

/// 查看器渐进图层：列表封面先亮，原图就绪后淡入覆盖。
///
/// 分页列表项已携带签名 sourceUrl；首页最近/收藏条带的列表项不含
/// sourceUrl，由相邻页详情预取与内存缓存种子补齐。原图按屏宽降采样
/// 解码，避免移动端整幅原图解码卡顿。
///
/// 种子（列表/内存缓存）可能携带已过期的预签名 URL；签名 URL 失败后按
/// 世代后缀重试并作废详情 provider 换取现签地址：CachedNetworkImage 的
/// provider 相等性只看 cacheKey，同 key 的 URL 轮换不会重载已失败的
/// 流，必须换 key 才能重试。
///
/// 解码宽度档位由 [viewerDecodeWidths] 统一提供，相邻页预取与渲染共用，
/// 保证图片缓存键一致，预取才能真正命中已解码位图。
class _ProgressivePhotoImage extends ConsumerStatefulWidget {
  const _ProgressivePhotoImage({required this.photo});

  final PhotoItem photo;

  @override
  ConsumerState<_ProgressivePhotoImage> createState() =>
      _ProgressivePhotoImageState();
}

class _ProgressivePhotoImageState
    extends ConsumerState<_ProgressivePhotoImage> {
  static const int _maxRetryTicks = 2;

  /// 原图层异步就绪后的短淡入时长；仅异步加载播放，同步缓存命中不播。
  static const Duration _sourceFadeIn = Duration(milliseconds: 220);

  int _retryTick = 0;
  bool _recovering = false;

  void _handleImageError() {
    if (_recovering || _retryTick >= _maxRetryTicks) {
      return;
    }
    // post-frame 触发，避免图片流回调（可发生于 build 期）中直接改状态。
    _recovering = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _retryTick++;
        _recovering = false;
      });
      // 作废详情取现签 URL；新 URL 配合世代后缀 cacheKey 才会真正重载。
      ref.invalidate(photoDetailProvider(widget.photo.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    final retrySuffix = _retryTick > 0 ? ':r$_retryTick' : '';
    final coverUrl = photo.coverUrl;
    final sourceUrl = photo.sourceUrl;
    final widths = viewerDecodeWidths(context);
    final sourceDecodeWidth = widths.source;
    final coverDecodeWidth = widths.cover;

    if (sourceUrl == null || sourceUrl.isEmpty) {
      if (coverUrl == null || coverUrl.isEmpty) {
        return const SizedBox.shrink();
      }
      return _ViewerNetworkImage(
        imageUrl: coverUrl,
        cacheKey: '${photo.coverCacheKey}$retrySuffix',
        memCacheWidth: sourceDecodeWidth,
        fadeInDuration: _sourceFadeIn,
        onError: _handleImageError,
      );
    }

    final hasCover = coverUrl != null && coverUrl.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasCover)
          _ViewerNetworkImage(
            imageUrl: coverUrl,
            cacheKey: '${photo.coverCacheKey}$retrySuffix',
            memCacheWidth: coverDecodeWidth,
            onError: _handleImageError,
          ),
        _ViewerNetworkImage(
          imageUrl: sourceUrl,
          cacheKey: '${photo.sourceCacheKey}$retrySuffix',
          memCacheWidth: sourceDecodeWidth,
          // 封面已在底层：原图加载中不再叠 spinner，失败时保留封面；
          // 异步就绪后短淡入，把封面→原图的清晰度跳变柔化为交叉过渡
          //（预取命中的同步加载会被 octo 跳过淡入，仍单帧直出）。
          fadeInDuration: _sourceFadeIn,
          transparentWhilePending: hasCover,
          hideError: hasCover,
          onError: _handleImageError,
        ),
      ],
    );
  }
}

/// 查看器单层网络图：按给定解码宽降采样，可选透明等待与静默失败。
class _ViewerNetworkImage extends StatelessWidget {
  const _ViewerNetworkImage({
    required this.imageUrl,
    required this.cacheKey,
    required this.memCacheWidth,
    this.fadeInDuration = Duration.zero,
    this.transparentWhilePending = false,
    this.hideError = false,
    this.onError,
  });

  final String imageUrl;
  final String cacheKey;
  final int memCacheWidth;
  final Duration fadeInDuration;
  final bool transparentWhilePending;
  final bool hideError;
  final VoidCallback? onError;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheKey: cacheKey,
      memCacheWidth: memCacheWidth,
      fit: BoxFit.contain,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      errorListener: (_) {
        final callback = onError;
        if (callback != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => callback());
        }
      },
      placeholder:
          transparentWhilePending
              ? (context, url) => const SizedBox.shrink()
              : (context, url) => Center(
                child: CircularProgressIndicator(
                  color: context.photosColors.primaryContainer,
                ),
              ),
      errorWidget:
          hideError
              ? (context, url, error) => const SizedBox.shrink()
              : (context, url, error) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      color: context.photosColors.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      size: 48,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context).photosImageLoadFailed,
                      style: TextStyle(
                        color: context.photosColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}

/// LIVE 徽标：胶囊样式，激活时高亮，点按切换常驻播放。
class _MotionBadge extends StatelessWidget {
  const _MotionBadge({
    required this.active,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final bool active;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        active
            ? context.photosColors.primaryContainer
            : isDark
            ? Colors.black.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.78);
    final foreground =
        active
            ? context.photosColors.onPrimaryContainer
            : isDark
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.black.withValues(alpha: 0.78);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.motion_photos_on_rounded,
                  size: 16,
                  color: foreground,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
