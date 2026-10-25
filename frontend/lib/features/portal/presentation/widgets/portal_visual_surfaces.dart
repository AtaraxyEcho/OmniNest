part of 'portal_visual_widgets.dart';

class PortalGradientCover extends StatelessWidget {
  const PortalGradientCover({
    required this.palette,
    required this.title,
    required this.subtitle,
    this.variant = 0,
    this.height,
    this.imageUrl,
    this.readerItemId,
    this.fallbackIcon = Icons.image_outlined,
    this.foregroundFit = BoxFit.contain,
    this.foregroundPadding = const EdgeInsets.fromLTRB(10, 10, 10, 58),
    this.showTextOverlay = true,
    this.maxCoverWidth,
    this.maxCoverHeight,
    this.minCoverHeight = 120,
    this.borderWidth = 1,
    this.directImage = false,
    this.coverCacheKey,
    this.onCoverError,
    this.contentScale = 1.0,
    super.key,
  });

  final PortalVisualPalette palette;
  final String title;
  final String subtitle;
  final int variant;
  final double? height;
  final String? imageUrl;
  final String? readerItemId;
  final IconData fallbackIcon;
  final BoxFit foregroundFit;
  final EdgeInsetsGeometry foregroundPadding;
  final bool showTextOverlay;
  final double? maxCoverWidth;
  final double? maxCoverHeight;
  final double minCoverHeight;
  final double borderWidth;
  final bool directImage;

  /// 稳定缓存键（内容标识构造），与签名 URL 解耦。
  final String? coverCacheKey;

  /// 封面加载失败回调；调用方据此触发对应数据分区重签刷新。
  final VoidCallback? onCoverError;

  /// 封面图悬停微放大，与 Photos 照片卡同构：只作用于图像本体，氛围
  /// 底图、遮罩、文字与描边保持原位；满铺直图的溢出由卡片圆角裁剪，
  /// 前景封面图在其留白内放大。悬停时由调用方驱动该值。
  final double contentScale;

  @override
  Widget build(BuildContext context) {
    final normalizedImageUrl = imageUrl?.trim();
    final normalizedReaderItemId = readerItemId?.trim();
    final hasImage =
        (normalizedImageUrl != null && normalizedImageUrl.isNotEmpty) ||
        (normalizedReaderItemId != null && normalizedReaderItemId.isNotEmpty);
    // 禁渐变规范：每个变体取单一纯色（回退色列表沿用双份同色保持接口）。
    final solid = switch (variant % 4) {
      0 => palette.accentAlt,
      1 => PortalCoverFallbackColors.deepBlue,
      2 => PortalCoverFallbackColors.deepTeal,
      _ => PortalCoverFallbackColors.deepIndigo,
    };
    final colors = [solid, solid];
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: minCoverHeight,
        maxWidth: maxCoverWidth ?? double.infinity,
        maxHeight: maxCoverHeight ?? double.infinity,
      ),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.26),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
            child: Stack(
              children: [
                if (hasImage)
                  Positioned.fill(
                    child: _AdaptiveCoverImage(
                      imageUrl: normalizedImageUrl,
                      readerItemId: normalizedReaderItemId,
                      fallbackColors: colors,
                      foregroundFit: foregroundFit,
                      foregroundPadding: foregroundPadding,
                      directImage: directImage,
                      coverCacheKey: coverCacheKey,
                      onCoverError: onCoverError,
                      contentScale: contentScale,
                    ),
                  )
                else
                  Positioned(
                    right: 18,
                    top: 18,
                    child: Icon(
                      fallbackIcon,
                      color: palette.text.withValues(alpha: 0.28),
                      size: 34,
                    ),
                  ),
                if (showTextOverlay)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: hasImage ? 0.10 : 0),
                            Colors.black.withValues(
                              alpha: hasImage ? 0.66 : 0.48,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (showTextOverlay)
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasImage ? Colors.white : palette.text,
                            fontSize: AppTypography.titleLarge,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                hasImage
                                    ? Colors.white.withValues(alpha: 0.78)
                                    : palette.muted,
                            fontSize: AppTypography.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                        width: borderWidth,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
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

/// 底层氛围图的模糊强度：仅用于完整封面下方的铺满裁切层。
const double _ambientBackdropBlurSigma = 24;

/// 底层氛围图的解码缓存宽度：只需保留色彩关系，避免整卡分辨率解码。
const int _ambientBackdropCacheWidth = 128;

/// 将底层封面图模糊为色彩氛围层，消除与上层完整封面的同图重影。
class _AmbientCoverBackdrop extends StatelessWidget {
  const _AmbientCoverBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: _ambientBackdropBlurSigma,
        sigmaY: _ambientBackdropBlurSigma,
        tileMode: TileMode.clamp,
      ),
      child: child,
    );
  }
}

class _AdaptiveCoverImage extends ConsumerWidget {
  const _AdaptiveCoverImage({
    required this.fallbackColors,
    required this.foregroundFit,
    required this.foregroundPadding,
    required this.directImage,
    this.imageUrl,
    this.readerItemId,
    this.coverCacheKey,
    this.onCoverError,
    this.contentScale = 1.0,
  });

  final String? imageUrl;
  final String? readerItemId;
  final String? coverCacheKey;
  final VoidCallback? onCoverError;
  final List<Color> fallbackColors;
  final BoxFit foregroundFit;
  final EdgeInsetsGeometry foregroundPadding;
  final bool directImage;

  /// 封面图缩放，见 [PortalGradientCover.contentScale]。
  final double contentScale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemId = readerItemId?.trim();
    final resolvedImageUrl = imageUrl?.trim();
    final hasReaderCover = itemId != null && itemId.isNotEmpty;
    final hasNetworkCover =
        resolvedImageUrl != null && resolvedImageUrl.isNotEmpty;
    if (!hasReaderCover && !hasNetworkCover) {
      return _CoverImageFallback(colors: fallbackColors);
    }
    final readerCoverItemId = hasReaderCover ? itemId : null;
    final networkCoverUrl = hasNetworkCover ? resolvedImageUrl : null;
    if (directImage) {
      final fallback = _CoverImageFallback(colors: fallbackColors);
      if (readerCoverItemId != null) {
        return _CoverArtScale(
          scale: contentScale,
          child: AuthCoverImage(
            itemId: readerCoverItemId,
            fit: BoxFit.cover,
            fallback: fallback,
          ),
        );
      }
      // 本地音乐封面走稳定鉴权 API 路径，需要音乐专域的 Dio 缓存管理器；
      // 其他模块的签名直链与非音乐地址返回 null，行为不变。
      final coverManager = ref.watch(
        musicCoverCacheManagerProvider(networkCoverUrl!),
      );
      return _CoverArtScale(
        scale: contentScale,
        child: CachedNetworkImage(
          imageUrl: networkCoverUrl,
          cacheKey: coverCacheKey,
          cacheManager: coverManager,
          // Web 端默认 HtmlImage 会绕过管理器直连页面 origin 且不带 Bearer。
          imageRenderMethodForWeb: musicCoverRenderMethodForWeb(coverManager),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          memCacheWidth: quantizedDecodeWidth(
            logicalWidth: 200,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            step: 64,
            min: 128,
            max: 800,
          ),
          errorListener: (_) {
            // 签名 URL 过期是封面失败主因：post-frame 通知上层重签，
            // 避免在图片流回调（可发生于 build 期）中直接触发状态改写。
            final callback = onCoverError;
            if (callback != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) => callback());
            }
          },
          placeholder: (context, url) => fallback,
          errorWidget: (context, url, error) => fallback,
        ),
      );
    }
    if (readerCoverItemId != null) {
      return _ReaderAdaptiveCoverImage(
        itemId: readerCoverItemId,
        fallbackColors: fallbackColors,
        foregroundFit: foregroundFit,
        foregroundPadding: foregroundPadding,
        contentScale: contentScale,
      );
    }
    return _NetworkAdaptiveCoverImage(
      imageUrl: networkCoverUrl!,
      fallbackColors: fallbackColors,
      foregroundFit: foregroundFit,
      foregroundPadding: foregroundPadding,
      cacheKey: coverCacheKey,
      onCoverError: onCoverError,
      contentScale: contentScale,
    );
  }
}

class _ReaderAdaptiveCoverImage extends StatelessWidget {
  const _ReaderAdaptiveCoverImage({
    required this.itemId,
    required this.fallbackColors,
    required this.foregroundFit,
    required this.foregroundPadding,
    this.contentScale = 1.0,
  });

  final String itemId;
  final List<Color> fallbackColors;
  final BoxFit foregroundFit;
  final EdgeInsetsGeometry foregroundPadding;

  /// 封面图缩放，见 [PortalGradientCover.contentScale]。
  final double contentScale;

  @override
  Widget build(BuildContext context) {
    final fallback = _CoverImageFallback(colors: fallbackColors);
    return Stack(
      fit: StackFit.expand,
      children: [
        _AmbientCoverBackdrop(
          child: AuthCoverImage(
            itemId: itemId,
            fit: BoxFit.cover,
            fallback: fallback,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.20),
          ),
        ),
        Padding(
          padding: foregroundPadding,
          child: _CoverArtZoom(
            scale: contentScale,
            child: AuthCoverImage(
              itemId: itemId,
              fit: foregroundFit,
              fallback: const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class _NetworkAdaptiveCoverImage extends ConsumerWidget {
  const _NetworkAdaptiveCoverImage({
    required this.imageUrl,
    required this.fallbackColors,
    required this.foregroundFit,
    required this.foregroundPadding,
    this.cacheKey,
    this.onCoverError,
    this.contentScale = 1.0,
  });

  final String imageUrl;
  final List<Color> fallbackColors;
  final BoxFit foregroundFit;
  final EdgeInsetsGeometry foregroundPadding;
  final String? cacheKey;
  final VoidCallback? onCoverError;

  /// 封面图缩放，见 [PortalGradientCover.contentScale]。
  final double contentScale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = _CoverImageFallback(colors: fallbackColors);
    final cacheManager = ref.watch(musicCoverCacheManagerProvider(imageUrl));
    void notifyCoverError() {
      // 签名 URL 失效是 hero 封面失败主因：post-frame 通知上层重签，
      // 避免在图片流回调（可发生于 build 期）中直接触发状态改写。
      final callback = onCoverError;
      if (callback != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => callback());
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _AmbientCoverBackdrop(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            cacheKey: cacheKey,
            cacheManager: cacheManager,
            // Web 端默认 HtmlImage 会绕过管理器直连页面 origin 且不带 Bearer。
            imageRenderMethodForWeb: musicCoverRenderMethodForWeb(cacheManager),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            memCacheWidth: _ambientBackdropCacheWidth,
            errorListener: (_) => notifyCoverError(),
            placeholder: (context, url) => fallback,
            errorWidget: (context, url, error) => fallback,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.20),
          ),
        ),
        Padding(
          padding: foregroundPadding,
          child: _CoverArtZoom(
            scale: contentScale,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              cacheKey: cacheKey,
              cacheManager: cacheManager,
              // Web 端默认 HtmlImage 会绕过管理器直连页面 origin 且不带 Bearer。
              imageRenderMethodForWeb: musicCoverRenderMethodForWeb(
                cacheManager,
              ),
              fit: foregroundFit,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              // hero 封面卡最宽 400 逻辑像素：量化解码覆盖 DPR 放大，
              // 同时避免整图分辨率的解码开销。
              memCacheWidth: quantizedDecodeWidth(
                logicalWidth: 400,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                step: 128,
                min: 256,
                max: 1280,
              ),
              errorListener: (_) => notifyCoverError(),
              placeholder: (context, url) => const SizedBox.shrink(),
              errorWidget: (context, url, error) => const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 满铺封面图悬停微放大（Photos 照片卡同构的裁切缩放）：图片铺满容器，
/// 放大后的溢出由外层卡片圆角裁剪——画幅边界不动，只有内容放大。
class _CoverArtScale extends StatelessWidget {
  const _CoverArtScale({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: scale,
      duration: MotionToken.normal,
      curve: MotionToken.curve,
      child: child,
    );
  }
}

/// 前景封面图的悬停内容放大（Photos 照片卡同构的裁切缩放）：
/// FittedBox 把图片按 contain 适配进留白区，ClipRect 钉住图片的
/// 天然画幅——放大只作用于内部像素、边缘被裁掉，封面本体不变大。
/// 图片在无界约束下按解码尺寸布局，加载前后画幅一致。
class _CoverArtZoom extends StatelessWidget {
  const _CoverArtZoom({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      clipBehavior: Clip.none,
      child: ClipRect(
        child: AnimatedScale(
          scale: scale,
          duration: MotionToken.normal,
          curve: MotionToken.curve,
          child: child,
        ),
      ),
    );
  }
}

class _CoverImageFallback extends StatelessWidget {
  const _CoverImageFallback({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
    );
  }
}

class PortalMetricLine extends StatelessWidget {
  const PortalMetricLine({
    required this.palette,
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  final PortalVisualPalette palette;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 行内容统一带横向 12 内边距：可点击行的胶囊高亮与文字保持呼吸
    // 空间，静态行（无高亮）与可点击行左缘对齐。
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.muted,
                fontSize: AppTypography.bodyMedium,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: palette.text,
                fontSize: AppTypography.bodyLarge,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: row,
      ),
    );
  }
}

class PortalQuickLinks extends StatelessWidget {
  const PortalQuickLinks({
    required this.palette,
    this.includeAdmin = false,
    super.key,
  });

  final PortalVisualPalette palette;
  final bool includeAdmin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = [
      (Icons.folder_open_rounded, l10n.portalDockFiles, '/files'),
      (Icons.menu_book_rounded, l10n.portalDockReading, '/reader'),
      (Icons.movie_rounded, l10n.portalDockMovies, '/video'),
      (Icons.music_note_rounded, l10n.portalDockMusic, '/music'),
      (Icons.photo_library_rounded, l10n.portalDockPhotos, '/photos'),
      if (includeAdmin)
        (Icons.admin_panel_settings_rounded, l10n.portalAdmin, '/admin'),
    ];
    return Wrap(
      alignment: WrapAlignment.start,
      runAlignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: 8,
      runSpacing: 8,
      children:
          entries
              .map(
                (entry) => Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.go(entry.$3),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: palette.structuralStrongSurface(alpha: 0.62),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: palette.muted.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(entry.$1, size: 18, color: palette.text),
                          const SizedBox(width: 8),
                          Text(
                            entry.$2,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: AppTypography.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
    );
  }
}
