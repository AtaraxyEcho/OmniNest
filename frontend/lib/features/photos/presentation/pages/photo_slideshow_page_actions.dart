part of 'photo_slideshow_page.dart';

/// 幻灯片内的写操作：收藏切换与原片下载。

/// 两者都只依赖当前照片与能力判定，不参与动画与预加载的状态机，
/// 因此从页面主体拆出。
extension _PhotoSlideshowPageActions on _PhotoSlideshowPageState {
  Future<void> _toggleFavorite(PhotoItem photo) async {
    // 无 activity:write 的角色：按钮保留但点击明确提示无权限。
    if (!ref.read(userCapabilitiesProvider).canManageOwnActivity) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(context).errorForbidden,
        severity: OmniFeedbackSeverity.error,
      );
      return;
    }
    final wasFavorite = photo.favorite;
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .toggleFavorite(photo.id, currentFavorite: photo.favorite);
      if (!mounted) return;
      showOmniFeedback(
        context,
        wasFavorite
            ? AppLocalizations.of(context).favoriteRemoved
            : AppLocalizations.of(context).favoriteAdded,
        severity: OmniFeedbackSeverity.success,
      );
      ref.invalidate(photoDetailProvider(photo.id));
    } on Exception {
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(context).photosOperationFailed,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  Future<void> _downloadPhoto(PhotoItem photo) async {
    final sourceUrl = photo.sourceUrl;
    if (sourceUrl == null || sourceUrl.isEmpty) return;
    try {
      if (kIsWeb) {
        // 与详情页同口径：等浏览器下载真的发起再反馈，
        // unawaited 会让外层 catch 看不见拒绝，用户点了没动静。
        await downloadPhotoBatchInBrowser(
          url: sourceUrl,
          fileName: photo.downloadFileName,
        );
        if (!mounted) {
          return;
        }
        showOmniFeedback(
          context,
          AppLocalizations.of(context).photosDownloadStarted,
          severity: OmniFeedbackSeverity.success,
        );
        return;
      }
      final exportResult = await ref
          .read(photoCenterControllerProvider.notifier)
          .savePhotoFileToDisk(
            url: sourceUrl,
            sizeBytes: photo.fileSize,
            suggestedName: photo.downloadFileName,
          );
      if (!mounted || exportResult is PhotoExportCancelled) return;
      final l10n = AppLocalizations.of(context);
      final message = switch (exportResult) {
        PhotoExportSaved(:final path) => l10n.photosDownloadSaved(path),
        PhotoExportShared() => l10n.photosExportShared,
        PhotoExportCancelled() => null,
      };
      if (message != null) {
        showOmniFeedback(context, message);
      }
    } on Exception {
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(context).photosDownloadFailed,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }
}
