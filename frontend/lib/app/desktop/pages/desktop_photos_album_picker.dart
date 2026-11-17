part of 'desktop_photos_page.dart';

/// 桌面 Photos 批量加入相册的抽屉与创建后接续流程。
extension _PhotoAlbumPickerActions on _DesktopPhotosPageState {
  Future<void> _addSelectedToAlbum(void Function(VoidCallback) setState) async {
    final l10n = AppLocalizations.of(context);
    final albums =
        ref.read(photoAlbumsProvider).asData?.value ?? const <PhotoAlbum>[];
    final photoIds = _selection.toList(growable: false);
    if (photoIds.isEmpty) return;

    // 样例点 Album 后先收起选中栏；取消抽屉也保持清空状态。
    setState(_selection.clear);
    final choice = await showDesktopDrawer<({String? albumId, bool createNew})>(
      context,
      width: 420,
      builder:
          (_) => _SelectedPhotoAlbumDrawer(
            photoCount: photoIds.length,
            albums: albums,
          ),
    );
    if (choice == null || !mounted) return;

    var createdAlbum = false;
    PhotoAlbum? newAlbum;
    setState(() => _selectionBusy = true);
    try {
      var albumId = choice.albumId;
      if (choice.createNew) {
        final takenNames = albums.map((album) => album.name).toList();
        final name = await showDesktopDrawer<String>(
          context,
          width: 420,
          builder: (_) => _NewAlbumDrawer(takenNames: takenNames),
        );
        if (name == null || !mounted) return;
        newAlbum = await ref
            .read(photoCenterControllerProvider.notifier)
            .createAlbum(name: name);
        if (!mounted) return;
        createdAlbum = true;
        albumId = newAlbum.id;
      }

      await ref
          .read(photoRepositoryProvider)
          .addPhotosToAlbum(albumId: albumId!, photoIds: photoIds);
      if (!mounted) return;
      ref.invalidate(photoAlbumsProvider);
      showDesktopToast(
        context,
        newAlbum == null
            ? l10n.photosAddedToAlbum
            : l10n.desktopPhotosAlbumCreatedWithPhotos(
              newAlbum.name,
              photoIds.length,
            ),
        icon: createdAlbum ? DesktopIcons.plus : DesktopIcons.check,
      );
    } on Object catch (error) {
      if (!mounted) return;
      if (createdAlbum) {
        ref.invalidate(photoAlbumsProvider);
      }
      showDesktopToast(
        context,
        userFacingErrorText(error),
        kind: DesktopToastKind.error,
      );
    } finally {
      if (mounted) {
        setState(() => _selectionBusy = false);
      }
    }
  }
}

class _SelectedPhotoAlbumDrawer extends StatelessWidget {
  const _SelectedPhotoAlbumDrawer({
    required this.photoCount,
    required this.albums,
  });

  final int photoCount;
  final List<PhotoAlbum> albums;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopDrawerFrame(
      eyebrow: l10n.photosAlbumPhotoCountLabel(photoCount),
      title: l10n.photosAddToAlbum,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: albums.length + 1,
        separatorBuilder: (_, _) => Divider(height: 1, color: skin.line),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _PhotoAlbumPickerTile(
              title: l10n.photosNewAlbum,
              icon: DesktopIcons.plus,
              onTap:
                  () => closeDesktopModal(context, (
                    albumId: null,
                    createNew: true,
                  )),
            );
          }
          final album = albums[index - 1];
          return _PhotoAlbumPickerTile(
            title: album.name,
            subtitle: l10n.desktopItemCount(album.photoCount),
            album: album,
            onTap:
                () => closeDesktopModal(context, (
                  albumId: album.id,
                  createNew: false,
                )),
          );
        },
      ),
    );
  }
}

class _PhotoAlbumPickerTile extends StatelessWidget {
  const _PhotoAlbumPickerTile({
    required this.title,
    required this.onTap,
    this.icon,
    this.subtitle,
    this.album,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final PhotoAlbum? album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              decoration: BoxDecoration(
                color: hovered ? skin.raise : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child:
                          album == null
                              ? ColoredBox(
                                color: skin.raise2,
                                child: Icon(icon, size: 18, color: skin.accent),
                              )
                              : DesktopCover(
                                url: album!.coverUrl,
                                kind: DesktopCoverKind.network,
                                fallbackIcon: DesktopIcons.album,
                                cacheKey: 'photo-album-picker-${album!.id}',
                              ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.denseStrong(skin.text),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: DesktopType.caption(skin.text3),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
