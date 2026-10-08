import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/library/presentation/widgets/library_space_tier.dart';
import 'package:omninest/features/photos/application/photo_browse_scope.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/portal/portal_ui.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';

/// Library 分段（All/Photos/Movies/Music）。
enum LibrarySegment { all, photos, movies, music }

/// 分段切换条：轻量胶囊分段，切换不离开 Library 空间。
class LibrarySegmentBar extends StatelessWidget {
  const LibrarySegmentBar({
    required this.segment,
    required this.onChanged,
    super.key,
  });

  final LibrarySegment segment;
  final ValueChanged<LibrarySegment> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      LibrarySegment.all: l10n.librarySegmentAll,
      LibrarySegment.photos: l10n.portalDockPhotos,
      LibrarySegment.movies: l10n.portalDockMovies,
      LibrarySegment.music: l10n.mobileNavMusic,
    };
    // 分段是空间内主导航，按触控裁决抬到 48；标签总宽超出可用宽度时
    // 横向可滚，不靠缩放或裁剪兜底。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.env.segmentBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.env.line09),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in LibrarySegment.values)
                _LibrarySegmentChip(
                  label: labels[entry]!,
                  selected: segment == entry,
                  onTap: () => onChanged(entry),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibrarySegmentChip extends StatelessWidget {
  const _LibrarySegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      semanticLabel: label,
      onTap: onTap,
      child: AnimatedContainer(
        duration: MobileLayoutTokens.stateDuration,
        curve: MobileLayoutTokens.motionCurve,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: MobileLayoutTokens.minimumTarget,
        decoration: BoxDecoration(
          color: selected ? context.env.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                  : null,
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: selected ? context.env.onAccentDeep : context.env.inkMuted,
              fontSize: AppTypography.bodyMedium,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Library 区块标题：eyebrow + 标题 + 「查看全部」动作。
class LibrarySectionHeader extends StatelessWidget {
  const LibrarySectionHeader({
    required this.eyebrow,
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.env.white43,
                  // ignore: font_size_whitelist
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.env.ink,
                  // ignore: font_size_whitelist
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: context.env.white70,
              minimumSize: const Size(48, 38),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(fontSize: AppTypography.labelSmall),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel!),
                const SizedBox(width: 1),
                OmniIcon(
                  icon: OmniIcons.chevron,
                  size: 16,
                  color: context.env.white70,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 记忆横幅：最新相册大图 + 衬线标题 + 主行动。
class LibraryFeatureBanner extends StatelessWidget {
  const LibraryFeatureBanner({
    required this.imageUrl,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onTap,
    super.key,
  });

  final String? imageUrl;
  final String eyebrow;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tier = LibrarySpaceTier.resolve(context);
    return MobilePressable(
      semanticLabel: title,
      onTap: onTap,
      child: SizedBox(
        height: tier.featureHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 45,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null && imageUrl!.isNotEmpty)
                  PortalMediaThumbnail(
                    imageUrl: imageUrl!,
                    cacheHeight: 620,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.zero,
                    fallback: _bannerFallback(context),
                  )
                else
                  _bannerFallback(context),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xC7050A09), Color(0x14050A09)],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0x8C040807), Colors.transparent],
                      stops: [0, 0.6],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 23),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow.toUpperCase(),
                        style: const TextStyle(
                          // polarity-stable：压在影像上，对比由图片本身提供，两极性同值
                          color: Color(0xA1FFFFFF),
                          fontSize: AppTypography.labelMicro,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          // polarity-stable：压在影像上，对比由图片本身提供，两极性同值
                          color: Colors.white,
                          fontFamily: AppTypography.serifFamily,
                          fontFamilyFallback: AppTypography.serifFamilyFallback,
                          fontSize: AppTypography.displaySmall,
                          height: 0.98,
                          letterSpacing: -0.4,
                          shadows: [
                            Shadow(blurRadius: 14, color: Colors.black45),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.env.inkMuted,
                          fontSize: AppTypography.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: onTap,
                          style: FilledButton.styleFrom(
                            backgroundColor: context.env.buttonInk,
                            foregroundColor: context.env.onButtonInk,
                            minimumSize: const Size(64, 43),
                            padding: const EdgeInsets.symmetric(horizontal: 17),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: AppTypography.bodySmall,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          icon: OmniIcon(
                            icon: OmniIcons.play,
                            size: 16,
                            color: context.env.onButtonInk,
                          ),
                          label: Text(actionLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bannerFallback(BuildContext context) {
    return ColoredBox(
      color: context.env.surfaceTint,
      child: Center(
        child: OmniIcon(
          icon: OmniIcons.image,
          size: 40,
          color: context.env.ink40,
        ),
      ),
    );
  }
}

// 照片马赛克：1 大 + 2 小 + 计数条。
class LibraryPhotoMosaic extends ConsumerWidget {
  const LibraryPhotoMosaic({
    required this.photos,
    required this.onOpenModule,
    super.key,
  });

  final List<PhotoItem> photos;

  /// 点击计数瓦片进入照片模块。
  final VoidCallback onOpenModule;

  static const int _maxTiles = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final total = photos.length;
    if (total == 0) {
      return EnvEmptyState(
        icon: OmniIcons.image,
        title: l10n.libraryEmptyPhotosTitle,
        message: l10n.libraryEmptyPhotosMessage,
        compact: true,
      );
    }
    final tier = LibrarySpaceTier.resolve(context);
    final remaining = total > _maxTiles ? total - _maxTiles : 0;
    Widget tile(PhotoItem photo, {BoxFit fit = BoxFit.cover}) {
      return MobilePressable(
        semanticLabel: photo.title,
        onTap: () {
          ref
              .read(photoBrowseScopeProvider.notifier)
              .set(photos, PhotoBrowseSource.library);
          context.push('/photos/${photo.id}');
        },
        child: PortalMediaThumbnail(
          imageUrl: photo.coverUrl ?? '',
          cacheKey: photo.coverCacheKey,
          cacheHeight: 560,
          fit: fit,
          borderRadius: BorderRadius.zero,
          fallback: ColoredBox(
            color: scheme.surfaceContainerHigh,
            child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    if (total == 1) {
      // 单张铺满两行（原型 button:first-child 为 grid-row: span 2）。
      return SizedBox(height: tier.mosaicHeight, child: tile(photos.first));
    }
    return SizedBox(
      height: tier.mosaicHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 145, child: tile(photos.first)),
          const SizedBox(width: 5),
          Expanded(
            flex: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (total > 1)
                        Expanded(child: ClipRRect(child: tile(photos[1]))),
                      if (total > 2) ...[
                        const SizedBox(width: 5),
                        Expanded(child: tile(photos[2])),
                      ],
                      if (total == 2)
                        Expanded(
                          child: _MoreTile(
                            count: remaining,
                            onTap: onOpenModule,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Expanded(
                  child:
                      total > 3
                          ? Stack(
                            fit: StackFit.expand,
                            children: [
                              tile(photos[3]),
                              Positioned.fill(
                                child: _MoreTile(
                                  count: remaining,
                                  onTap: onOpenModule,
                                ),
                              ),
                            ],
                          )
                          : _MoreTile(count: total - 2, onTap: onOpenModule),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「+N」计数瓦片：提示库内还有更多照片。
/// 「+N」计数瓦片：深色遮罩铺满所在瓦（圆角由外层裁切承担）。
class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      semanticLabel: '+$count',
      onTap: onTap,
      child: ColoredBox(
        color: const Color(0x80060B0A),
        child: Center(
          child: Text(
            '+$count',
            style: const TextStyle(
              // polarity-stable：压在影像上，对比由图片本身提供，两极性同值
              color: Colors.white,
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// 横向内容轨通用容器：右侧出血延伸到屏幕边缘。
class LibraryRail extends StatelessWidget {
  const LibraryRail({required this.height, required this.children, super.key});

  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // 右出血：轨道内容允许滚动到父容器右缘之外（样例 margin-right:-20）。
    // 出血量取当前档位的页边距，保证出血后正好贴到内容盒外缘。
    final bleed = LibrarySpaceTier.resolve(context).horizontalPadding;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder:
            (context, constraints) => OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: constraints.maxWidth + bleed,
              child: SizedBox(
                width: constraints.maxWidth + bleed,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  clipBehavior: Clip.none,
                  itemCount: children.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 13),
                  itemBuilder: (context, index) => children[index],
                ),
              ),
            ),
      ),
    );
  }
}

/// 影视海报卡：海报 + 进度 + 播放浮钮。
class LibraryPosterCard extends StatelessWidget {
  const LibraryPosterCard({
    required this.imageUrl,
    required this.title,
    required this.detail,
    this.progress,
    this.showPlayButton = true,
    required this.onTap,
    super.key,
  });

  final String? imageUrl;
  final String title;
  final String? detail;

  /// 0-1 播放进度；null 不显示进度条。
  final double? progress;
  final bool showPlayButton;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tier = LibrarySpaceTier.resolve(context);
    return MobilePressable(
      semanticLabel: title,
      onTap: onTap,
      child: SizedBox(
        width: tier.posterWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: tier.posterHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: PortalMediaThumbnail(
                      imageUrl: imageUrl ?? '',
                      cacheHeight: 420,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.zero,
                      fallback: ColoredBox(
                        color: context.env.surfaceTint,
                        child: Center(
                          child: OmniIcon(
                            icon: OmniIcons.film,
                            size: 26,
                            color: context.env.white46,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0x66000000)],
                            stops: [0.4, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showPlayButton)
                    const Positioned(
                      left: 10,
                      bottom: 13,
                      child: _PosterPlayBadge(),
                    ),
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0, 1),
                        minHeight: 3,
                        color: context.env.accentInk,
                        // polarity-stable：压在影像上，对比由图片本身提供，两极性同值
                        backgroundColor: const Color(0x3DFFFFFF),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.env.ink,
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null && detail!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.env.inkMuted,
                    fontSize: AppTypography.labelMicro,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 海报左下角的白色播放浮钮（原型 poster-play）。
class _PosterPlayBadge extends StatelessWidget {
  const _PosterPlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 35,
      height: 35,
      decoration: BoxDecoration(
        color: context.env.posterPlayBg,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: OmniIcon(
          icon: OmniIcons.play,
          size: 16,
          color: context.env.posterPlayFg,
        ),
      ),
    );
  }
}

// 音乐专辑卡：方形封面 + 播放浮钮。
class LibraryAlbumCard extends StatelessWidget {
  const LibraryAlbumCard({
    required this.imageUrl,
    required this.title,
    required this.detail,
    required this.onTap,
    super.key,
  });

  final String? imageUrl;
  final String title;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = LibrarySpaceTier.resolve(context).albumSize;
    return MobilePressable(
      semanticLabel: title,
      onTap: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 25,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: PortalMediaThumbnail(
                        imageUrl: imageUrl ?? '',
                        cacheHeight: 330,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.zero,
                        fallback: ColoredBox(
                          color: context.env.surfaceTint,
                          child: Center(
                            child: OmniIcon(
                              icon: OmniIcons.music,
                              size: 26,
                              color: context.env.white46,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: context.env.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: context.env.accent.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Center(
                        child: OmniIcon(
                          icon: OmniIcons.play,
                          size: 18,
                          color: context.env.onAccent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.env.ink,
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null && detail!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.env.inkMuted,
                    fontSize: AppTypography.labelMicro,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 收藏照片横轨瓦片。
class LibraryFavoritePhotoTile extends ConsumerWidget {
  const LibraryFavoritePhotoTile({
    required this.photos,
    required this.index,
    super.key,
  });

  final List<PhotoItem> photos;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final photo = photos[index];
    return MobilePressable(
      semanticLabel: photo.title,
      onTap: () {
        ref
            .read(photoBrowseScopeProvider.notifier)
            .set(photos, PhotoBrowseSource.favorites);
        context.push('/photos/${photo.id}');
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 118,
          height: 118,
          child: PortalMediaThumbnail(
            imageUrl: photo.coverUrl ?? '',
            cacheKey: photo.coverCacheKey,
            cacheHeight: 280,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.zero,
            fallback: ColoredBox(
              color: scheme.surfaceContainerHigh,
              child: Icon(
                Icons.favorite_outline,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 由继续观看条目计算「剩余分钟」描述文本。
String libraryContinueDetail(
  AppLocalizations l10n,
  MovieContinueWatching item,
) {
  final duration = item.durationSeconds;
  final position = item.positionSeconds;
  if (duration > 0 && position >= 0 && duration > position) {
    final minutes = ((duration - position) / 60).round();
    if (minutes > 0) {
      return l10n.libraryMinutesLeft(minutes);
    }
  }
  final percent = item.progressPercent.round();
  if (percent > 0) {
    return '$percent%';
  }
  return '';
}
