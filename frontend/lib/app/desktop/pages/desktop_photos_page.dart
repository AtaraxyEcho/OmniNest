import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_places_globe.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/desktop/widgets/desktop_tilt.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/features/photos/domain/photo_album.dart'
    show PhotoAlbumDetail;
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_dialog.dart';
import 'package:omninest/features/video/video_dashboard.dart';

part 'desktop_photos_groups.dart';
part 'desktop_photos_selection.dart';
part 'desktop_photos_album_picker.dart';
part 'desktop_photos_album_detail.dart';
part 'desktop_photos_sections.dart';

/// 桌面相册页（样例 `Photos.tsx`）。
///
/// 三档视图：按日分组的胶片流、收藏、相册架。样例的分组是「等高一排、
/// 按宽高比铺满」的 justified 行——不是固定列网格，这正是它看起来像
/// 相片墙而不是表格的原因。
/// 顺序必须与样例 `Photos.tsx:54` 一致：Library · Albums · Places ·
/// Favorites · Trash。`DesktopSeg` 直接按枚举值顺序渲染，改这里就是改
/// 分类栏的排列。
enum DesktopPhotosTab { library, albums, places, favorites, trash }

class DesktopPhotosPage extends ConsumerStatefulWidget {
  const DesktopPhotosPage({super.key});

  @override
  ConsumerState<DesktopPhotosPage> createState() => _DesktopPhotosPageState();
}

class _DesktopPhotosPageState extends ConsumerState<DesktopPhotosPage> {
  DesktopPhotosTab _tab = DesktopPhotosTab.library;

  /// 缩略行高：样例 `.zoom` 的 150–320，默认 210。
  double _density = 210;

  /// 选中的照片 id（样例 `sel: Set<string>`）。只在胶片流与收藏两档生效。
  final Set<String> _selection = <String>{};
  bool _selectionBusy = false;
  bool _purgingTrash = false;
  String? _selectedAlbumId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dashboard = ref.watch(photoDashboardProvider).asData?.value;
    final videoDashboard = ref.watch(movieDashboardProvider).asData?.value;
    final page = ref.watch(photoListProvider).asData?.value;
    final favorites = ref.watch(photoFavoritesProvider).asData?.value;
    final albums = ref.watch(photoAlbumsProvider).asData?.value;
    if (_tab == DesktopPhotosTab.places) {
      // 只在进入地点分区时取数：分组接口按 GPS 聚合，首屏不需要。
      ref.watch(photoLocationGroupsProvider);
    }

    final labels = <DesktopPhotosTab, String>{
      DesktopPhotosTab.library: l10n.desktopPhotosLibrary,
      DesktopPhotosTab.places: l10n.photosTabPlaces,
      DesktopPhotosTab.favorites: l10n.photosTabFavorites,
      DesktopPhotosTab.albums: l10n.photosTabAlbums,
      DesktopPhotosTab.trash: l10n.photosTabTrash,
    };

    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            child: DesktopPage(
              topPadding: DesktopMetrics.pageTopPaddingCompact,
              children: [
                DesktopPageHead(
                  eyebrow:
                      l10n
                          .desktopPhotosCount(
                            dashboard?.totalPhotos ?? 0,
                            (videoDashboard?.stats.movieCount ?? 0) +
                                (videoDashboard?.stats.episodeCount ?? 0),
                          )
                          .toUpperCase(),
                  title: l10n.modulePhotosTitle,
                  actionsRightAlignedWhenWrapped: true,
                  actions: [
                    // 样例 `Photos.tsx:54-55`：`.head-actions` 里 Seg 在左、缩放
                    // 滑条在右；滑条只在 Library 档出现。
                    DesktopSeg<DesktopPhotosTab>(
                      options: DesktopPhotosTab.values,
                      value: _tab,
                      labelOf: (value) => labels[value] ?? '',
                      onChanged: (value) {
                        setState(() {
                          _tab = value;
                          if (value != DesktopPhotosTab.albums) {
                            _selectedAlbumId = null;
                          }
                          // 换分区时清空选中：样例的选中集只作用于当前列表。
                          _selection.clear();
                        });
                        if (value == DesktopPhotosTab.trash) {
                          // 回收站按需取数：进入分区才请求，避免首屏多打一次。
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              ref
                                  .read(photoCenterControllerProvider.notifier)
                                  .setFrameView(FrameView.trash);
                            }
                          });
                        }
                      },
                    ),
                    if (_tab == DesktopPhotosTab.library)
                      _DensitySlider(
                        value: _density,
                        onChanged: (value) => setState(() => _density = value),
                      ),
                  ],
                ),
                switch (_tab) {
                  DesktopPhotosTab.library => _PhotoGroups(
                    photos: page?.items ?? const <PhotoItem>[],
                    loading: page == null,
                    density: _density,
                    selection: _selection,
                    onActivate: _activatePhoto,
                    onToggleSelect: _toggleSelect,
                    onSelectMany:
                        (items) => setState(
                          () => _selection.addAll(items.map((item) => item.id)),
                        ),
                  ),
                  DesktopPhotosTab.places => _PlacesSection(
                    groups:
                        ref.watch(photoLocationGroupsProvider).asData?.value ??
                        const <PhotoGroup>[],
                    onOpen: _openPhoto,
                  ),
                  DesktopPhotosTab.favorites => _JustifiedPhotos(
                    photos: favorites?.items ?? const <PhotoItem>[],
                    targetHeight: 200,
                    selection: _selection,
                    onActivate: _activatePhoto,
                    onToggleSelect: _toggleSelect,
                  ),
                  DesktopPhotosTab.albums =>
                    _selectedAlbumId == null
                        ? _AlbumShelf(
                          albums: albums ?? const <PhotoAlbum>[],
                          onOpen: _openAlbum,
                          onCreate: _createAlbum,
                        )
                        : _DesktopAlbumDetail(
                          albumId: _selectedAlbumId!,
                          onBack: () => setState(() => _selectedAlbumId = null),
                          onShare: _shareAlbum,
                          onDelete: _deleteAlbum,
                          onOpenPhoto: _openAlbumPhoto,
                        ),
                  DesktopPhotosTab.trash => _TrashSection(
                    state:
                        ref.watch(photoCenterControllerProvider).asData?.value,
                    onRestore: _restorePhoto,
                    onPurge: _confirmPurgePhoto,
                    purging: _purgingTrash,
                    onPurgeAll: _confirmPurgeAllTrash,
                  ),
                },
              ],
            ),
          ),
        ),
        // 样例 `.sel-bar`：底部居中浮层，不占页面流；空选中时滑下淡出。
        Positioned(
          left: 0,
          right: 0,
          bottom: DesktopMetrics.playerBarClearance,
          child: _PhotoSelectionOverlay(
            count: _selection.length,
            busy: _selectionBusy,
            onFavorite: _favoriteSelected,
            onAlbum: () => _addSelectedToAlbum(setState),
            onDownload: () => _downloadSelected(setState),
            onDelete: _deleteSelected,
            onClear: () => setState(_selection.clear),
          ),
        ),
      ],
    );
  }

  void _openPhoto(PhotoItem photo) {
    ref
        .read(photoBrowseScopeProvider.notifier)
        .set(const <PhotoItem>[], PhotoBrowseSource.library);
    desktopPush(context, DesktopRoutes.photoDetail(photo.id));
  }

  void _openAlbum(PhotoAlbum album) {
    setState(() {
      _tab = DesktopPhotosTab.albums;
      _selectedAlbumId = album.id;
      _selection.clear();
    });
  }

  void _openAlbumPhoto(PhotoItem photo, List<PhotoItem> photos) {
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
      setState(() => _selectedAlbumId = null);
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

  /// 样例 `Photos.tsx:65`：已经有选中项、或按住 Ctrl/Cmd 时点击是「切换选中」，
  /// 否则才打开大图。没有这条规则，选中状态下一点就跳走，选不中第二张。
  void _activatePhoto(PhotoItem photo) {
    final additive =
        _selection.isNotEmpty ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (additive) {
      _toggleSelect(photo);
      return;
    }
    _openPhoto(photo);
  }

  void _toggleSelect(PhotoItem photo) {
    setState(() {
      if (!_selection.remove(photo.id)) {
        _selection.add(photo.id);
      }
    });
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
      setState(_selection.clear);
      return;
    }
    setState(() => _selectionBusy = true);
    try {
      final controller = ref.read(photoCenterControllerProvider.notifier);
      for (final photo in pending) {
        await controller.toggleFavorite(photo.id, currentFavorite: false);
      }
      if (!mounted) {
        return;
      }
      setState(_selection.clear);
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
        setState(() => _selectionBusy = false);
      }
    }
  }

  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final ids = _selection.toList(growable: false);
    setState(() => _selectionBusy = true);
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .movePhotosToTrash(ids);
      if (!mounted) {
        return;
      }
      setState(_selection.clear);
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
        setState(() => _selectionBusy = false);
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
    setState(() => _purgingTrash = true);
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
      if (mounted) setState(() => _purgingTrash = false);
    }
  }
}
