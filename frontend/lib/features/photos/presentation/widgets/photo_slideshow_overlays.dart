import 'dart:ui' as ui show Image, ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_slideshow_chrome.dart';

/// 幻灯片帧：页面上的一层画面（照片 + 已解码位图）。
///
/// 背景模糊层直接使用 [photo] 的 coverUrl，前景用 [image] 的解码位图。
class SlideFrame {
  const SlideFrame(this.photo, this.image);

  final PhotoItem photo;
  final ui.Image? image;
}

/// 背景双层模糊：与前景同一过渡控制器同步交叉（Apple Photos 式氛围同步）。
class SlideshowBackdropLayers extends StatelessWidget {
  const SlideshowBackdropLayers({
    required this.transition,
    required this.transitioning,
    this.leavingFrame,
    this.enteringFrame,
    super.key,
  });

  final Animation<double> transition;
  final bool transitioning;
  final SlideFrame? leavingFrame;
  final SlideFrame? enteringFrame;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: transition,
      builder: (context, _) {
        final t = transition.value;
        final leaving = transitioning ? leavingFrame : null;
        final entering = enteringFrame;
        if (entering == null) return const SizedBox.shrink();
        return Stack(
          fit: StackFit.expand,
          children: [
            if (leaving != null)
              Positioned.fill(
                child: Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: _buildBlurredCover(leaving.photo),
                ),
              ),
            Positioned.fill(
              child: Opacity(
                // 过渡控制器在静止态停在 0，入场层不透明度必须按过渡态门控，
                // 否则首图与切换完成后都会以 opacity 0 渲染成黑屏。
                opacity: transitioning ? t.clamp(0.0, 1.0) : 1.0,
                child: _buildBlurredCover(entering.photo),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 单张模糊背景：96px 超低分辨率缩略图放大拉伸（放大即强模糊）+ 压暗。
  Widget _buildBlurredCover(PhotoItem photo) {
    final thumb = photo.coverUrl;
    if (thumb == null || thumb.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return RepaintBoundary(
      child: Transform.scale(
        scale: 1.12,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: thumb,
                cacheKey: photo.coverCacheKey,
                memCacheWidth: 96,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                fadeInDuration: Duration.zero,
                errorWidget:
                    (context, url, error) =>
                        const ColoredBox(color: Colors.black),
              ),
              ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 前景双层：离场位图淡出 + 当前位图淡入（微缩放，摄影应用式 motion）。
class SlideshowSlideLayers extends StatelessWidget {
  const SlideshowSlideLayers({
    required this.transition,
    required this.transitioning,
    this.leavingFrame,
    this.enteringFrame,
    super.key,
  });

  final Animation<double> transition;
  final bool transitioning;
  final SlideFrame? leavingFrame;
  final SlideFrame? enteringFrame;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: transition,
      builder: (context, _) {
        final t = transition.value;
        final leaving = transitioning ? leavingFrame : null;
        final entering = enteringFrame;
        if (entering == null) return const SizedBox.shrink();
        return Stack(
          fit: StackFit.expand,
          children: [
            if (leaving != null && leaving.image != null)
              Positioned.fill(
                child: SlideshowSlideLayer(
                  image: leaving.image,
                  opacity: (1 - t).clamp(0.0, 1.0),
                  scale: 1.0 - 0.005 * t,
                ),
              ),
            Positioned.fill(
              child: SlideshowSlideLayer(
                image: entering.image,
                // 过渡控制器在静止态停在 0：入场层不透明度与缩放必须按
                // 过渡态门控，否则首图与切换完成后都会以 opacity 0 渲染成黑屏。
                opacity: transitioning ? t.clamp(0.0, 1.0) : 1.0,
                scale: transitioning ? 1.015 - 0.015 * t : 1.0,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 首屏加载层：内存/磁盘封面优先 + 无封面时的小型 spinner。
class SlideshowLoadingStage extends StatelessWidget {
  const SlideshowLoadingStage({required this.photo, super.key});

  final PhotoItem photo;

  @override
  Widget build(BuildContext context) {
    final cover = photo.coverUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasCover)
          CachedNetworkImage(
            imageUrl: cover,
            cacheKey: photo.coverCacheKey,
            fit: BoxFit.cover,
            memCacheWidth: 1280,
            filterQuality: FilterQuality.medium,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder:
                (context, url) => const ColoredBox(color: Colors.black),
            errorWidget:
                (context, url, error) => const ColoredBox(color: Colors.black),
          )
        else
          const ColoredBox(color: Colors.black),
        // Spinner only when there is no cover to show under it.
        if (!hasCover)
          const Center(
            child: SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0x66FFFFFF),
              ),
            ),
          ),
      ],
    );
  }
}

/// 上下渐变遮罩：控件隐藏时底部渐变减淡、顶部渐变收起。
class SlideshowGradients extends StatelessWidget {
  const SlideshowGradients({required this.visible, super.key});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: visible ? 1 : 0.4,
            duration: const Duration(milliseconds: 500),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment(0, -0.4),
                  colors: [
                    Color(0xB8000000),
                    Color(0x2E000000),
                    Colors.transparent,
                  ],
                  stops: [0, 0.35, 0.6],
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 500),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment(0, 0.3),
                  colors: [Color(0x80000000), Colors.transparent],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 左右切换箭头：隐藏时淡出并横向微移，指针事件同步关闭。
class SlideshowArrow extends StatelessWidget {
  const SlideshowArrow({
    required this.right,
    required this.visible,
    required this.onTap,
    super.key,
  });

  final bool right;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Positioned(
      left: right ? null : 20,
      right: right ? 20 : null,
      top: 0,
      bottom: 0,
      child: Center(
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: AnimatedSlide(
              offset: visible ? Offset.zero : Offset(right ? 0.08 : -0.08, 0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.ease,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onTap,
                  child: Tooltip(
                    message:
                        right ? l10n.photosNextPhoto : l10n.photosPrevPhoto,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0),
                      ),
                      child: Icon(
                        right
                            ? Icons.chevron_right_rounded
                            : Icons.chevron_left_rounded,
                        size: 28,
                        color: Colors.white.withValues(alpha: 0.70),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部区容器：元信息 + 播放/暂停 + 分段进度 + 缩略图条开关 + 缩略图条。
///
/// [segments] 与 [thumbnailStrip] 由页面构建后按槽位嵌入，
/// 保持进度与图片缓存等可变状态仍归页面所有。
class SlideshowBottomArea extends StatelessWidget {
  const SlideshowBottomArea({
    required this.photo,
    required this.visible,
    required this.isPlaying,
    required this.thumbnailsVisible,
    required this.onTogglePlay,
    required this.onToggleThumbnails,
    required this.segments,
    required this.thumbnailStrip,
    super.key,
  });

  final PhotoItem photo;
  final bool visible;
  final bool isPlaying;
  final bool thumbnailsVisible;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleThumbnails;
  final Widget segments;
  final Widget thumbnailStrip;

  @override
  Widget build(BuildContext context) {
    final preferZh = Localizations.localeOf(context).languageCode == 'zh';
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, 0.12),
            duration: const Duration(milliseconds: 400),
            curve: Curves.ease,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    photo.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppTypography.headlineSmall,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -0.01,
                    ),
                  ),
                  Text(
                    _metaLine(photo, preferZh),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: AppTypography.bodySmall,
                      letterSpacing: 0.06,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      IconButton(
                        tooltip:
                            isPlaying
                                ? AppLocalizations.of(context).photosPause
                                : AppLocalizations.of(context).photosPlay,
                        onPressed: onTogglePlay,
                        icon: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white.withValues(alpha: 0.80),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: segments),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: onToggleThumbnails,
                        child: Text(
                          thumbnailsVisible
                              ? AppLocalizations.of(context).photosStripHide
                              : AppLocalizations.of(context).photosStripShow,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.50),
                            fontSize: AppTypography.labelSmall,
                            letterSpacing: 0.08,
                          ),
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child:
                        thumbnailsVisible
                            ? thumbnailStrip
                            : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _metaLine(PhotoItem photo, bool preferZh) {
    final location = photo.locationDisplay(preferZh: preferZh);
    final date = photo.dateTaken ?? photo.createdAt;
    final dateText =
        date == null
            ? null
            : '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}';
    return [location, dateText].whereType<String>().join(' · ');
  }
}

/// 首图加载失败的居中重试层。
class SlideshowErrorRetry extends StatelessWidget {
  const SlideshowErrorRetry({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 44,
            color: Color(0x66FFFFFF),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.photosImageLoadFailed,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: AppTypography.bodyLarge,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n.coreRetry),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.85),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分段进度条：仅当前段跟随 [progress] 逐帧刷新，其余段为静态。
class SlideshowSegments extends StatelessWidget {
  const SlideshowSegments({
    required this.count,
    required this.current,
    required this.isPlaying,
    required this.progress,
    required this.onTap,
    super.key,
  });

  final int count;
  final int current;
  final bool isPlaying;
  final ValueListenable<double> progress;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: RepaintBoundary(
                    // 隔离绘制：进度 tick 的重绘不传播到页面根。
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      // 仅当前段跟随进度逐帧刷新；其余段为静态，避免照片多时每 30ms 重建全部段。
                      child:
                          i == current
                              ? ValueListenableBuilder<double>(
                                valueListenable: progress,
                                builder:
                                    (context, value, _) =>
                                        _buildSegmentBar(_valueFor(i, value)),
                              )
                              : _buildSegmentBar(_valueFor(i, 0)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSegmentBar(double value) {
    return LinearProgressIndicator(
      value: value,
      minHeight: 2,
      backgroundColor: Colors.white.withValues(alpha: 0.20),
      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xE6FFFFFF)),
    );
  }

  double _valueFor(int index, double value) {
    if (index < current) return 1;
    if (index > current) return 0;
    return isPlaying ? value : 0;
  }
}

/// 底部缩略图条：当前项高亮，其余降不透明度。
class SlideshowThumbnailStrip extends StatelessWidget {
  const SlideshowThumbnailStrip({
    required this.photos,
    required this.current,
    required this.onTap,
    super.key,
  });

  final List<PhotoItem> photos;
  final int current;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == current;
          final thumb = photos[index].coverUrl;
          return Opacity(
            opacity: selected ? 1 : 0.45,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(index),
              child: Container(
                width: 72,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color:
                        selected
                            ? Colors.white.withValues(alpha: 0.90)
                            : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child:
                      thumb != null && thumb.isNotEmpty
                          ? CachedNetworkImage(
                            imageUrl: thumb,
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            errorWidget:
                                (context, url, error) => ColoredBox(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                          )
                          : ColoredBox(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
