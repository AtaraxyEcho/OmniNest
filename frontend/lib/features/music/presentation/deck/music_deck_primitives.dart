import 'dart:convert';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/data/music_cover_cache.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

/// Music Deck 局部玻璃表面。
class MusicDeckGlass extends StatelessWidget {
  const MusicDeckGlass({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.opacity = 0.18,
    this.blur = 12,
    this.borderRadius = 8,
    this.fillColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double opacity;
  final double blur;
  final double borderRadius;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final light = Theme.of(context).brightness == Brightness.light;
    final resolvedFillColor = fillColor ?? colors.surfaceContainer;
    final fillAlpha =
        opacity < resolvedFillColor.a ? opacity : resolvedFillColor.a;
    final requestedOutlineAlpha = light ? 0.68 : 1.0;
    final outlineAlpha =
        requestedOutlineAlpha < colors.outline.a
            ? requestedOutlineAlpha
            : colors.outline.a;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          color: resolvedFillColor.withValues(alpha: fillAlpha),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(
              color: colors.outline.withValues(alpha: outlineAlpha),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 统一处理本地和在线音乐封面。
class MusicDeckArtwork extends StatelessWidget {
  const MusicDeckArtwork({
    required this.title,
    this.imageUrl,
    this.icon = Icons.music_note_rounded,
    this.borderRadius = 6,
    super.key,
  });

  final String title;
  final String? imageUrl;
  final IconData icon;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final image = _buildImage(context, constraints);
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: ColoredBox(
            color: colors.surfaceContainer,
            child: image ?? _ArtworkFallback(icon: icon, size: 36),
          ),
        );
      },
    );
  }

  Widget? _buildImage(BuildContext context, BoxConstraints constraints) {
    final source = imageUrl?.trim();
    if (source == null || source.isEmpty) {
      return null;
    }
    if (source.startsWith('data:image/')) {
      final comma = source.indexOf(',');
      if (comma < 0) {
        return null;
      }
      try {
        return Image.memory(
          base64Decode(source.substring(comma + 1)),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        );
      } on FormatException {
        return null;
      }
    }
    final logicalWidth =
        constraints.maxWidth.isFinite ? constraints.maxWidth : 240.0;
    final cacheWidth = (logicalWidth * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(120, 1200);
    // 本地封面走稳定鉴权 API 路径时使用专域缓存管理器（dio 拼 baseUrl
    // 并附带鉴权头）；CDN 地址与缓存未注入时保持默认路径。Web 端默认
    // HtmlImage 渲染会绕过 cacheManager 并把相对 URL 按页面 origin 解析，
    // 必须切到 HttpGet 走管理器下载，否则跨源部署下封面全部 404。
    final manager =
        isMusicCoverApiPath(source) ? MusicCoverCache.maybeInstance : null;
    return CachedNetworkImage(
      imageUrl: source,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: cacheWidth,
      maxWidthDiskCache: cacheWidth,
      cacheManager: manager,
      imageRenderMethodForWeb:
          manager == null
              ? ImageRenderMethodForWeb.HtmlImage
              : ImageRenderMethodForWeb.HttpGet,
      useOldImageOnUrlChange: true,
      fadeInDuration: const Duration(milliseconds: 160),
      fadeOutDuration: const Duration(milliseconds: 80),
      filterQuality: FilterQuality.medium,
      placeholder: (context, url) => _ArtworkFallback(icon: icon, size: 34),
      errorWidget:
          (context, url, error) => _ArtworkFallback(icon: icon, size: 34),
    );
  }
}

/// 封面占位/加载失败的艺术兜底：对角渐变提亮深色场景，
/// 避免无封面歌单在玻璃叠层下呈现纯黑观感。
class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colors.surfaceContainer,
                colors.surfaceContainerHigh,
                Color.lerp(colors.surfaceContainerHigh, colors.primary, 0.18)!,
              ],
            ),
          ),
        ),
        Center(
          child: Icon(
            icon,
            color: colors.onSurface.withValues(alpha: 0.78),
            size: size,
          ),
        ),
      ],
    );
  }
}

/// 音乐来源标签。
class MusicDeckSourceBadge extends StatelessWidget {
  const MusicDeckSourceBadge({
    required this.platform,
    this.overlay = false,
    super.key,
  });

  final MusicPlatform platform;
  final bool overlay;

  /// 常规徽章平台色：中性微底 + 平台色描边与文字的胶囊形态，
  /// 识别由平台色承担，文字不再铺实底色块。
  static Color badgeColor(MusicPlatform platform, bool light) {
    return switch (platform) {
      MusicPlatform.local =>
        light ? const Color(0xFF58605B) : const Color(0xFFC4CCC8),
      MusicPlatform.netease =>
        light ? const Color(0xFF9A3037) : const Color(0xFFF28C8C),
      MusicPlatform.qq =>
        light ? const Color(0xFF735A08) : const Color(0xFFF0CD76),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    final colors = context.musicColors;
    final label = musicDeckSourceLabel(l10n, platform);
    final color = badgeColor(platform, light);
    // 覆盖在封面等影像上时沿用近实底表面 + 平台色文字描边。
    if (overlay) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.46)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: AppTypography.labelSmall,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 返回音乐来源平台的国际化名称。
String musicDeckSourceLabel(AppLocalizations l10n, MusicPlatform platform) {
  return switch (platform) {
    MusicPlatform.local => l10n.musicDeckSourceLocal,
    MusicPlatform.netease => l10n.musicDeckSourceNetease,
    MusicPlatform.qq => l10n.musicDeckSourceQq,
  };
}
