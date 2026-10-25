part of 'portal_mobile_shell.dart';

/// 最近动态标题行：eyebrow + 「进入媒体库」文字动作。
class _SpatialRecentHeading extends StatelessWidget {
  const _SpatialRecentHeading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.spatialRecentlyEyebrow.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.env.eyebrowInk,
              fontSize: AppTypography.labelMicro,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.65,
              height: 1.45,
            ),
          ),
        ),
        TextButton(
          onPressed: () => context.go('/library'),
          style: TextButton.styleFrom(
            foregroundColor: context.env.white70,
            minimumSize: const Size(48, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(fontSize: AppTypography.labelSmall),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.spatialViewLibrary),
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

/// 最近动态条：照片 / 阅读 / 文件三张紧凑卡。
///
/// 手机与平板档沿用样例 `1.4fr : 1fr : 1fr`；≥980 双栏档按原型
/// `.recent-strip{repeat(3,1fr)}` 等分三列并抬高瓦片。
class _SpatialRecentStrip extends ConsumerWidget {
  const _SpatialRecentStrip({required this.tier});

  final PortalMobileTier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final photos = ref.watch(portalPhotoDashboardProvider).asData?.value;
    final reader = ref.watch(portalReaderDashboardProvider).asData?.value;
    final recentFiles = ref.watch(fileRecentEntriesProvider).asData?.value;
    final recentPhoto = photos?.recentPhotos.firstOrNull;
    final readingItem =
        reader?.continueReading.firstOrNull ?? reader?.recentItems.firstOrNull;
    final fileNode = recentFiles?.firstOrNull;

    final tiles = <Widget>[
      _SpatialRecentTile(
        label: l10n.spatialRecentPhotos,
        photo: recentPhoto,
        height: tier.recentTileHeight,
        photoSub: l10n.libraryBannerPhotoCount(
          photos?.recentPhotos.length ?? 0,
        ),
        onTap: () {
          final list = photos?.recentPhotos ?? const <PhotoItem>[];
          if (list.isEmpty) {
            context.push('/photos');
            return;
          }
          ref
              .read(photoBrowseScopeProvider.notifier)
              .set(list, PhotoBrowseSource.library);
          context.push('/photos/${list.first.id}');
        },
      ),
      _SpatialRecentTile(
        label: l10n.mobileNavReader,
        readerItem: readingItem,
        height: tier.recentTileHeight,
        onTap:
            readingItem == null
                ? () => context.go('/reader')
                : () => context.push('/reader/items/${readingItem.id}'),
      ),
      _SpatialRecentTile(
        label: l10n.spatialRecentFiles,
        fileNode: fileNode,
        height: tier.recentTileHeight,
        onTap: () => context.go('/files'),
      ),
    ];
    final photoFlex = tier.twoColumnHome ? 1 : 14;
    final otherFlex = tier.twoColumnHome ? 1 : 10;
    return Row(
      children: [
        for (var index = 0; index < tiles.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(
            flex: index == 0 ? photoFlex : otherFlex,
            child: tiles[index],
          ),
        ],
      ],
    );
  }
}

class _SpatialRecentTile extends StatelessWidget {
  const _SpatialRecentTile({
    required this.label,
    required this.height,
    required this.onTap,
    this.photo,
    this.photoSub,
    this.readerItem,
    this.fileNode,
  });

  final String label;

  /// 瓦片高度（样例 136，≥980 双栏档 150）。
  final double height;
  final PhotoItem? photo;

  /// 照片卡副文案（如新增张数）。
  final String? photoSub;
  final ReaderItem? readerItem;
  final FileNode? fileNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    String title = label;
    String? subtitle;
    Widget? visual;
    if (photo != null) {
      title = photo!.title;
      subtitle = photoSub;
    } else if (readerItem != null) {
      title = readerItem!.title;
      visual = _BookMini(title: readerItem!.title);
      final fraction = readerItem!.progressPercent;
      final percent = fraction == null ? null : (fraction * 100).round();
      final chapter = readerItem!.currentChapterTitle;
      subtitle = [
        if (chapter?.isNotEmpty == true) chapter,
        if (percent != null && percent > 0) '$percent%',
      ].join(' · ');
    } else if (fileNode != null) {
      title = fileNode!.name;
      visual = Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: context.env.folderGlyphBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: OmniIcon(
            icon: OmniIcons.folder,
            size: 24,
            color: context.env.folderGlyph,
          ),
        ),
      );
      final updated = fileNode!.updatedAt;
      if (updated != null) {
        subtitle = localizations.formatShortDate(updated);
      }
    }
    Widget? image;
    if (photo != null) {
      image = PortalMediaThumbnail(
        imageUrl: photo!.coverUrl ?? '',
        cacheKey: photo!.coverCacheKey,
        cacheHeight: 320,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.zero,
        fallback: const SizedBox.shrink(),
      );
    } else if (readerItem != null && readerItem!.hasCover) {
      image = AuthCoverImage(
        itemId: readerItem!.id,
        fit: BoxFit.cover,
        fallback: const SizedBox.shrink(),
      );
    }
    return MobilePressable(
      semanticLabel: label,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.env.surfaceRaised,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: context.env.line10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image != null)
                  Positioned.fill(child: image)
                else
                  Positioned.fill(
                    child: ColoredBox(color: context.env.surfaceTint),
                  ),
                if (image != null)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.05),
                            Colors.black.withValues(alpha: 0.78),
                          ],
                          stops: const [0.35, 1],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (visual != null) visual,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: photo != null ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.env.ink,
                              fontSize: AppTypography.bodySmall,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          if (subtitle != null && subtitle.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.env.inkMuted,
                                fontSize: AppTypography.labelMicro,
                              ),
                            ),
                          ],
                        ],
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
}

/// 书脊小卡：衬线首字母 + 左侧书脊描边（原型 book-mini）。
class _BookMini extends StatelessWidget {
  const _BookMini({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final letter =
        title.isNotEmpty ? title.characters.first.toUpperCase() : '?';
    return Container(
      width: 35,
      height: 48,
      decoration: BoxDecoration(
        color: context.env.bookMiniBg,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(2),
          right: Radius.circular(7),
        ),
        boxShadow: [
          BoxShadow(color: context.env.bookMiniSpine, offset: Offset(-3, 0)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: context.env.bookMiniFg,
          fontFamily: AppTypography.serifFamily,
          fontFamilyFallback: AppTypography.serifFamilyFallback,
          fontSize: AppTypography.titleLarge,
          height: 1,
        ),
      ),
    );
  }
}

/// 高频动作行：查找任何内容 / 添加媒体。
///
/// ≥980 双栏档按原型 `.quick-line{max-width:420}` 收成左对齐窄条，
/// 避免两枚按钮在跨列下摊满整幅。
class _SpatialQuickLine extends StatelessWidget {
  const _SpatialQuickLine({required this.tier});

  final PortalMobileTier tier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget action(OmniIconsData icon, String label, VoidCallback onTap) {
      return Expanded(
        child: MobilePressable(
          semanticLabel: label,
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.env.surfaceGlass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.env.line09),
                ),
                child: SizedBox(
                  height: MobileLayoutTokens.minimumTarget,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OmniIcon(icon: icon, size: 18, color: context.env.ink),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.env.ink,
                            fontSize: AppTypography.labelSmall,
                            fontWeight: FontWeight.w600,
                          ),
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

    final row = Row(
      children: [
        action(OmniIcons.search, l10n.spatialActionFind, () {
          context.push('/search');
        }),
        const SizedBox(width: 9),
        action(OmniIcons.plus, l10n.spatialActionAddMedia, () {
          context.go('/files');
        }),
      ],
    );
    final maxWidth = tier.quickLineMaxWidth;
    if (maxWidth == null) {
      return row;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: row,
      ),
    );
  }
}
