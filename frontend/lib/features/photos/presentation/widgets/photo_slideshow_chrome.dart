import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 幻灯片顶栏图标按钮：透明底、紧凑密度、跟随控制显隐。
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

/// 幻灯片顶部栏：左关闭+标题、中页码、右操作组。
///
/// 三区用 Stack 对齐，避免 Flexible/Spacer 均分剩余宽度导致桌面端挤成一团。
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
                ? const Color(0xFFFB7185)
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

/// 前景幻灯片单层：直接绘制解码位图（RawImage）。
///
/// 无状态、无网络——位图引用由页面持有并跨切换稳定，
/// 层本身只根据调用方给定的 opacity/scale 绘制（合成级操作）。
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
              // 主图 high：缩放动画期间最高采样质量；缩略图/backdrop 仍为 medium。
              filterQuality: FilterQuality.high,
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
