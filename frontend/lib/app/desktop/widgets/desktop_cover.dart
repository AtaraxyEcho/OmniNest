import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
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
    this.fallback,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheKey,
    this.cacheWidth,
    this.cacheHeight,
    this.iconSize = 22,
    super.key,
  });

  final String? url;
  final DesktopCoverKind kind;
  final String? readerItemId;
  final IconData fallbackIcon;

  /// 可选的首帧/失败占位。首页照片条需要保持透明，避免出现原型没有的
  /// 图标卡片闪现；其他调用方继续使用按模块图标回退。
  final Widget? fallback;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String? cacheKey;
  final int? cacheWidth;
  final int? cacheHeight;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final fallback =
        this.fallback ??
        ColoredBox(
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
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
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

/// Reader 书籍封面：对应样例 `Cover` 与 `.book-cover.art`。
///
/// 封面图仍通过 Reader 的鉴权取图通道加载，图像之上保留原型的书脊、
/// 底部暗部、标题层、类型标签和 hover 光泽；没有图像时复用同一套结构，
/// 这样网格卡片、继续阅读卡和书籍详情不会产生两种封面语义。
class DesktopReaderBookCover extends StatelessWidget {
  const DesktopReaderBookCover({
    required this.itemId,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.isComic,
    this.readerType = 'BOOK',
    this.volumeNumber,
    this.large = false,
    this.compact = false,
    this.hoveredOverride,
    super.key,
  });

  final String itemId;
  final String title;
  final String author;
  final String? coverUrl;
  final bool isComic;
  final String readerType;
  final int? volumeNumber;
  final bool large;
  final bool compact;
  final bool? hoveredOverride;

  static const _radius = BorderRadius.only(
    topLeft: Radius.circular(4),
    topRight: Radius.circular(10),
    bottomRight: Radius.circular(10),
    bottomLeft: Radius.circular(4),
  );

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final hasArt = coverUrl?.isNotEmpty == true;
    final subtitle =
        volumeNumber == null
            ? author
            : '${l10n.readerLabelVolume} $volumeNumber';
    final tag =
        readerType == 'MANGA' ? l10n.readerTypeManga : l10n.readerTypeComic;

    return DesktopHover(
      builder: (context, localHovered) {
        final hovered = hoveredOverride ?? localHovered;
        final gloss = AnimatedSlide(
          offset: hovered ? const Offset(0.6, 0) : const Offset(-0.6, 0),
          // 原型 `.book-cover .gloss` 使用 1s 过渡；过短会让光带像
          // hover 闪烁，并且在父卡片抬升时露出不连续的边缘。
          duration: MotionToken.reduced(
            context,
            const Duration(milliseconds: 1000),
          ),
          curve: DesktopMotion.ease,
          child: SizedBox.expand(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  // CSS `linear-gradient(115deg, ...)`：从左上向右下
                  // 斜过封面，不能用默认的水平或反向斜线近似。
                  begin: const Alignment(-0.906, -0.423),
                  end: const Alignment(0.906, 0.423),
                  colors: [
                    Colors.transparent,
                    Colors.white.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                  stops: const [0.4, 0.5, 0.6],
                ),
              ),
            ),
          ),
        );
        // 外层仅画阴影；底色、图片、暗色遮罩统一收口至单一 ClipRRect(Clip.antiAlias)，
        // 彻底移除 antiAliasWithSaveLayer 消除旋转与 3D 倾斜时的斜边像素锯齿。
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: _radius,
            boxShadow:
                hovered
                    ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.7),
                        blurRadius: 50,
                        offset: const Offset(0, 40),
                        spreadRadius: -18,
                      ),
                    ]
                    : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 40,
                        offset: const Offset(0, 24),
                        spreadRadius: -14,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
          ),
          child: ClipRRect(
            borderRadius: _radius,
            clipBehavior: Clip.antiAlias,
            // Container 才同时支持 decoration 与 foregroundDecoration，
            // 前景细描边必须与底色/图片同一裁切，避免悬停旋转时出锯齿。
            child: Container(
              decoration: BoxDecoration(
                color: hasArt ? skin.panelSolid : null,
                gradient:
                    hasArt
                        ? null
                        : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            skin.accent.withValues(alpha: large ? 0.38 : 0.32),
                            Color.lerp(skin.accent, Colors.black, 0.55)!,
                          ],
                        ),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: _radius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.75,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasArt)
                    DesktopCover(
                      url: coverUrl,
                      kind: DesktopCoverKind.reader,
                      readerItemId: itemId,
                      fallbackIcon: DesktopIcons.book,
                      cacheKey: 'desktop-reader-cover-$itemId',
                      iconSize: large ? 28 : 20,
                    ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: compact ? 5 : 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.35),
                            Colors.white.withValues(alpha: 0.12),
                            Colors.black.withValues(alpha: 0.10),
                          ],
                          stops: const [0, 0.4, 1],
                        ),
                      ),
                    ),
                  ),
                  // 有封面图时不再覆满高对比暗色遮罩（书名作者已在卡片下方展示），
                  // 既彻底消除暗色边缘对比锯齿，又完整呈现原版封面色彩质感。                  if (!compact && !hasArt)
                  Positioned(
                    left: 24,
                    right: 16,
                    top: 22,
                    child: ColoredBox(
                      color: (hasArt ? Colors.white : skin.text).withValues(
                        alpha: 0.4,
                      ),
                      child: const SizedBox(height: 1),
                    ),
                  ),
                  if (isComic && !compact && hasArt)
                    Positioned(
                      top: 12,
                      right: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          child: Text(
                            tag,
                            style: DesktopType.micro(Colors.white).copyWith(
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (isComic && !compact && !hasArt)
                    Positioned(
                      top: 34,
                      left: 24,
                      child: Text(
                        l10n.readerTypeComic,
                        style: DesktopType.micro(
                          skin.text.withValues(alpha: 0.7),
                        ).copyWith(letterSpacing: 1.8),
                      ),
                    ),
                  if (!compact)
                    Positioned(
                      left: 24,
                      right: hasArt ? 14 : 16,
                      bottom: hasArt ? 14 : 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: large ? 4 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.coverTitle(
                              hasArt ? Colors.white : skin.text,
                              large: large,
                            ).copyWith(
                              shadows:
                                  hasArt
                                      ? [
                                        const Shadow(
                                          color: Colors.black54,
                                          blurRadius: 8,
                                          offset: Offset(0, 1),
                                        ),
                                      ]
                                      : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.micro(
                              (hasArt ? Colors.white : skin.text).withValues(
                                alpha: 0.75,
                              ),
                            ).copyWith(
                              shadows:
                                  hasArt
                                      ? [
                                        const Shadow(
                                          color: Colors.black54,
                                          blurRadius: 8,
                                          offset: Offset(0, 1),
                                        ),
                                      ]
                                      : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!compact)
                    Positioned.fill(child: IgnorePointer(child: gloss)),
                ],
              ),
            ),
          ),
        );
      },
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
    this.hoveredOverride,
    super.key,
  });

  final Widget child;
  final double restY;
  final double restX;
  final double hoverY;
  final double hoverX;
  final double hoverLift;
  final bool? hoveredOverride;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return DesktopHover(
      builder: (context, localHovered) {
        final hovered = hoveredOverride ?? localHovered;
        final active = hovered && !reduced;
        final y = active ? hoverY : restY;
        final x = active ? hoverX : restX;
        return AnimatedContainer(
          duration: MotionToken.reduced(
            context,
            const Duration(milliseconds: 260),
          ),
          curve: Curves.easeOutCubic,
          transformAlignment: Alignment.center,
          // 合并单矩阵变换 + 1px 透明抗锯齿缓冲边，平滑 3D 透视斜边毛刺。
          transform:
              Matrix4.identity()
                ..setEntry(3, 2, 1 / 900)
                ..translateByDouble(0.0, active ? hoverLift : 0.0, 0.0, 1.0)
                ..rotateX(x * math.pi / 180)
                ..rotateY(y * math.pi / 180),
          child: Padding(padding: const EdgeInsets.all(1), child: child),
        );
      },
    );
  }
}
