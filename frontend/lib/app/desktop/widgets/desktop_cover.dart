import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_media_thumbnail.dart';
import 'package:omninest/features/reader/reader_cover_ui.dart';

/// 封面来源：不同模块的取图通道不同，壳层按来源分派而不是各写一份。
enum DesktopCoverKind {
  /// 签名直链或已解析的绝对地址（影视、照片、外部音乐 CDN）。
  network,

  /// 音乐封面：本地曲库是鉴权 API 路径，需要专域缓存管理器。
  music,

  /// 图书封面：按 itemId 取认证字节，不能直接喂 Image.network。
  reader,
}

/// 桌面统一封面。缺失时落「同色底 + 类型图标」，不露破图也不留空洞。
class DesktopCover extends StatelessWidget {
  const DesktopCover({
    required this.url,
    this.kind = DesktopCoverKind.network,
    this.readerItemId,
    this.fallbackIcon = DesktopIcons.image,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheKey,
    this.iconSize = 22,
    super.key,
  });

  final String? url;
  final DesktopCoverKind kind;
  final String? readerItemId;
  final IconData fallbackIcon;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String? cacheKey;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final fallback = ColoredBox(
      color: skin.raise2,
      child: Center(
        child: Icon(fallbackIcon, size: iconSize, color: skin.text3),
      ),
    );
    if (kind == DesktopCoverKind.reader && readerItemId != null) {
      return AuthCoverImage(
        itemId: readerItemId!,
        coverUrl: url,
        fit: fit,
        borderRadius: borderRadius,
        fallback: fallback,
      );
    }
    return PortalMediaThumbnail(
      imageUrl: url,
      fallback: fallback,
      fit: fit,
      borderRadius: borderRadius,
      cacheKey: cacheKey,
    );
  }
}

/// 无封面图书的纸封（样例 `.paper-cover` / `.book-cover`）：
/// 左侧书脊阴影 + 衬线书名 + 作者小字。
class DesktopPaperCover extends StatelessWidget {
  const DesktopPaperCover({
    required this.title,
    required this.author,
    required this.tone,
    required this.ink,
    this.compact = false,
    super.key,
  });

  final String title;
  final String author;
  final Color tone;
  final Color ink;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(4),
          right: Radius.circular(10),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tone, Color.lerp(tone, Colors.black, 0.30)!],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 40,
            offset: const Offset(0, 24),
            spreadRadius: -14,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.white.withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0.10),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 16,
            top: 22,
            child: Container(height: 1, color: ink.withValues(alpha: 0.4)),
          ),
          Positioned(
            left: 24,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.chapter(
                    ink,
                  ).copyWith(fontWeight: FontWeight.w500, height: 1.12),
                ),
                const SizedBox(height: 4),
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.micro(ink.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 书封面的静止 3D 倾角与 hover 抬角（样例 `.bp-cover` / `.cont-book`）。
///
/// 两处口径不同：书详 `rotateY(-14deg) -> -4deg`；阅读页继续阅读卡
/// `rotateY(-18deg) rotateX(3deg) -> -6deg / 0 / 上移 6px`。时长都是 800ms
/// `--spring`，用 [DesktopMotion.pageFlip]（820ms）就近表达。
class DesktopBookTilt extends StatelessWidget {
  const DesktopBookTilt({
    required this.child,
    this.restY = -14,
    this.restX = 0,
    this.hoverY = -4,
    this.hoverX = 0,
    this.hoverLift = 0,
    super.key,
  });

  final Widget child;
  final double restY;
  final double restX;
  final double hoverY;
  final double hoverX;
  final double hoverLift;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return DesktopHover(
      builder: (context, hovered) {
        final active = hovered && !reduced;
        final y = active ? hoverY : restY;
        final x = active ? hoverX : restX;
        return AnimatedContainer(
          duration: MotionToken.reduced(context, DesktopMotion.pageFlip),
          curve: DesktopMotion.spring,
          transformAlignment: Alignment.center,
          // perspective(900px) 等价于 setEntry(3, 2, 1/900)。
          transform:
              Matrix4.identity()
                ..setEntry(3, 2, 1 / 900)
                ..rotateX(x * math.pi / 180)
                ..rotateY(y * math.pi / 180),
          child: Transform.translate(
            offset: Offset(0, active ? hoverLift : 0),
            child: child,
          ),
        );
      },
    );
  }
}
