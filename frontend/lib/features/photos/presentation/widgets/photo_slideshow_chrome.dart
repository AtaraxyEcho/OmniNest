import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/app/theme/severity_colors.dart';

/// Slideshow top-bar icon button: transparent, compact density.
class SlideshowIconButton extends StatelessWidget {
  const SlideshowIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.color,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(
        icon,
        size: 20,
        color: color ?? Colors.white.withValues(alpha: 0.70),
      ),
    );
  }
}

/// Slideshow top bar: left close/title, center counter, right actions.
///
/// Uses a Stack so Flexible/Spacer do not split free width and crowd
/// desktop controls together.
class PhotoSlideshowTopBar extends StatelessWidget {
  const PhotoSlideshowTopBar({
    required this.photo,
    required this.current,
    required this.total,
    required this.visible,
    required this.showInfo,
    required this.showShare,
    required this.onClose,
    required this.onToggleFavorite,
    required this.onToggleShare,
    required this.onDownload,
    required this.onToggleInfo,
    required this.onFullscreen,
    super.key,
  });

  final PhotoItem photo;
  final int current;
  final int total;
  final bool visible;
  final bool showInfo;
  final bool showShare;
  final VoidCallback onClose;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleShare;
  final VoidCallback onDownload;
  final VoidCallback onToggleInfo;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final showModuleTitle = width >= 520;
    final showCenterCounter = width >= 720;
    final horizontalPadding = width >= 600 ? 24.0 : 16.0;
    final actionGap = width >= 600 ? 16.0 : 8.0;
    final counterText =
        '${(current + 1).toString().padLeft(2, '0')} / '
        '${total.toString().padLeft(2, '0')}';
    final counterStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.50),
      fontSize: AppTypography.bodySmall,
      letterSpacing: 0.08,
      fontWeight: FontWeight.w300,
    );
    final actionButtons = [
      SlideshowIconButton(
        tooltip: l10n.photosFavorite,
        icon:
            photo.favorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
        color:
            photo.favorite
                ? SeverityColors.dangerSoft
                : Colors.white.withValues(alpha: 0.70),
        onTap: onToggleFavorite,
      ),
      SizedBox(width: actionGap),
      SlideshowIconButton(
        tooltip: l10n.photosSharePhoto,
        icon: Icons.share_rounded,
        color: showShare ? Colors.white : Colors.white.withValues(alpha: 0.70),
        onTap: onToggleShare,
      ),
      SizedBox(width: actionGap),
      SlideshowIconButton(
        tooltip: l10n.photosDownloadPhoto,
        icon: Icons.download_rounded,
        onTap: onDownload,
      ),
      SizedBox(width: actionGap),
      SlideshowIconButton(
        tooltip: showInfo ? l10n.photosHideInfo : l10n.photosShowInfo,
        icon: Icons.info_outline_rounded,
        color: showInfo ? Colors.white : Colors.white.withValues(alpha: 0.70),
        onTap: onToggleInfo,
      ),
      SizedBox(width: actionGap),
      SlideshowIconButton(
        tooltip: l10n.photosFullscreen,
        icon: Icons.fullscreen_rounded,
        onTap: onFullscreen,
      ),
    ];
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          // 语义子树常驻：opacity 归零默认摘除语义，会触发 Windows 桥更新失败。
          alwaysIncludeSemantics: true,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, -0.2),
            duration: const Duration(milliseconds: 400),
            curve: Curves.ease,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20 + MediaQuery.paddingOf(context).top,
                horizontalPadding,
                32,
              ),
              child: SizedBox(
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SlideshowIconButton(
                            tooltip: l10n.photosBackToPhotos,
                            icon: Icons.close_rounded,
                            onTap: onClose,
                          ),
                          if (showModuleTitle) ...[
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: (width * 0.28).clamp(80, 220),
                              ),
                              child: Text(
                                l10n.photosModuleDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.70),
                                  fontSize: AppTypography.bodyMedium,
                                  letterSpacing: 0.04,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showCenterCounter)
                      IgnorePointer(
                        child: Text(
                          counterText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: counterStyle,
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!showCenterCounter) ...[
                            Text(
                              counterText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: counterStyle,
                            ),
                            SizedBox(width: actionGap),
                          ],
                          ...actionButtons,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Foreground slideshow layer: draws a decoded bitmap via RawImage.
///
/// Stateless and offline; the page owns the image and keeps it stable
/// across transitions. This layer only applies the given opacity/scale.
class SlideshowSlideLayer extends StatelessWidget {
  const SlideshowSlideLayer({
    required this.image,
    required this.opacity,
    required this.scale,
    super.key,
  });

  final ui.Image? image;
  final double opacity;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final resolved =
        image != null
            ? RawImage(
              image: image,
              fit: BoxFit.contain,
              // Medium: full-screen contain already scales the decode to the
              // display; high-quality sampling on multi-megapixel bitmaps
              // stalls the raster thread for seconds on entry.
              filterQuality: FilterQuality.medium,
            )
            : const ColoredBox(color: Colors.black);
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scaleByDouble(scale, scale, 1, 1),
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: RepaintBoundary(child: SizedBox.expand(child: resolved)),
      ),
    );
  }
}
