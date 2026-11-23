part of 'desktop_photos_page.dart';

/// 单张照片快捷操作（右键菜单及检查器复用）：收藏切换、单张导出与移入回收站。
extension _DesktopPhotosSingleActions on _DesktopPhotosPageState {
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
}
