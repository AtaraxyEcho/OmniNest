part of 'desktop_photo_viewer_page.dart';

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.alignment,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Alignment alignment;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        // 样例 `.vw-nav`：52×52 圆钮、图标 26、左右各 20 边距。
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: DesktopIconButton(
          icon: icon,
          size: 52,
          iconSize: 26,
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// 将查看器舞台状态同步给跨 Navigator 过渡注册表，用于退出时缩回当前照片卡片。
extension _ViewerTransitionSync on _DesktopPhotoViewerPageState {
  void _syncTransitionStage(PhotoItem? photo) {
    if (photo == null) {
      DesktopPhotoTransitionRegistry.instance.clearViewerStage(this);
      return;
    }
    final width = photo.width;
    final height = photo.height;
    final ratio =
        (width != null && height != null && width > 0 && height > 0)
            ? width / height
            : null;
    DesktopPhotoTransitionRegistry.instance.updateViewerStage(
      this,
      DesktopPhotoViewerStageSnapshot(
        photoId: photo.id,
        coverUrl: photo.coverUrl,
        aspectRatio: ratio,
        infoOpen: _info,
        canFlyBack: _scale <= 1.05 && (_rotation % 360 == 0) && !_slideshow,
        imageKey: _stageImageKey,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.photo,
    required this.index,
    required this.total,
    required this.info,
    required this.slideshow,
    required this.visible,
    required this.favorite,
    required this.onClose,
    required this.onToggleInfo,
    required this.onToggleSlideshow,
    required this.onRotate,
    required this.onToggleFavorite,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  final PhotoItem photo;
  final int index;
  final int total;
  final bool info;
  final bool slideshow;
  final bool visible;
  final bool favorite;
  final VoidCallback onClose;
  final VoidCallback onToggleInfo;
  final VoidCallback onToggleSlideshow;
  final VoidCallback onRotate;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: DesktopMotion.of(context, DesktopMotion.viewerChrome),
          alwaysIncludeSemantics: true,
          child: SizedBox(
            height: 64,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DesktopWindowDragRegion(child: SizedBox.expand()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      DesktopIconButton(
                        icon: DesktopIcons.left,
                        size: 36,
                        iconSize: 18,
                        tooltip: l10n.photosClose,
                        onPressed: onClose,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: IgnorePointer(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _placeLabel(photo) ?? photo.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.cardTitle(skin.text),
                              ),
                              Text(
                                l10n.desktopPhotosIndex(index + 1, total),
                                style: DesktopType.caption(skin.text3),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DesktopIconButton(
                        icon:
                            slideshow ? DesktopIcons.pause : DesktopIcons.play,
                        size: 36,
                        iconSize: 17,
                        active: slideshow,
                        tooltip: l10n.photosSlideshow,
                        onPressed: onToggleSlideshow,
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.rotate,
                        size: 36,
                        iconSize: 18,
                        tooltip: l10n.photosRotate,
                        onPressed: onRotate,
                      ),
                      DesktopIconButton(
                        icon:
                            favorite
                                ? DesktopIcons.heartFilled
                                : DesktopIcons.heart,
                        size: 36,
                        iconSize: 18,
                        tooltip: l10n.photosFavorite,
                        onPressed: onToggleFavorite,
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.edit,
                        size: 36,
                        iconSize: 17,
                        tooltip: l10n.photosEdit,
                        onPressed: onEdit,
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.share,
                        size: 36,
                        iconSize: 17,
                        tooltip: l10n.filesShare,
                        onPressed: onShare,
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.trash,
                        size: 36,
                        iconSize: 17,
                        tooltip: l10n.photosDelete,
                        onPressed: onDelete,
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.info,
                        size: 36,
                        iconSize: 18,
                        active: info,
                        tooltip: l10n.desktopPhotosInfo,
                        onPressed: onToggleInfo,
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
