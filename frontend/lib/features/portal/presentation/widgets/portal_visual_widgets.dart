import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/reader_cover_ui.dart';
import 'package:omninest/core/widgets/brand_logo.dart';

class PortalVisualPalette {
  const PortalVisualPalette({
    required this.background,
    required this.surface,
    required this.surfaceStrong,
    required this.clearStructuralSurfaces,
    required this.lightweightSurfaceAlpha,
    required this.structuralAlphaCeiling,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentAlt,
    required this.glow,
  });

  final Color background;
  final Color surface;
  final Color surfaceStrong;
  final bool clearStructuralSurfaces;
  final double lightweightSurfaceAlpha;
  final double? structuralAlphaCeiling;
  final Color text;
  final Color muted;
  final Color accent;
  final Color accentAlt;
  final Color glow;

  /// 返回结构面板填充色，浅色透明模式仅保留边框和阴影。
  Color structuralSurface({double? alpha}) {
    if (clearStructuralSurfaces) {
      return Colors.transparent;
    }
    return alpha == null
        ? surface
        : surface.withValues(alpha: _resolveStructuralAlpha(alpha));
  }

  /// 返回强调控件填充色，浅色透明模式不叠加任何染色层。
  Color structuralStrongSurface({double? alpha}) {
    if (clearStructuralSurfaces) {
      return Colors.transparent;
    }
    return alpha == null
        ? surfaceStrong
        : surfaceStrong.withValues(alpha: _resolveStructuralAlpha(alpha));
  }

  double _resolveStructuralAlpha(double requested) {
    final ceiling = structuralAlphaCeiling;
    if (ceiling == null || requested <= ceiling) {
      return requested;
    }
    return ceiling;
  }

  static PortalVisualPalette of(
    BuildContext context, {
    bool backdropActive = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    if (scheme.brightness == Brightness.light && backdropActive) {
      return const PortalVisualPalette(
        background: Colors.transparent,
        surface: Color(0x4D0C1920),
        surfaceStrong: Color(0x7512242B),
        clearStructuralSurfaces: false,
        lightweightSurfaceAlpha: 0.18,
        structuralAlphaCeiling: 0.46,
        text: Color(0xFFF4F7F5),
        muted: Color(0xD1D6E3E1),
        accent: Color(0xFF9FDBE3),
        accentAlt: Color(0xFFD5C27A),
        glow: Color(0x383D8EA0),
      );
    }
    if (scheme.brightness == Brightness.light) {
      final background =
          Color.lerp(scheme.surface, scheme.primaryContainer, 0.06)!;
      final surface =
          Color.lerp(scheme.surfaceContainer, scheme.primaryContainer, 0.12)!;
      final surfaceStrong =
          Color.lerp(
            scheme.surfaceContainerHigh,
            scheme.secondaryContainer,
            0.08,
          )!;
      return PortalVisualPalette(
        background: background,
        surface: surface.withValues(alpha: 0.48),
        surfaceStrong: surfaceStrong.withValues(alpha: 0.62),
        clearStructuralSurfaces: true,
        lightweightSurfaceAlpha: 0,
        structuralAlphaCeiling: 0,
        text: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        accent: scheme.primary,
        accentAlt: scheme.tertiary,
        glow: scheme.primary.withValues(alpha: 0.16),
      );
    }
    if (!backdropActive) {
      // 深色无壁纸（Web / 桌面未启用）：烟熏玻璃色板是按「背后有亮壁纸」
      // 设计的，直接压在近黑舞台上会整体灰暗；回落常规暗色表面
      // （与浅色无壁纸分支同构），文字用主题前景色。
      final background =
          Color.lerp(scheme.surface, scheme.primaryContainer, 0.04)!;
      final surface =
          Color.lerp(scheme.surfaceContainer, scheme.primaryContainer, 0.08)!;
      final surfaceStrong =
          Color.lerp(
            scheme.surfaceContainerHigh,
            scheme.secondaryContainer,
            0.05,
          )!;
      return PortalVisualPalette(
        background: background,
        surface: surface,
        surfaceStrong: surfaceStrong,
        clearStructuralSurfaces: false,
        lightweightSurfaceAlpha: 0.18,
        structuralAlphaCeiling: null,
        text: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        accent: scheme.primary,
        accentAlt: scheme.tertiary,
        glow: scheme.primary.withValues(alpha: 0.16),
      );
    }
    return const PortalVisualPalette(
      background: Color(0xFF071016),
      surface: Color(0xA6121D25),
      surfaceStrong: Color(0xD9142029),
      clearStructuralSurfaces: false,
      lightweightSurfaceAlpha: 0.36,
      structuralAlphaCeiling: null,
      text: Color(0xFFF4F7F5),
      muted: Color(0xB8DDE8E7),
      accent: Color(0xFF9FDBE3),
      accentAlt: Color(0xFFD5C27A),
      glow: Color(0x663D8EA0),
    );
  }
}

/// Portal 动效工具。
class PortalMotion {
  const PortalMotion._();

  /// 根据系统减少动态效果设置返回动画时长。
  static Duration duration(BuildContext context, Duration value) {
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return disabled ? Duration.zero : value;
  }
}

/// 沉浸模式下可通过指针或键盘焦点唤出的顶栏区域。
class PortalImmersiveTopBarReveal extends StatefulWidget {
  const PortalImmersiveTopBarReveal({
    required this.immersive,
    required this.child,
    this.height = 58,
    super.key,
  });

  final bool immersive;
  final Widget child;
  final double height;

  @override
  State<PortalImmersiveTopBarReveal> createState() =>
      _PortalImmersiveTopBarRevealState();
}

class _PortalImmersiveTopBarRevealState
    extends State<PortalImmersiveTopBarReveal> {
  bool _pointerInside = false;
  bool _focusWithin = false;

  bool get _visible => !widget.immersive || _pointerInside || _focusWithin;

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Focus(
      key: const ValueKey('portal-immersive-top-bar-focus-region'),
      canRequestFocus: widget.immersive,
      onFocusChange: (focused) {
        if (_focusWithin != focused) {
          setState(() => _focusWithin = focused);
        }
      },
      child: MouseRegion(
        onEnter: (_) => _setPointerInside(true),
        onExit: (_) => _setPointerInside(false),
        child: SizedBox(
          key: const ValueKey('portal-immersive-top-bar'),
          height: widget.height,
          child: ExcludeFocus(
            excluding: widget.immersive && !visible,
            child: IgnorePointer(
              ignoring: widget.immersive && !visible,
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, -0.78),
                duration: PortalMotion.duration(
                  context,
                  const Duration(milliseconds: 220),
                ),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: PortalMotion.duration(
                    context,
                    const Duration(milliseconds: 180),
                  ),
                  curve: Curves.easeOutCubic,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setPointerInside(bool value) {
    if (_pointerInside == value) {
      return;
    }
    setState(() => _pointerInside = value);
  }
}

class PortalVisualPanel extends StatelessWidget {
  const PortalVisualPanel({
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.lightweight = false,
    this.onTap,
    super.key,
  });

  final PortalVisualPalette palette;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool lightweight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final lightForeground =
        ThemeData.estimateBrightnessForColor(palette.text) == Brightness.light;
    final surfaceColor =
        lightweight
            ? palette.structuralSurface(alpha: palette.lightweightSurfaceAlpha)
            : palette.structuralSurface();
    final borderColor =
        lightForeground
            ? Colors.white.withValues(alpha: lightweight ? 0.13 : 0.18)
            : light
            ? Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: lightweight ? 0.10 : 0.14)
            : Colors.white.withValues(alpha: lightweight ? 0.12 : 0.16);
    final shadowColor = Colors.black.withValues(
      alpha:
          !light
              ? (lightweight ? 0.08 : 0.32)
              : lightForeground
              ? (lightweight ? 0.10 : 0.20)
              : (lightweight ? 0.04 : 0.08),
    );
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: lightweight ? 10 : (light ? 22 : 36),
            offset: Offset(0, lightweight ? 4 : (light ? 8 : 18)),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class PortalVisualTopBar extends StatelessWidget {
  const PortalVisualTopBar({
    required this.palette,
    required this.trailing,
    required this.onSearch,
    super.key,
  });

  final PortalVisualPalette palette;
  final List<Widget> trailing;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          const BrandLogo(size: 34, radius: 8),
          const SizedBox(width: 12),
          Text(
            'OmniNest',
            style: TextStyle(
              color: palette.text,
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onSearch,
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: palette.structuralStrongSurface(alpha: 0.62),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: palette.muted.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            color: palette.muted,
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.portalSearch,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: AppTypography.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          ...trailing,
        ],
      ),
    );
  }
}

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
      1 => const Color(0xFF263A66),
      2 => const Color(0xFF244641),
      _ => const Color(0xFF20233D),
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

class _AdaptiveCoverImage extends StatelessWidget {
  const _AdaptiveCoverImage({
    required this.fallbackColors,
    required this.foregroundFit,
    required this.foregroundPadding,
    required this.directImage,
    this.imageUrl,
    this.readerItemId,
  });

  final String? imageUrl;
  final String? readerItemId;
  final List<Color> fallbackColors;
  final BoxFit foregroundFit;
  final EdgeInsetsGeometry foregroundPadding;
  final bool directImage;

  @override
  Widget build(BuildContext context) {
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
        return AuthCoverImage(
          itemId: readerCoverItemId,
          fit: BoxFit.cover,
          fallback: fallback,
        );
      }
      return CachedNetworkImage(
        imageUrl: networkCoverUrl!,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        placeholder: (context, url) => fallback,
        errorWidget: (context, url, error) => fallback,
      );
    }
    if (readerCoverItemId != null) {
      return _ReaderAdaptiveCoverImage(
        itemId: readerCoverItemId,
        fallbackColors: fallbackColors,
        foregroundFit: foregroundFit,
        foregroundPadding: foregroundPadding,
      );
    }
    return _NetworkAdaptiveCoverImage(
      imageUrl: networkCoverUrl!,
      fallbackColors: fallbackColors,
      foregroundFit: foregroundFit,
      foregroundPadding: foregroundPadding,
    );
  }
}

class _ReaderAdaptiveCoverImage extends StatelessWidget {
  const _ReaderAdaptiveCoverImage({
    required this.itemId,
    required this.fallbackColors,
    required this.foregroundFit,
    required this.foregroundPadding,
  });

  final String itemId;
  final List<Color> fallbackColors;
  final BoxFit foregroundFit;
  final EdgeInsetsGeometry foregroundPadding;

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
          child: AuthCoverImage(
            itemId: itemId,
            fit: foregroundFit,
            fallback: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _NetworkAdaptiveCoverImage extends StatelessWidget {
  const _NetworkAdaptiveCoverImage({
    required this.imageUrl,
    required this.fallbackColors,
    required this.foregroundFit,
    required this.foregroundPadding,
  });

  final String imageUrl;
  final List<Color> fallbackColors;
  final BoxFit foregroundFit;
  final EdgeInsetsGeometry foregroundPadding;

  @override
  Widget build(BuildContext context) {
    final fallback = _CoverImageFallback(colors: fallbackColors);
    return Stack(
      fit: StackFit.expand,
      children: [
        _AmbientCoverBackdrop(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            memCacheWidth: _ambientBackdropCacheWidth,
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
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: foregroundFit,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            placeholder: (context, url) => const SizedBox.shrink(),
            errorWidget: (context, url, error) => const SizedBox.shrink(),
          ),
        ),
      ],
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
    this.includeAdmin = true,
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
