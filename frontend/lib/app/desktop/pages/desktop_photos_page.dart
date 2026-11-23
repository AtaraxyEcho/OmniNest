import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerCancelEvent,
        PointerDownEvent,
        PointerEvent,
        PointerMoveEvent,
        PointerUpEvent,
        kPrimaryButton;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:omninest/app/desktop/desktop_ambient_hints.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_photo_transition.dart';
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
import 'package:omninest/core/utils/file_size_formatter.dart';
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
part 'desktop_photos_actions.dart';
part 'desktop_photos_justified_shell.dart';
part 'desktop_photos_justified_tile.dart';
part 'desktop_photos_single_actions.dart';

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
  static const Duration _photosGateTimeout = Duration(milliseconds: 400);

  DesktopPhotosTab _tab = DesktopPhotosTab.library;
  final ScrollController _photosScrollController = ScrollController();
  bool _loadingMorePhotos = false;
  bool _morePhotosCheckScheduled = false;
  Timer? _gateTimer;
  bool _gateReleased = false;
  bool _syncedInitialAmbientPhoto = false;

  /// 缩略行高：样例 `.zoom` 的 150–320，默认 210。
  double _density = 210;

  /// 选中的照片 id（样例 `sel: Set<string>`）。只在胶片流与收藏两档生效。
  final Set<String> _selection = <String>{};
  bool _selectionMode = false;
  String? _lastSelectedPhotoId;
  final GlobalKey<MediaImportButtonState> _mediaImportKey =
      GlobalKey<MediaImportButtonState>();
  bool _selectionBusy = false;
  bool _purgingTrash = false;
  String? _selectedAlbumId;
  DateTime? _lastLoadMoreAttemptAt;
  final Map<String, _PhotoDayHoverState> _dayHoverStates =
      <String, _PhotoDayHoverState>{};

  static const Duration _loadMoreThrottle = Duration(milliseconds: 300);

  _PhotoDayHoverState _hoverStateForDay(String contextKey) =>
      _dayHoverStates.putIfAbsent(contextKey, _PhotoDayHoverState.new);

  bool _isAsyncSettled(AsyncValue<Object?> state) =>
      !(state.isLoading && !state.hasValue);

  @override
  void initState() {
    super.initState();
    _photosScrollController.addListener(_maybeLoadMorePhotos);
    HardwareKeyboard.instance.addHandler(_handlePageKey);
    // 统计眉标（photoDashboardProvider）与照片流（photoListProvider）共享 400ms 联合门控。
    final settled =
        _isAsyncSettled(ref.read(photoDashboardProvider)) &&
        _isAsyncSettled(ref.read(photoListProvider));
    if (settled) {
      _gateReleased = true;
    } else {
      _gateTimer = Timer(_photosGateTimeout, () {
        if (!mounted || _gateReleased) {
          return;
        }
        setState(() => _gateReleased = true);
      });
    }
  }

  @override
  void dispose() {
    _gateTimer?.cancel();
    for (final state in _dayHoverStates.values) {
      state.dispose();
    }
    _dayHoverStates.clear();
    HardwareKeyboard.instance.removeHandler(_handlePageKey);
    _photosScrollController
      ..removeListener(_maybeLoadMorePhotos)
      ..dispose();
    super.dispose();
  }

  bool _handlePageKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (_tab != DesktopPhotosTab.library &&
        _tab != DesktopPhotosTab.favorites) {
      return false;
    }
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null && !modalRoute.isCurrent) return false;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final textInputFocused =
        focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (textInputFocused) return false;

    final hardware = HardwareKeyboard.instance;
    final key = event.logicalKey;
    if ((hardware.isControlPressed || hardware.isMetaPressed) &&
        key == LogicalKeyboardKey.keyA) {
      final items = _visibleSelectablePhotos();
      if (items.isEmpty) return false;
      setState(() {
        _selectionMode = true;
        _selection
          ..clear()
          ..addAll(items.map((item) => item.id));
        _lastSelectedPhotoId = items.last.id;
      });
      _syncPhotoSelectionDetail();
      return true;
    }
    if (key == LogicalKeyboardKey.escape &&
        (_selection.isNotEmpty || _selectionMode)) {
      setState(() {
        _selection.clear();
        _selectionMode = false;
        _lastSelectedPhotoId = null;
      });
      ref.read(desktopShellProvider.notifier).clearDetail();
      return true;
    }
    if ((key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace) &&
        _selection.isNotEmpty &&
        !_selectionBusy) {
      unawaited(_deleteSelected());
      return true;
    }
    return false;
  }

  List<PhotoItem> _visibleSelectablePhotos() {
    final orders = ref.read(photoDisplayOrderProvider);
    if (_tab == DesktopPhotosTab.favorites) {
      final favs =
          ref.read(photoFavoritesProvider).asData?.value.items ??
          const <PhotoItem>[];
      return applyPhotoDisplayOrder(favs, orders['favorites']);
    }
    final items =
        ref.read(photoListProvider).asData?.value.items ?? const <PhotoItem>[];
    return applyPhotoLibraryDisplayOrder(items, orders);
  }

  void _maybeLoadMorePhotos() {
    if (!mounted ||
        _loadingMorePhotos ||
        !_photosScrollController.hasClients ||
        (_tab != DesktopPhotosTab.library &&
            _tab != DesktopPhotosTab.favorites)) {
      return;
    }
    final favorites = _tab == DesktopPhotosTab.favorites;
    final page =
        ref
            .read(favorites ? photoFavoritesProvider : photoListProvider)
            .asData
            ?.value;
    if (page == null || !page.hasMore) return;

    final now = DateTime.now();
    final lastAttempt = _lastLoadMoreAttemptAt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < _loadMoreThrottle) {
      return;
    }
    if (_photosScrollController.position.extentAfter > 600) return;

    _lastLoadMoreAttemptAt = now;
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

  /// ScrollMetricsNotification 防重入锁，避免单帧内高频重复入队回调。
  void _checkForMorePhotosAfterFrame() {
    if (_morePhotosCheckScheduled || _loadingMorePhotos) return;
    _morePhotosCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _morePhotosCheckScheduled = false;
      if (mounted) _maybeLoadMorePhotos();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final photoOrders = ref.watch(photoDisplayOrderProvider);
    final dashboardAsync = ref.watch(photoDashboardProvider);
    final dashboard = dashboardAsync.asData?.value;
    final pageAsync = ref.watch(photoListProvider);
    final page = pageAsync.asData?.value;
    if (!_syncedInitialAmbientPhoto && page != null && page.items.isNotEmpty) {
      final firstImage = page.items.where((item) => !item.isVideo).firstOrNull;
      if (firstImage != null) {
        _syncedInitialAmbientPhoto = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(desktopAmbientHintProvider.notifier)
              .rememberPhotoId(firstImage.id);
        });
      }
    }
    // 按当前活跃 _tab 延迟订阅收藏、相册、地点与回收站，避免首屏并行拉取冗余接口。
    final favoritesAsync =
        _tab == DesktopPhotosTab.favorites
            ? ref.watch(photoFavoritesProvider)
            : null;
    final albumsAsync =
        _tab == DesktopPhotosTab.albums ? ref.watch(photoAlbumsProvider) : null;
    final favorites = favoritesAsync?.asData?.value;
    final albums = albumsAsync?.asData?.value;
    final locationGroupsAsync =
        _tab == DesktopPhotosTab.places
            ? ref.watch(photoLocationGroupsProvider)
            : null;
    final photoCenterAsync =
        _tab == DesktopPhotosTab.trash
            ? ref.watch(photoCenterControllerProvider)
            : null;

    final dashboardLoading =
        dashboardAsync.isLoading && !dashboardAsync.hasValue;
    final pageLoading = pageAsync.isLoading && !pageAsync.hasValue;
    if (!dashboardLoading && !pageLoading && !_gateReleased) {
      _gateReleased = true;
      _gateTimer?.cancel();
      _gateTimer = null;
    }
    final jointGated = !_gateReleased;
    final eyebrowLoading = jointGated || dashboardLoading;
    final libraryLoading = jointGated || (page == null && pageAsync.isLoading);

    final labels = <DesktopPhotosTab, String>{
      DesktopPhotosTab.library: l10n.desktopPhotosLibrary,
      DesktopPhotosTab.places: l10n.photosTabPlaces,
      DesktopPhotosTab.favorites: l10n.photosTabFavorites,
      DesktopPhotosTab.albums: l10n.photosTabAlbums,
      DesktopPhotosTab.trash: l10n.photosTabTrash,
    };

    final supportsSelection =
        _tab == DesktopPhotosTab.library || _tab == DesktopPhotosTab.favorites;
    final selectionActive = _selectionMode || _selection.isNotEmpty;

    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _checkForMorePhotosAfterFrame();
              return false;
            },
            child: DesktopSliverPage(
              controller: _photosScrollController,
              topPadding: DesktopMetrics.pageTopPaddingCompact,
              slivers: [
                DesktopStickySliver(
                  child: Stack(
                    children: [
                      DesktopPageHead(
                        eyebrow:
                            eyebrowLoading
                                ? ' '
                                : l10n
                                    .desktopPhotosCount(
                                      dashboard?.totalPhotos ?? 0,
                                      dashboard?.totalVideos ?? 0,
                                    )
                                    .toUpperCase(),
                        title: l10n.modulePhotosTitle,
                        sticky: true,
                        actionsRightAlignedWhenWrapped: true,
                        actions: [
                          _importAction(context, l10n),
                          // 对齐 `Photos.tsx:108-115`：Import → Seg → Select(soft) → Zoom。
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
                                _selectionMode = false;
                                _lastSelectedPhotoId = null;
                              });
                              if (value == DesktopPhotosTab.library ||
                                  value == DesktopPhotosTab.favorites) {
                                _checkForMorePhotosAfterFrame();
                              }
                              if (value == DesktopPhotosTab.trash) {
                                // 回收站按需取数：进入分区才请求，避免首屏多打一次。
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) {
                                    ref
                                        .read(
                                          photoCenterControllerProvider
                                              .notifier,
                                        )
                                        .setFrameView(FrameView.trash);
                                  }
                                });
                              }
                            },
                          ),
                          if (supportsSelection)
                            DesktopButton(
                              label:
                                  selectionActive
                                      ? l10n.photosDone
                                      : l10n.desktopPhotosSelect,
                              icon:
                                  selectionActive
                                      ? DesktopIcons.close
                                      : DesktopIcons.check,
                              variant:
                                  selectionActive
                                      ? DesktopButtonVariant.primary
                                      : DesktopButtonVariant.soft,
                              onPressed: () {
                                setState(() {
                                  if (selectionActive) {
                                    _selection.clear();
                                    _selectionMode = false;
                                    _lastSelectedPhotoId = null;
                                  } else {
                                    _selectionMode = true;
                                  }
                                });
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
                      if (eyebrowLoading)
                        const Positioned(
                          left: 0,
                          top: 10,
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: DesktopSkeletonBox(
                                width: 96,
                                height: 11,
                                radius: 5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_tab == DesktopPhotosTab.library)
                  ..._buildPhotoGroupSlivers(
                    context: context,
                    photos: page?.items ?? const <PhotoItem>[],
                    displayOrders: photoOrders,
                    loading: libraryLoading,
                    error:
                        page == null && pageAsync.hasError
                            ? errorReason(pageAsync.error!, l10n)
                            : null,
                    onRetry: () => ref.invalidate(photoListProvider),
                    density: _density,
                    selection: _selection,
                    selectionMode: _selectionMode,
                    onActivate:
                        (photo, groupPhotos) => _activatePhoto(
                          photo,
                          groupPhotos,
                          source: PhotoBrowseSource.library,
                        ),
                    onToggleSelect: _toggleSelect,
                    onSecondaryTap:
                        (photo, groupPhotos, globalPos) =>
                            _openPhotoContextMenu(
                              photo,
                              groupPhotos,
                              globalPos,
                              source: PhotoBrowseSource.library,
                            ),
                    onInspect:
                        (photo, groupPhotos) => _inspectPhoto(
                          photo,
                          groupPhotos,
                          source: PhotoBrowseSource.library,
                        ),
                    onSelectMany: (items) {
                      setState(() {
                        final ids = items.map((item) => item.id).toSet();
                        final dayIsSelected =
                            ids.isNotEmpty && ids.every(_selection.contains);
                        if (dayIsSelected) {
                          _selection.removeAll(ids);
                        } else {
                          _selection.addAll(ids);
                          if (items.isNotEmpty) {
                            _lastSelectedPhotoId = items.last.id;
                          }
                        }
                      });
                      _syncPhotoSelectionDetail();
                    },
                    onOrderChanged: _savePhotoOrder,
                    onResetOrder: _resetPhotoOrder,
                    hoverStateOf: _hoverStateForDay,
                  )
                else
                  SliverToBoxAdapter(
                    child: switch (_tab) {
                      DesktopPhotosTab.library => const SizedBox.shrink(),
                      DesktopPhotosTab.places =>
                        locationGroupsAsync!.hasError &&
                                !locationGroupsAsync.hasValue
                            ? DesktopErrorView(
                              message: errorReason(
                                locationGroupsAsync.error!,
                                l10n,
                              ),
                              onRetry:
                                  () => ref.invalidate(
                                    photoLocationGroupsProvider,
                                  ),
                            )
                            : DesktopSkeletonSwitcher(
                              regionId: 'photos-places',
                              hasData: locationGroupsAsync.hasValue,
                              loading: !locationGroupsAsync.hasValue,
                              skeleton: const _PlacesLoadingSkeleton(),
                              child: _PlacesSection(
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
                            ),
                      DesktopPhotosTab.favorites =>
                        favorites == null && favoritesAsync!.hasError
                            ? DesktopErrorView(
                              message: errorReason(favoritesAsync.error!, l10n),
                              onRetry:
                                  () => ref.invalidate(photoFavoritesProvider),
                            )
                            : DesktopSkeletonSwitcher(
                              regionId: 'photos-favorites',
                              hasData: favorites != null,
                              loading:
                                  favorites == null &&
                                  favoritesAsync!.isLoading,
                              skeleton: const DesktopSkeletonPhotoGrid(
                                targetHeight: 200,
                                showGroupHeaders: false,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (photoOrders.containsKey('favorites'))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: DesktopLink(
                                          label: l10n.desktopPhotosResetOrder,
                                          onPressed:
                                              () =>
                                                  _resetPhotoOrder('favorites'),
                                        ),
                                      ),
                                    ),
                                  _JustifiedPhotos(
                                    photos: applyPhotoDisplayOrder(
                                      favorites?.items ?? const <PhotoItem>[],
                                      photoOrders['favorites'],
                                    ),
                                    targetHeight: 200,
                                    selection: _selection,
                                    selectionMode: _selectionMode,
                                    onActivate:
                                        (photo, favoritePhotos) =>
                                            _activatePhoto(
                                              photo,
                                              favoritePhotos,
                                              source:
                                                  PhotoBrowseSource.favorites,
                                            ),
                                    onToggleSelect: _toggleSelect,
                                    onSecondaryTap:
                                        (photo, favoritePhotos, globalPos) =>
                                            _openPhotoContextMenu(
                                              photo,
                                              favoritePhotos,
                                              globalPos,
                                              source:
                                                  PhotoBrowseSource.favorites,
                                            ),
                                    onInspect:
                                        (photo, favoritePhotos) =>
                                            _inspectPhoto(
                                              photo,
                                              favoritePhotos,
                                              source:
                                                  PhotoBrowseSource.favorites,
                                            ),
                                    orderContext: 'favorites',
                                    onOrderChanged: _savePhotoOrder,
                                  ),
                                ],
                              ),
                            ),
                      DesktopPhotosTab.albums =>
                        albums == null && albumsAsync!.hasError
                            ? DesktopErrorView(
                              message: errorReason(albumsAsync.error!, l10n),
                              onRetry:
                                  () => ref.invalidate(photoAlbumsProvider),
                            )
                            : _selectedAlbumId == null
                            ? _AlbumShelf(
                              albums: albums ?? const <PhotoAlbum>[],
                              loading: albums == null && albumsAsync!.isLoading,
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
                  ),
                if (_loadingMorePhotos)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Center(
                        child: DesktopSpinner(size: 18, strokeWidth: 2),
                      ),
                    ),
                  ),
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
            onClear: () {
              setState(() {
                _selection.clear();
                _selectionMode = false;
                _lastSelectedPhotoId = null;
              });
              ref.read(desktopShellProvider.notifier).clearDetail();
            },
          ),
        ),
      ],
    );
  }

  void _update(VoidCallback fn) => setState(fn);
}
