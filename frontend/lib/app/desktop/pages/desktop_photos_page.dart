import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart'
    show PointerDownEvent, PointerMoveEvent, PointerEvent, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_media_import_dialog.dart'
    show
        DesktopMediaImportKind,
        DesktopMediaImportSelection,
        showDesktopMediaImportDialog;
import 'package:omninest/app/desktop/widgets/desktop_places_globe.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/features/files/media_import_ui.dart'
    show MediaImportButton, MediaImportButtonState, MediaImportCompletionState;
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/application/media_import_queue_controller.dart';
import 'package:omninest/features/files/application/media_import_service.dart'
    show MediaImportBatchResult;
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/features/photos/domain/photo_album.dart'
    show PhotoAlbumDetail;
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/application/photo_display_order_controller.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_dialog.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart'
    show photoImportNoticeText;

part 'desktop_photos_groups.dart';
part 'desktop_photos_selection.dart';
part 'desktop_photos_album_picker.dart';
part 'desktop_photos_album_detail.dart';
part 'desktop_photos_sections.dart';
part 'desktop_photos_justified.dart';
part 'desktop_photos_reorder.dart';
part 'desktop_photos_import_actions.dart';
part 'desktop_photos_album_shelf.dart';
part 'desktop_photos_solo.dart';

/// 桌面相册页（样例 `Photos.tsx`）。
///
/// 三档视图：按日分组的胶片流、收藏、相册架。样例的分组是「等高一排、
/// 按宽高比铺满」的 justified 行——不是固定列网格，这正是它看起来像
/// 相片墙而不是表格的原因。
/// 顺序必须与样例 `Photos.tsx:54` 一致：Library · Albums · Places ·
/// Favorites · Trash。`DesktopSeg` 直接按枚举值顺序渲染，改这里就是改
/// 分类栏的排列。
enum DesktopPhotosTab { library, albums, places, favorites, trash }

typedef _PhotoOrderChanged =
    Future<void> Function(String contextKey, List<String> ids, int movedCount);

class DesktopPhotosPage extends ConsumerStatefulWidget {
  const DesktopPhotosPage({super.key});

  @override
  ConsumerState<DesktopPhotosPage> createState() => _DesktopPhotosPageState();
}

class _DesktopPhotosPageState extends ConsumerState<DesktopPhotosPage> {
  DesktopPhotosTab _tab = DesktopPhotosTab.library;
  final ScrollController _photosScrollController = ScrollController();
  bool _loadingMorePhotos = false;

  /// 缩略行高：样例 `.zoom` 的 150–320，默认 210。
  double _density = 210;

  /// 选中的照片 id（样例 `sel: Set<string>`）。只在胶片流与收藏两档生效。
  final Set<String> _selection = <String>{};
  final GlobalKey<MediaImportButtonState> _mediaImportKey =
      GlobalKey<MediaImportButtonState>();
  bool _selectionBusy = false;
  bool _purgingTrash = false;
  String? _selectedAlbumId;

  @override
  void initState() {
    super.initState();
    _photosScrollController.addListener(_maybeLoadMorePhotos);
  }

  @override
  void dispose() {
    _photosScrollController
      ..removeListener(_maybeLoadMorePhotos)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMorePhotos() {
    if (!mounted ||
        _loadingMorePhotos ||
        !_photosScrollController.hasClients ||
        (_tab != DesktopPhotosTab.library &&
            _tab != DesktopPhotosTab.favorites)) {
      return;
    }
    if (_photosScrollController.position.extentAfter > 600) return;

    final favorites = _tab == DesktopPhotosTab.favorites;
    final page =
        ref
            .read(favorites ? photoFavoritesProvider : photoListProvider)
            .asData
            ?.value;
    if (page == null || !page.hasMore) return;

    setState(() => _loadingMorePhotos = true);
    unawaited(_loadMorePhotoPage(favorites: favorites));
  }

  Future<void> _loadMorePhotoPage({required bool favorites}) async {
    final l10n = AppLocalizations.of(context);
    try {
      if (favorites) {
        await ref.read(photoFavoritesProvider.notifier).loadMore();
      } else {
        await ref.read(photoListProvider.notifier).loadMore();
      }
    } on Object catch (error) {
      if (!mounted) return;
      showDesktopToast(
        context,
        failureToast(l10n, l10n.modulePhotosTitle, error),
        kind: DesktopToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _loadingMorePhotos = false);
    }
  }

  void _checkForMorePhotosAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMorePhotos();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final photoOrders = ref.watch(photoDisplayOrderProvider);
    final dashboard = ref.watch(photoDashboardProvider).asData?.value;
    final pageAsync = ref.watch(photoListProvider);
    final favoritesAsync = ref.watch(photoFavoritesProvider);
    final albumsAsync = ref.watch(photoAlbumsProvider);
    final page = pageAsync.asData?.value;
    final favorites = favoritesAsync.asData?.value;
    final albums = albumsAsync.asData?.value;
    // 地点和回收站数据只在对应分区进入时请求。
    final locationGroupsAsync =
        _tab == DesktopPhotosTab.places
            ? ref.watch(photoLocationGroupsProvider)
            : null;
    final photoCenterAsync =
        _tab == DesktopPhotosTab.trash
            ? ref.watch(photoCenterControllerProvider)
            : null;

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
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _checkForMorePhotosAfterFrame();
              return false;
            },
            child: SingleChildScrollView(
              controller: _photosScrollController,
              child: DesktopPage(
                topPadding: DesktopMetrics.pageTopPaddingCompact,
                children: [
                  DesktopPageHead(
                    eyebrow:
                        l10n
                            .desktopPhotosCount(
                              dashboard?.totalPhotos ?? 0,
                              dashboard?.totalVideos ?? 0,
                            )
                            .toUpperCase(),
                    title: l10n.modulePhotosTitle,
                    actionsRightAlignedWhenWrapped: true,
                    actions: [
                      _importAction(context, l10n),
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
                          if (value == DesktopPhotosTab.library ||
                              value == DesktopPhotosTab.favorites) {
                            _checkForMorePhotosAfterFrame();
                          }
                          if (value == DesktopPhotosTab.trash) {
                            // 回收站按需取数：进入分区才请求，避免首屏多打一次。
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                ref
                                    .read(
                                      photoCenterControllerProvider.notifier,
                                    )
                                    .setFrameView(FrameView.trash);
                              }
                            });
                          }
                        },
                      ),
                      if (_tab == DesktopPhotosTab.library)
                        _DensitySlider(
                          value: _density,
                          onChanged:
                              (value) => setState(() => _density = value),
                        ),
                    ],
                  ),
                  switch (_tab) {
                    DesktopPhotosTab.library => _PhotoGroups(
                      photos: page?.items ?? const <PhotoItem>[],
                      displayOrders: photoOrders,
                      loading: page == null && pageAsync.isLoading,
                      error:
                          page == null && pageAsync.hasError
                              ? errorReason(pageAsync.error!, l10n)
                              : null,
                      onRetry: () => ref.invalidate(photoListProvider),
                      density: _density,
                      selection: _selection,
                      onActivate:
                          (photo, groupPhotos) => _activatePhoto(
                            photo,
                            groupPhotos,
                            source: PhotoBrowseSource.library,
                          ),
                      onToggleSelect: _toggleSelect,
                      onSelectMany:
                          (items) => setState(() {
                            final ids = items.map((item) => item.id).toSet();
                            final dayIsSelected =
                                ids.isNotEmpty &&
                                ids.every(_selection.contains);
                            if (dayIsSelected) {
                              _selection.removeAll(ids);
                            } else {
                              _selection.addAll(ids);
                            }
                          }),
                      onOrderChanged: _savePhotoOrder,
                      onResetOrder: _resetPhotoOrder,
                    ),
                    DesktopPhotosTab.places =>
                      locationGroupsAsync!.hasError &&
                              !locationGroupsAsync.hasValue
                          ? DesktopErrorView(
                            message: errorReason(
                              locationGroupsAsync.error!,
                              l10n,
                            ),
                            onRetry:
                                () =>
                                    ref.invalidate(photoLocationGroupsProvider),
                          )
                          : !locationGroupsAsync.hasValue
                          ? const _PlacesLoadingSkeleton()
                          : _PlacesSection(
                            groups:
                                locationGroupsAsync.asData?.value ??
                                const <PhotoGroup>[],
                            onOpen:
                                (photo, photos) => _openPhoto(
                                  photo,
                                  photos,
                                  PhotoBrowseSource.locations,
                                ),
                          ),
                    DesktopPhotosTab.favorites =>
                      favorites == null && favoritesAsync.hasError
                          ? DesktopErrorView(
                            message: errorReason(favoritesAsync.error!, l10n),
                            onRetry:
                                () => ref.invalidate(photoFavoritesProvider),
                          )
                          : favorites == null && favoritesAsync.isLoading
                          ? const DesktopSkeletonPhotoGrid(targetHeight: 200)
                          : _JustifiedPhotos(
                            photos: applyPhotoDisplayOrder(
                              favorites?.items ?? const <PhotoItem>[],
                              photoOrders['favorites'],
                            ),
                            targetHeight: 200,
                            selection: _selection,
                            onActivate:
                                (photo, favoritePhotos) => _activatePhoto(
                                  photo,
                                  favoritePhotos,
                                  source: PhotoBrowseSource.favorites,
                                ),
                            onToggleSelect: _toggleSelect,
                            orderContext: 'favorites',
                            onOrderChanged: _savePhotoOrder,
                          ),
                    DesktopPhotosTab.albums =>
                      albums == null && albumsAsync.hasError
                          ? DesktopErrorView(
                            message: errorReason(albumsAsync.error!, l10n),
                            onRetry: () => ref.invalidate(photoAlbumsProvider),
                          )
                          : _selectedAlbumId == null
                          ? _AlbumShelf(
                            albums: albums ?? const <PhotoAlbum>[],
                            loading: albums == null && albumsAsync.isLoading,
                            onOpen: _openAlbum,
                            onCreate: _createAlbum,
                          )
                          : _DesktopAlbumDetail(
                            albumId: _selectedAlbumId!,
                            onBack:
                                () => setState(() => _selectedAlbumId = null),
                            onShare: _shareAlbum,
                            onDelete: _deleteAlbum,
                            onOpenPhoto: _openAlbumPhoto,
                            onOrderChanged: _savePhotoOrder,
                          ),
                    DesktopPhotosTab.trash => _TrashSection(
                      state: photoCenterAsync?.asData?.value,
                      loading:
                          photoCenterAsync?.isLoading == true ||
                          photoCenterAsync?.asData?.value.isLoadingTrash ==
                              true,
                      error:
                          photoCenterAsync?.hasError == true &&
                                  !photoCenterAsync!.hasValue
                              ? errorReason(photoCenterAsync.error!, l10n)
                              : null,
                      onRetry:
                          () => ref.invalidate(photoCenterControllerProvider),
                      onRestore: _restorePhoto,
                      onPurge: _confirmPurgePhoto,
                      purging: _purgingTrash,
                      onPurgeAll: _confirmPurgeAllTrash,
                    ),
                  },
                  if (_loadingMorePhotos)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
              ),
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

  void _openPhoto(
    PhotoItem photo,
    List<PhotoItem> photos,
    PhotoBrowseSource source,
  ) {
    ref.read(photoBrowseScopeProvider.notifier).set(photos, source);
    desktopPush(context, DesktopRoutes.photoDetail(photo.id));
  }

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
  void _activatePhoto(
    PhotoItem photo,
    List<PhotoItem> photos, {
    required PhotoBrowseSource source,
  }) {
    final additive =
        _selection.isNotEmpty ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (additive) {
      _toggleSelect(photo);
      return;
    }
    _openPhoto(photo, photos, source);
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
