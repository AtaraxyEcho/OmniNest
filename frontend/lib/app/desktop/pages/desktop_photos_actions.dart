part of 'desktop_photos_page.dart';

/// 照片页的排序、相册与批量选择动作（与页面 state 共用同一批字段）。
extension _DesktopPhotosActions on _DesktopPhotosPageState {
  Future<void> _savePhotoOrder(
    String contextKey,
    List<String> ids,
    int movedCount,
  ) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(photoDisplayOrderProvider.notifier)
          .saveOrder(contextKey, ids);
      if (!mounted) return;
      showDesktopToast(
        context,
        movedCount > 1
            ? l10n.desktopPhotosMovedCount(movedCount)
            : l10n.desktopPhotosOrderSaved,
        icon: DesktopIcons.check,
      );
    } on Object {
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.desktopPhotosOrderSaveFailed,
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

  Future<void> _resetPhotoOrder(String contextKey) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(photoDisplayOrderProvider.notifier).resetOrder(contextKey);
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.desktopPhotosOrderReset,
        icon: DesktopIcons.check,
      );
    } on Object {
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.desktopPhotosOrderSaveFailed,
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

  void _openAlbum(PhotoAlbum album) {
    _update(() {
      _tab = DesktopPhotosTab.albums;
      _selectedAlbumId = album.id;
      _selection.clear();
      _selectionMode = false;
      _lastSelectedPhotoId = null;
    });
  }

  void _openAlbumPhoto(PhotoItem photo, List<PhotoItem> photos) {
    ref.read(desktopAmbientHintProvider.notifier).rememberPhotoId(photo.id);
    ref
        .read(photoBrowseScopeProvider.notifier)
        .set(photos, PhotoBrowseSource.album, sourceKey: _selectedAlbumId);
    desktopPush(context, DesktopRoutes.photoDetail(photo.id));
  }

  Future<void> _shareAlbum(PhotoAlbum album) async {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(photoCenterControllerProvider.notifier);
    late final List<PhotoShareLink> shares;
    try {
      shares = await controller.listAlbumShares(album.id);
    } on Object catch (error) {
      if (!mounted) return;
      showDesktopToast(
        context,
        failureToast(l10n, l10n.photosShareAlbum, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
      return;
    }
    if (!mounted) return;
    final result = await showPhotoShareDialog(
      context,
      title: l10n.photosShareAlbum,
      shares: shares,
      onRevoke: controller.revokeAlbumShare,
      onRevokeAll: () => controller.revokeAllAlbumShares(album.id),
      shareUrlOf: (share) async {
        final baseUrl =
            await ref.read(webShareBaseUrlResolverProvider).resolve();
        return '$baseUrl/#/shared/photos/${share.token}';
      },
    );
    if (!mounted || result == null) return;
    try {
      final link = await controller.createAlbumShare(
        album.id,
        password: result.$1.isEmpty ? null : result.$1,
        expiresAt: resolveShareExpiry(result.$2),
      );
      if (!mounted) return;
      final baseUrl = await ref.read(webShareBaseUrlResolverProvider).resolve();
      if (!mounted) return;
      final copied = await copyTextToClipboard(
        '$baseUrl/#/shared/photos/${link.token}',
      );
      if (!mounted) return;
      showDesktopToast(
        context,
        copied
            ? l10n.filesCopiedClipboard
            : l10n.photosShareLinkCreated(
              '$baseUrl/#/shared/photos/${link.token}',
            ),
        icon: DesktopIcons.share,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.photosShareLinkFailed, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _deleteAlbum(PhotoAlbum album) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDesktopDialog<bool>(
      context,
      builder:
          (dialogContext) => DesktopDialog(
            width: 440,
            eyebrow: l10n.photosTabAlbums,
            title: l10n.photosDeleteAlbumTitle,
            content: Text(
              l10n.photosDeleteAlbumConfirm(album.name),
              style: DesktopType.dense(DesktopSkin.of(context).text2),
            ),
            actions: [
              DesktopButton(
                label: l10n.photosClose,
                onPressed: () => closeDesktopModal(dialogContext, false),
              ),
              DesktopButton(
                label: l10n.photosDelete,
                icon: DesktopIcons.trash,
                variant: DesktopButtonVariant.danger,
                onPressed: () => closeDesktopModal(dialogContext, true),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .deleteAlbum(album.id);
      if (!mounted) return;
      _update(() => _selectedAlbumId = null);
      showDesktopToast(
        context,
        l10n.photosDeletedAlbum(album.name),
        icon: DesktopIcons.trash,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.photosDeleteAlbumTitle, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _createAlbum() async {
    final l10n = AppLocalizations.of(context);
    final takenNames =
        ref
            .read(photoAlbumsProvider)
            .asData
            ?.value
            .map((album) => album.name)
            .toList(growable: false) ??
        const <String>[];
    final name = await showDesktopDrawer<String>(
      context,
      width: 420,
      builder: (_) => _NewAlbumDrawer(takenNames: takenNames),
    );
    if (name == null || !mounted) {
      return;
    }
    try {
      final album = await ref
          .read(photoCenterControllerProvider.notifier)
          .createAlbum(name: name);
      if (mounted) {
        showDesktopToast(
          context,
          l10n.photosAlbumCreated(album.name),
          icon: DesktopIcons.plus,
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.photosNewAlbum, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  /// 样例 `Photos.tsx:65`：支持 Shift 连选、Ctrl/Cmd 加选、多选模式下点击切换选中，
  /// 否则打开大图。
  void _activatePhoto(
    PhotoItem photo,
    List<PhotoItem> photos, {
    required PhotoBrowseSource source,
  }) {
    final hardware = HardwareKeyboard.instance;
    if (hardware.isShiftPressed && _lastSelectedPhotoId != null) {
      final anchorIndex = photos.indexWhere(
        (item) => item.id == _lastSelectedPhotoId,
      );
      final targetIndex = photos.indexWhere((item) => item.id == photo.id);
      if (anchorIndex >= 0 && targetIndex >= 0) {
        final start = math.min(anchorIndex, targetIndex);
        final end = math.max(anchorIndex, targetIndex);
        _update(() {
          for (var i = start; i <= end; i++) {
            _selection.add(photos[i].id);
          }
          _lastSelectedPhotoId = photo.id;
        });
        _syncPhotoSelectionDetail();
        return;
      }
    }
    final additive =
        _selectionMode ||
        _selection.isNotEmpty ||
        hardware.isControlPressed ||
        hardware.isMetaPressed;
    if (additive) {
      _toggleSelect(photo);
      return;
    }
    _openPhoto(photo, photos, source);
  }

  void _toggleSelect(PhotoItem photo) {
    _update(() {
      if (!_selection.remove(photo.id)) {
        _selection.add(photo.id);
      }
      _lastSelectedPhotoId = photo.id;
    });
    _syncPhotoSelectionDetail();
  }

  Future<void> _favoriteSelected() async {
    final l10n = AppLocalizations.of(context);
    final ids = _selection.toList(growable: false);
    // `toggleFavorite` 要真实当前值，否则会把「已在收藏」误判成收藏。
    final visible = <String, PhotoItem>{
      for (final photo
          in ref.read(photoFavoritesProvider).asData?.value.items ??
              const <PhotoItem>[])
        photo.id: photo,
      for (final photo
          in ref.read(photoListProvider).asData?.value.items ??
              const <PhotoItem>[])
        photo.id: photo,
    };
    final pending = ids
        .map((id) => visible[id])
        .whereType<PhotoItem>()
        .where((photo) => !photo.favorite)
        .toList(growable: false);
    if (pending.isEmpty) {
      _update(() {
        _selection.clear();
        _selectionMode = false;
      });
      return;
    }
    _update(() => _selectionBusy = true);
    try {
      final controller = ref.read(photoCenterControllerProvider.notifier);
      for (final photo in pending) {
        await controller.toggleFavorite(photo.id, currentFavorite: false);
      }
      if (!mounted) {
        return;
      }
      _update(() {
        _selection.clear();
        _selectionMode = false;
      });
      showDesktopToast(
        context,
        l10n.desktopPhotosFavorited(pending.length),
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
    } finally {
      if (mounted) {
        _update(() => _selectionBusy = false);
      }
    }
  }

  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final ids = _selection.toList(growable: false);
    _update(() => _selectionBusy = true);
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .movePhotosToTrash(ids);
      if (!mounted) {
        return;
      }
      _update(() {
        _selection.clear();
        _selectionMode = false;
      });
      showDesktopToast(
        context,
        l10n.desktopPhotosMovedToTrash(ids.length),
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
    } finally {
      if (mounted) {
        _update(() => _selectionBusy = false);
      }
    }
  }

  Future<void> _restoreSelectedFromTrash(
    ProviderContainer container,
    List<String> photoIds,
    AppLocalizations l10n,
  ) async {
    try {
      final controller = container.read(photoCenterControllerProvider.notifier);
      for (final photoId in photoIds) {
        await controller.restorePhotoFromTrash(photoId);
      }
      container
          .read(desktopToastProvider.notifier)
          .show(
            l10n.desktopPhotosRestoredFromTrash(photoIds.length),
            icon: DesktopIcons.check,
          );
    } on Object catch (error) {
      container
          .read(desktopToastProvider.notifier)
          .show(
            failureToast(l10n, l10n.photosRestore, error),
            kind: DesktopToastKind.error,
            icon: DesktopIcons.info,
          );
    }
  }

  Future<void> _restorePhoto(PhotoItem photo) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .restorePhotoFromTrash(photo.id);
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.photosRestore, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _confirmPurgePhoto(PhotoItem photo) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDesktopDialog<bool>(
      context,
      builder:
          (dialogContext) => DesktopDialog(
            width: 440,
            eyebrow: l10n.photosTabTrash,
            title: l10n.photosDeleteForever,
            content: Text(
              photo.title,
              style: DesktopType.dense(DesktopSkin.of(context).text2),
            ),
            actions: [
              DesktopButton(
                label: l10n.photosClose,
                onPressed: () => closeDesktopModal(dialogContext, false),
              ),
              DesktopButton(
                label: l10n.photosDeleteForever,
                icon: DesktopIcons.trash,
                variant: DesktopButtonVariant.danger,
                onPressed: () => closeDesktopModal(dialogContext, true),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .purgePhotoFromTrash(photo.id);
      if (mounted) {
        showDesktopToast(
          context,
          l10n.photosDeleteForever,
          icon: DesktopIcons.trash,
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.photosDeleteForever, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _confirmPurgeAllTrash() async {
    if (_purgingTrash) return;
    final l10n = AppLocalizations.of(context);
    final state = ref.read(photoCenterControllerProvider).asData?.value;
    final count = state?.trashTotalElements ?? state?.trashPhotos.length ?? 0;
    if (count == 0) return;
    final confirmed = await showDesktopDialog<bool>(
      context,
      builder:
          (dialogContext) => DesktopDialog(
            width: 440,
            eyebrow: l10n.photosTabTrash,
            title: l10n.photosEmptyTrashConfirmTitle,
            content: Text(
              l10n.photosEmptyTrashConfirmBody(count),
              style: DesktopType.dense(DesktopSkin.of(context).text2),
            ),
            actions: [
              DesktopButton(
                label: l10n.photosClose,
                onPressed: () => closeDesktopModal(dialogContext, false),
              ),
              DesktopButton(
                label: l10n.photosDeleteForever,
                icon: DesktopIcons.trash,
                variant: DesktopButtonVariant.danger,
                onPressed: () => closeDesktopModal(dialogContext, true),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    _update(() => _purgingTrash = true);
    try {
      await ref.read(photoCenterControllerProvider.notifier).purgeTrash();
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.photosTrashPurged,
        icon: DesktopIcons.trash,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.photosEmptyTrash, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) _update(() => _purgingTrash = false);
    }
  }

  static String? _photoLocationLabel(PhotoItem photo) {
    final loc = photo.gpsLocation;
    if (loc != null && loc.isNotEmpty) {
      final parts = <String>[];
      for (final key in const [
        'displayName',
        'name',
        'city',
        'state',
        'province',
        'country',
      ]) {
        final raw = loc[key]?.toString().trim();
        if (raw != null && raw.isNotEmpty && !parts.contains(raw)) {
          parts.add(raw);
          if (key == 'displayName') break;
        }
      }
      if (parts.isNotEmpty) {
        return parts.join(', ');
      }
    }
    if (photo.gpsLatitude != null && photo.gpsLongitude != null) {
      return '${photo.gpsLatitude!.toStringAsFixed(4)}, ${photo.gpsLongitude!.toStringAsFixed(4)}';
    }
    return null;
  }

  DesktopDetailData _buildPhotoDetailData(
    PhotoItem photo,
    List<PhotoItem> photos, {
    required PhotoBrowseSource source,
  }) {
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final locale = Localizations.localeOf(context).toString();
    final taken = photo.dateTaken ?? photo.createdAt;
    final takenText =
        taken == null ? '—' : DateFormat.yMMMd(locale).add_Hm().format(taken);
    final camera = [
      photo.cameraMake?.trim(),
      photo.cameraModel?.trim(),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    final exposureParts = <String>[
      if (photo.aperture != null && photo.aperture!.trim().isNotEmpty)
        photo.aperture!.trim(),
      if (photo.shutterSpeed != null && photo.shutterSpeed!.trim().isNotEmpty)
        photo.shutterSpeed!.trim(),
      if (photo.iso != null) 'ISO ${photo.iso}',
      if (photo.focalLength != null && photo.focalLength!.trim().isNotEmpty)
        photo.focalLength!.trim(),
    ];
    final resolution =
        photo.width != null && photo.height != null
            ? '${photo.width} × ${photo.height}'
            : null;
    final location = _photoLocationLabel(photo);

    return DesktopDetailData(
      id: 'photo:${photo.id}',
      kind: 'photo',
      title: photo.title,
      subtitle: takenText,
      imageUrl: photo.coverUrl ?? photo.sourceUrl,
      fallbackIcon: DesktopIcons.image,
      badge: photo.isVideo ? 'VIDEO' : photo.format.toUpperCase(),
      squareArt: false,
      chips: photo.tags,
      chipsLabel: isZh ? '标签' : 'Tags',
      factsLabel: isZh ? 'EXIF 拍摄信息' : 'EXIF METADATA',
      facts: [
        if (camera.isNotEmpty) MapEntry(isZh ? '相机型号' : 'Camera', camera),
        if (photo.lensModel != null && photo.lensModel!.trim().isNotEmpty)
          MapEntry(isZh ? '镜头' : 'Lens', photo.lensModel!.trim()),
        if (exposureParts.isNotEmpty)
          MapEntry(
            isZh ? '光圈 / 快门 / ISO' : 'Exposure',
            exposureParts.join(' · '),
          ),
        if (location != null) MapEntry(isZh ? '拍摄地点' : 'Location', location),
        if (resolution != null)
          MapEntry(isZh ? '分辨率' : 'Resolution', resolution),
        MapEntry(isZh ? '拍摄时间' : 'Date taken', takenText),
        MapEntry(
          l10n.desktopFilesSize,
          '${formatFileSize(photo.fileSize)} · ${photo.format.toUpperCase()}',
        ),
      ],
      primary: DesktopDetailAction(
        label: l10n.filesOpen,
        icon: DesktopIcons.image,
        onPressed: (_, _) => _openPhoto(photo, photos, source),
      ),
      secondary: DesktopDetailAction(
        label: photo.favorite ? l10n.photosUnfavorite : l10n.photosFavorite,
        icon: photo.favorite ? DesktopIcons.heartFilled : DesktopIcons.heart,
        onPressed: (_, _) => unawaited(_toggleSingleFavorite(photo)),
      ),
      extraActions: [
        DesktopDetailAction(
          label: l10n.photosAddToAlbum,
          icon: DesktopIcons.album,
          onPressed: (_, _) {
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
        DesktopDetailAction(
          label: l10n.photosDownload,
          icon: DesktopIcons.download,
          onPressed: (_, _) => unawaited(_downloadSinglePhoto(photo)),
        ),
      ],
    );
  }

  void _inspectPhoto(
    PhotoItem photo,
    List<PhotoItem> photos, {
    required PhotoBrowseSource source,
  }) {
    if (!mounted) return;
    ref
        .read(desktopShellProvider.notifier)
        .showDetail(_buildPhotoDetailData(photo, photos, source: source));
  }

  void _syncPhotoSelectionDetail() {
    if (!mounted) return;
    final shell = ref.read(desktopShellProvider.notifier);
    if (_selection.isEmpty) {
      shell.clearDetail();
      return;
    }
    final photos = _visibleSelectablePhotos();
    final source =
        _tab == DesktopPhotosTab.favorites
            ? PhotoBrowseSource.favorites
            : PhotoBrowseSource.library;
    final selectedItems = photos
        .where((item) => _selection.contains(item.id))
        .toList(growable: false);
    if (selectedItems.isEmpty) {
      shell.clearDetail();
      return;
    }
    if (selectedItems.length == 1) {
      shell.selectDetail(
        _buildPhotoDetailData(selectedItems.first, photos, source: source),
      );
      return;
    }
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final totalBytes = selectedItems.fold<int>(
      0,
      (sum, item) => sum + item.fileSize,
    );
    final videoCount = selectedItems.where((item) => item.isVideo).length;
    final photoCount = selectedItems.length - videoCount;
    shell.selectDetail(
      DesktopDetailData(
        id: 'photos-multi:${selectedItems.map((e) => e.id).join(",")}',
        kind: 'photo',
        title:
            isZh
                ? '已选 ${selectedItems.length} 项'
                : '${selectedItems.length} items selected',
        subtitle: formatFileSize(totalBytes),
        imageUrl: selectedItems.first.coverUrl ?? selectedItems.first.sourceUrl,
        fallbackIcon: DesktopIcons.image,
        badge: '${selectedItems.length}',
        squareArt: false,
        factsLabel: isZh ? '批量汇总' : 'SELECTION SUMMARY',
        facts: [
          MapEntry(isZh ? '照片' : 'Photos', '$photoCount'),
          MapEntry(isZh ? '视频' : 'Videos', '$videoCount'),
          MapEntry(l10n.desktopFilesSize, formatFileSize(totalBytes)),
        ],
        primary: DesktopDetailAction(
          label: l10n.photosFavorite,
          icon: DesktopIcons.heart,
          onPressed: (_, _) => unawaited(_favoriteSelected()),
        ),
        secondary: DesktopDetailAction(
          label: l10n.photosAddToAlbum,
          icon: DesktopIcons.album,
          onPressed: (_, _) => unawaited(_addSelectedToAlbum(_update)),
        ),
        extraActions: [
          DesktopDetailAction(
            label: l10n.photosDownload,
            icon: DesktopIcons.download,
            onPressed: (_, _) => unawaited(_downloadSelected(_update)),
          ),
          DesktopDetailAction(
            label: l10n.photosDelete,
            icon: DesktopIcons.trash,
            danger: true,
            onPressed: (_, _) => unawaited(_deleteSelected()),
          ),
        ],
      ),
    );
  }
}
