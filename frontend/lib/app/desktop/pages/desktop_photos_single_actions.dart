part of 'desktop_photos_page.dart';

/// 单张照片上下文菜单、收藏、下载与删除动作（从 desktop_photos_page.dart 拆出）。
extension _DesktopPhotosSingleActions on _DesktopPhotosPageState {
  void _openPhotoContextMenu(
    PhotoItem photo,
    List<PhotoItem> photos,
    Offset globalPosition, {
    required PhotoBrowseSource source,
  }) {
    final l10n = AppLocalizations.of(context);
    final isSelected = _selection.contains(photo.id);
    ref.read(desktopShellProvider.notifier).openMenu(globalPosition, [
      DesktopMenuItem(
        label: l10n.filesOpen,
        icon: DesktopIcons.image,
        onPressed: () => _openPhoto(photo, photos, source),
      ),
      DesktopMenuItem(
        label:
            Localizations.localeOf(context).languageCode == 'zh'
                ? '检查信息'
                : l10n.desktopOpenDetails,
        icon: DesktopIcons.info,
        onPressed: () => _inspectPhoto(photo, photos, source: source),
      ),
      DesktopMenuItem(
        label:
            isSelected
                ? l10n.desktopPhotosClearSelection
                : l10n.desktopPhotosSelect,
        icon: DesktopIcons.check,
        onPressed: () => _toggleSelect(photo),
      ),
      const DesktopMenuItem.separator(),
      DesktopMenuItem(
        label: photo.favorite ? l10n.photosUnfavorite : l10n.photosFavorite,
        icon: DesktopIcons.heart,
        onPressed: () => unawaited(_toggleSingleFavorite(photo)),
      ),
      DesktopMenuItem(
        label: l10n.photosAddToAlbum,
        icon: DesktopIcons.album,
        onPressed: () {
          if (!_selection.contains(photo.id)) {
            _update(() {
              _selection
                ..clear()
                ..add(photo.id);
            });
          }
          unawaited(_addSelectedToAlbum(_update));
        },
      ),
      DesktopMenuItem(
        label: l10n.photosDownload,
        icon: DesktopIcons.download,
        onPressed: () => unawaited(_downloadSinglePhoto(photo)),
      ),
      const DesktopMenuItem.separator(),
      DesktopMenuItem(
        label: l10n.photosDelete,
        icon: DesktopIcons.trash,
        danger: true,
        onPressed: () => unawaited(_deleteSinglePhoto(photo)),
      ),
    ]);
  }

  Future<void> _toggleSingleFavorite(PhotoItem photo) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .toggleFavorite(photo.id, currentFavorite: photo.favorite);
      if (!mounted) return;
      showDesktopToast(
        context,
        photo.favorite ? l10n.photosUnfavorite : l10n.desktopPhotosFavorited(1),
        icon: DesktopIcons.heart,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.photosFavorite, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _downloadSinglePhoto(PhotoItem photo) async {
    final l10n = AppLocalizations.of(context);
    final url = photo.sourceUrl;
    if (url == null || url.isEmpty) {
      showDesktopToast(
        context,
        l10n.photosDownloadNeedsOriginal,
        kind: DesktopToastKind.warn,
        icon: DesktopIcons.download,
      );
      return;
    }
    try {
      final ext = photo.format.isEmpty ? 'jpg' : photo.format.toLowerCase();
      final name = '${photo.title}.$ext';
      final path = await resolvePhotoExportPath(suggestedName: name);
      if (path == null || !mounted) return;
      await ref
          .read(photoRepositoryProvider)
          .downloadPhotoFile(
            url: url,
            sizeBytes: photo.fileSize,
            destinationPath: path,
          );
      await deliverPhotoExport(path: path, fileName: name);
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.photosSavedCount(1),
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          userFacingErrorText(error),
          kind: DesktopToastKind.error,
        );
      }
    }
  }

  Future<void> _deleteSinglePhoto(PhotoItem photo) async {
    final l10n = AppLocalizations.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final ids = <String>[photo.id];
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .movePhotosToTrash(ids);
      if (!mounted) return;
      _update(() => _selection.remove(photo.id));
      showDesktopToast(
        context,
        l10n.desktopPhotosMovedToTrash(1),
        icon: DesktopIcons.trash,
        actionLabel: l10n.desktopUndo,
        onAction:
            () => unawaited(_restoreSelectedFromTrash(container, ids, l10n)),
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.photosDelete, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  void _openPhoto(
    PhotoItem photo,
    List<PhotoItem> photos,
    PhotoBrowseSource source,
  ) {
    ref.read(desktopAmbientHintProvider.notifier).rememberPhotoId(photo.id);
    ref.read(photoBrowseScopeProvider.notifier).set(photos, source);
    desktopPush(context, DesktopRoutes.photoDetail(photo.id));
  }

  /// 供拆分出的动作扩展调用的状态刷新出口。
}
