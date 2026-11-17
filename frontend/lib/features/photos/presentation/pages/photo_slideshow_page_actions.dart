part of 'photo_slideshow_page.dart';

/// 幻灯片的用户动作面：切歌式导航、手势滑动、播放/暂停、chrome 显隐与全屏切换，
/// 以及收藏切换与原片下载。
///
/// 这些成员只读当前照片与能力判定、写的是交互态，不参与动画与预加载的状态机，
/// 因此从页面主体拆出；状态更新统一走 `_updateState`。
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
    } on Exception catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        failureToast(
          AppLocalizations.of(context),
          AppLocalizations.of(context).photosOperationFailed,
          error,
        ),
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
    } on Exception catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        failureToast(
          AppLocalizations.of(context),
          AppLocalizations.of(context).photosDownloadFailed,
          error,
        ),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  void _goNext() => unawaited(_goTo(_current + 1));

  void _goPrev() => unawaited(_goTo(_current - 1));

  /// 横向滑动切换：负速度为左滑（下一张），正速度为右滑（上一张）。
  void _onHorizontalDragEnd(DragEndDetails details) {
    _resetIdle();
    if (_photos.length < 2) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 280) return;
    if (velocity < 0) {
      _goNext();
    } else {
      _goPrev();
    }
  }

  void _togglePlay() {
    _updateState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        if (_presentationVisible.isCompleted) {
          _progressController.forward(from: 0);
        }
      } else {
        _progressController.reset();
        _idleTimer?.cancel();
      }
      _controlsVisible = true;
    });
    if (_isPlaying) {
      _scheduleIdleHide();
    }
  }

  void _resetIdle() {
    if (!mounted) return;
    // MouseRegion.onHover fires on every pointer move (Web/desktop). Only
    // rebuild when chrome was hidden; always setState would repaint the
    // whole page and stall the segmented progress bar.
    if (!_controlsVisible) {
      _updateState(() => _controlsVisible = true);
    }
    _scheduleIdleHide();
  }

  /// Toggle chrome on canvas tap: hide when shown, show + resume idle timer when hidden.
  ///
  /// Allowed while paused so the user can stay immersive; tap again to restore.
  void _toggleControls() {
    if (!mounted) return;
    _idleTimer?.cancel();
    if (_controlsVisible) {
      _updateState(() => _controlsVisible = false);
      return;
    }
    _resetIdle();
  }

  void _scheduleIdleHide() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleHideDuration, () {
      if (!mounted) return;
      if (_isPlaying) _updateState(() => _controlsVisible = false);
    });
  }

  void _toggleFullscreen() {
    if (kIsWeb) {
      fs.toggleFullscreen();
      return;
    }
    ref.read(windowChromeControllerProvider.notifier).toggleFullscreen();
  }
}
