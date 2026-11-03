part of 'photo_detail_page.dart';

/// 观看器动作：下载原片、连播、关闭、删除、加入相册与收藏。
///
/// 这些流程只按当前页读状态，不参与 build 的响应式订阅，因此从页面主体拆出，
/// 避免下载与删除的分支继续把主文件堆成千行。
extension _PhotoDetailViewerActions on _PhotoDetailBodyState {
  // ─── 下载原片 ───

  Future<void> _downloadPhoto() async {
    final l10n = AppLocalizations.of(context);
    final photoId = _current.id;
    // 下载必须使用详情接口新签发的 sourceUrl：列表种子无 sourceUrl，
    // 内存缓存与会话内旧详情都可能持有已过期的预签名地址。
    final PhotoItem photo;
    try {
      ref.invalidate(photoDetailProvider(photoId));
      photo = await ref.read(photoDetailProvider(photoId).future);
    } on Exception {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.photosDownloadFailed,
        severity: OmniFeedbackSeverity.error,
      );
      return;
    }
    if (!mounted) return;
    final sourceUrl = photo.sourceUrl;
    if (sourceUrl == null || sourceUrl.isEmpty) {
      showOmniFeedback(context, l10n.photosDownloadSourceUnavailable);
      return;
    }
    final fileName = photo.downloadFileName;
    try {
      if (kIsWeb) {
        await downloadPhotoBatchInBrowser(url: sourceUrl, fileName: fileName);
        if (!mounted) {
          return;
        }
        showOmniFeedback(
          context,
          l10n.photosDownloadStarted,
          severity: OmniFeedbackSeverity.success,
        );
        return;
      }
      final exportResult = await ref
          .read(photoCenterControllerProvider.notifier)
          .savePhotoFileToDisk(
            url: sourceUrl,
            sizeBytes: photo.fileSize,
            suggestedName: fileName,
          );
      if (!mounted || exportResult is PhotoExportCancelled) return;
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
        l10n.photosDownloadFailed,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  /// 启动沉浸幻灯片页；关闭后按回传结果恢复查看器位置。
  Future<void> _launchSlideshow() async {
    final scope = ref.read(photoBrowseScopeProvider);
    final startIndex = _currentPage.clamp(
      0,
      _pages.isEmpty ? 0 : _pages.length - 1,
    );
    final startPhoto = _pages.isEmpty ? _current : _pages[startIndex];
    final result = await context.push<Object>(
      '/photos/slideshow',
      extra: {
        'photos': _pages,
        'initialIndex': startIndex,
        'initialPhotoId': startPhoto.id,
        'source': scope.source,
        'sourceKey': scope.sourceKey,
      },
    );
    if (!mounted || result is! Map) return;
    final restored = result['photoId'];
    if (restored is String && restored.isNotEmpty) {
      _updateState(() => _currentPhotoId = restored);
    }
  }

  /// 关闭查看器，返回照片列表。
  void _closeViewer() {
    context.popOrGo('/photos');
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFrameConfirmDialog(
      context,
      title: l10n.photosMoveToTrashTitle,
      body: l10n.photosMoveToTrashBodyOne,
      confirmLabel: l10n.photosMoveToTrashAction,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .movePhotoToTrash(_current.id);
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.photosTrashMoved,
        severity: OmniFeedbackSeverity.success,
      );
      _closeViewer();
    } on Exception {
      if (!mounted) return;
      showOmniFeedback(
        context,
        AppLocalizations.of(context).photosDeleteFailed,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  Future<void> _showAddToAlbumDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final albums =
        await ref.read(photoCenterControllerProvider.notifier).listAlbums();
    if (!context.mounted) return;

    final selected = await showFrameChoiceDialog<String>(
      context,
      title: AppLocalizations.of(context).photosSelectAlbum,
      choices: [
        for (final album in albums)
          FrameChoice(
            value: album.id,
            title: album.name,
            subtitle: AppLocalizations.of(
              context,
            ).photosAlbumPhotoCountLabel(album.photoCount),
          ),
      ],
      emptyMessage: AppLocalizations.of(context).photosNoAlbumsCreateFirst,
    );

    if (selected != null && context.mounted) {
      try {
        await ref
            .read(photoCenterControllerProvider.notifier)
            .addPhotosToAlbum(albumId: selected, photoIds: [_current.id]);
        if (context.mounted) {
          showOmniFeedback(
            context,
            AppLocalizations.of(context).photosAddedToAlbum,
            severity: OmniFeedbackSeverity.success,
          );
        }
      } on Exception {
        if (context.mounted) {
          showOmniFeedback(
            context,
            AppLocalizations.of(context).photosAddFailed,
            severity: OmniFeedbackSeverity.error,
          );
        }
      }
    }
  }

  /// 查看器收藏切换（头部与紧凑底部动作行共用）。
  Future<void> _toggleViewerFavorite(PhotoItem photo) async {
    // 无 activity:write 的角色：按钮保留但点击明确提示无权限。
    if (!ref.read(userCapabilitiesProvider).canManageOwnActivity) {
      if (mounted) {
        showOmniFeedback(
          context,
          AppLocalizations.of(context).errorForbidden,
          severity: OmniFeedbackSeverity.error,
        );
      }
      return;
    }
    try {
      final wasFavorite = photo.favorite;
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
      if (mounted) {
        showOmniFeedback(
          context,
          AppLocalizations.of(context).photosOperationFailed,
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }
}
