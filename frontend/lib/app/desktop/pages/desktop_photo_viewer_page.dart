import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_controls.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/features/photos/application/photo_display_order_controller.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_panel.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_slideshow_overlays.dart';

part 'desktop_photo_viewer_filmstrip.dart';

/// 桌面照片查看器（样例 `PhotoViewer`）：柔和模糊背景 + 上下暗纱渐变 + 顶栏 +
/// 左右翻页 + 缩放/旋转舞台 + 底部胶片条/幻灯片分段进度 + 右侧信息面板。
///
/// 与移动 `PhotoDetailPage` 分开：移动版是"页面 + 底部操作"，样例是满铺
/// 覆盖层，两套几何无法共用；数据仍走同一组 provider，动作落在
/// `photoCenterControllerProvider`，不另建取数链路。
class DesktopPhotoViewerPage extends ConsumerStatefulWidget {
  const DesktopPhotoViewerPage({required this.photoId, super.key});

  final String photoId;

  @override
  ConsumerState<DesktopPhotoViewerPage> createState() =>
      _DesktopPhotoViewerPageState();
}

class _DesktopPhotoViewerPageState extends ConsumerState<DesktopPhotoViewerPage>
    with SingleTickerProviderStateMixin {
  static const Duration _slideInterval = Duration(milliseconds: 3800);

  final TransformationController _zoom = TransformationController();
  final FocusNode _focus = FocusNode(debugLabel: 'desktop-photo-viewer');
  final GlobalKey _stageKey = GlobalKey(
    debugLabel: 'desktop-photo-viewer-stage',
  );
  late final AnimationController _slideProgress = AnimationController(
    vsync: this,
    duration: _slideInterval,
  );
  Offset? _lastDoubleTapLocal;

  late String _currentId = widget.photoId;
  double _rotation = 0;
  double _scale = 1;
  bool _info = false;
  bool _slideshow = false;
  bool _thumbnailsVisible = true;
  bool _pointerInsideViewer = false;
  bool _shareOpen = false;
  bool _loadingMoreBrowsePhotos = false;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_syncScale);
    _slideProgress.addStatusListener(_onSlideProgressStatus);
  }

  @override
  void dispose() {
    _slideProgress
      ..removeStatusListener(_onSlideProgressStatus)
      ..dispose();
    _zoom
      ..removeListener(_syncScale)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSlideProgressStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_slideshow || !mounted) {
      return;
    }
    final previousId = _currentId;
    _step(1);
    if (_slideshow && _currentId == previousId) {
      _slideProgress.forward(from: 0);
    }
  }

  void _syncScale() {
    final value = _zoom.value.getMaxScaleOnAxis();
    if ((value - _scale).abs() > 0.01) {
      setState(() => _scale = value);
    }
  }

  void _setPointerInsideViewer(bool value) {
    if (_pointerInsideViewer == value) {
      return;
    }
    setState(() => _pointerInsideViewer = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final browseScope = ref.watch(photoBrowseScopeProvider);
    final libraryPhotos =
        ref.watch(photoListProvider).asData?.value.items ?? const <PhotoItem>[];
    final list =
        browseScope.contains(_currentId) ? browseScope.photos : libraryPhotos;
    final browseSource =
        browseScope.contains(_currentId)
            ? browseScope.source
            : PhotoBrowseSource.library;
    final canLoadNextPage = switch (browseSource) {
      PhotoBrowseSource.library =>
        ref.watch(photoListProvider).asData?.value.hasMore ?? false,
      PhotoBrowseSource.favorites =>
        ref.watch(photoFavoritesProvider).asData?.value.hasMore ?? false,
      _ => false,
    };
    final index = list.indexWhere((photo) => photo.id == _currentId);
    final fallback = index >= 0 ? list[index] : null;
    final detail = ref.watch(photoDetailProvider(_currentId)).asData?.value;
    final photo = detail ?? fallback;
    final chromeVisible = !_slideshow || _pointerInsideViewer;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, event) => _onKey(event),
      child: MouseRegion(
        onEnter: (_) => _setPointerInsideViewer(true),
        onExit: (_) => _setPointerInsideViewer(false),
        child: ColoredBox(
          color: DesktopPalette.stageBlack,
          child: Stack(
            children: [
              // 还原旧版 SlideshowBlurredCover 同源柔和模糊层（96px 低分缩略图 +
              // 1.12 放大 + low 采样 + 0.35 暗罩），外层 450ms 交叉淡入淡出同步切图氛围。
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: DesktopMotion.of(
                      context,
                      const Duration(milliseconds: 450),
                    ),
                    layoutBuilder:
                        (currentChild, previousChildren) => Stack(
                          fit: StackFit.expand,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        ),
                    child:
                        photo == null
                            ? const ColoredBox(
                              key: ValueKey<String>('viewer-bg-empty'),
                              color: DesktopPalette.stageBlack,
                            )
                            : SlideshowBlurredCover(
                              key: ValueKey<String>('viewer-bg-${photo.id}'),
                              photo: photo,
                            ),
                  ),
                ),
              ),
              if (photo == null)
                const Center(child: SizedBox(width: 32, height: 32))
              else ...[
                _ViewerStage(
                  stageKey: _stageKey,
                  photo: photo,
                  zoom: _zoom,
                  rotation: _rotation,
                  slideshow: _slideshow,
                  infoOpen: _info,
                  onDismissInfo: () => setState(() => _info = false),
                  onDoubleTapDown: (pos) => _lastDoubleTapLocal = pos,
                  onDoubleTap: _toggleZoom,
                  onWheel: _onWheel,
                ),
                // 补齐旧版上下三段式暗纱渐变（底部 0xB8 → 0x2E → transparent，
                // 控件隐藏时保留 0.4 透明底纱）。
                SlideshowGradients(visible: chromeVisible),
                _TopBar(
                  photo: photo,
                  index: index,
                  total: list.length,
                  info: _info,
                  slideshow: _slideshow,
                  visible: chromeVisible,
                  favorite: photo.favorite,
                  onClose: _close,
                  onToggleInfo: () => setState(() => _info = !_info),
                  onToggleSlideshow: _toggleSlideshow,
                  onRotate: () => setState(() => _rotation += 90),
                  onToggleFavorite: () => _toggleFavorite(photo),
                  onEdit:
                      () => desktopPush(context, '/photos/${photo.id}/edit'),
                  onShare: () {
                    setState(() {
                      _info = false;
                      _shareOpen = true;
                    });
                  },
                  onDelete: () => unawaited(_moveToTrash(photo)),
                ),
                _NavButton(
                  alignment: Alignment.centerLeft,
                  icon: DesktopIcons.left,
                  tooltip: l10n.desktopPhotosPrevious,
                  onPressed: list.length > 1 ? () => _step(-1) : null,
                ),
                _NavButton(
                  alignment: Alignment.centerRight,
                  icon: DesktopIcons.chevron,
                  tooltip: l10n.desktopPhotosNext,
                  onPressed:
                      list.length > 1 || canLoadNextPage
                          ? () => _step(1)
                          : null,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !chromeVisible,
                    child: AnimatedOpacity(
                      opacity: chromeVisible ? 1 : 0,
                      duration: DesktopMotion.of(
                        context,
                        DesktopMotion.viewerChrome,
                      ),
                      child: _Filmstrip(
                        photos: list,
                        currentPhoto: photo,
                        currentIndex: math.max(index, 0),
                        slideshow: _slideshow,
                        thumbnailsVisible: _thumbnailsVisible,
                        slideProgress: _slideProgress,
                        onPick: _select,
                        onToggleSlideshow: _toggleSlideshow,
                        onToggleThumbnails:
                            () => setState(
                              () => _thumbnailsVisible = !_thumbnailsVisible,
                            ),
                      ),
                    ),
                  ),
                ),
                _InfoPanel(
                  open: _info,
                  photo: photo,
                  scale: _scale,
                  onClose: () => setState(() => _info = false),
                  onZoom: _setScale,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_shareOpen,
                    child: AnimatedOpacity(
                      opacity: _shareOpen ? 1 : 0,
                      duration: DesktopMotion.of(
                        context,
                        _shareOpen
                            ? DesktopMotion.drawerScrim
                            : DesktopMotion.drawerOut,
                      ),
                      curve:
                          _shareOpen
                              ? DesktopMotion.ease
                              : DesktopMotion.exitCurve,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _shareOpen = false),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                          child: const ColoredBox(color: DesktopPalette.scrim),
                        ),
                      ),
                    ),
                  ),
                ),
                PhotoSharePanel(
                  visible: _shareOpen,
                  photo: photo,
                  desktopStyle: true,
                  onDone: () => setState(() => _shareOpen = false),
                ),
              ],
              if (list.isEmpty && photo == null)
                Center(
                  child: Text(
                    AppLocalizations.of(context).photosNoPhotos,
                    style: DesktopType.body(skin.text3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 导航 ────────────────────────────────────────────────────────────

  void _step(int delta) {
    final browseScope = ref.read(photoBrowseScopeProvider);
    final libraryPhotos =
        ref.read(photoListProvider).asData?.value.items ?? const <PhotoItem>[];
    final list =
        browseScope.contains(_currentId) ? browseScope.photos : libraryPhotos;
    if (list.isEmpty) {
      return;
    }
    final index = list.indexWhere((photo) => photo.id == _currentId);
    final source =
        browseScope.contains(_currentId)
            ? browseScope.source
            : PhotoBrowseSource.library;
    if (delta > 0 && index == list.length - 1) {
      final hasMore = switch (source) {
        PhotoBrowseSource.library =>
          ref.read(photoListProvider).asData?.value.hasMore ?? false,
        PhotoBrowseSource.favorites =>
          ref.read(photoFavoritesProvider).asData?.value.hasMore ?? false,
        _ => false,
      };
      if (hasMore) {
        unawaited(
          _loadMoreBrowsePhotos(source: source, previousLength: list.length),
        );
        return;
      }
    }
    final next = list[(math.max(index, 0) + delta + list.length) % list.length];
    _select(next.id);
  }

  Future<void> _loadMoreBrowsePhotos({
    required PhotoBrowseSource source,
    required int previousLength,
  }) async {
    if (_loadingMoreBrowsePhotos) return;
    setState(() => _loadingMoreBrowsePhotos = true);
    final l10n = AppLocalizations.of(context);
    try {
      switch (source) {
        case PhotoBrowseSource.library:
          await ref.read(photoListProvider.notifier).loadMore();
        case PhotoBrowseSource.favorites:
          await ref.read(photoFavoritesProvider.notifier).loadMore();
        case PhotoBrowseSource.album ||
            PhotoBrowseSource.timeline ||
            PhotoBrowseSource.locations ||
            PhotoBrowseSource.tag:
          return;
      }
      if (!mounted) return;
      final orders = ref.read(photoDisplayOrderProvider);
      final updatedPhotos = switch (source) {
        PhotoBrowseSource.library => applyPhotoLibraryDisplayOrder(
          ref.read(photoListProvider).asData?.value.items ?? const [],
          orders,
        ),
        PhotoBrowseSource.favorites => applyPhotoDisplayOrder(
          ref.read(photoFavoritesProvider).asData?.value.items ?? const [],
          orders['favorites'],
        ),
        _ => const <PhotoItem>[],
      };
      if (updatedPhotos.length <= previousLength) return;
      ref.read(photoBrowseScopeProvider.notifier).set(updatedPhotos, source);
      _step(1);
    } on Object catch (error) {
      if (!mounted) return;
      showDesktopToast(
        context,
        failureToast(l10n, l10n.modulePhotosTitle, error),
        kind: DesktopToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _loadingMoreBrowsePhotos = false);
    }
  }

  void _select(String id) {
    setState(() {
      _currentId = id;
      _rotation = 0;
      _scale = 1;
      _zoom.value = Matrix4.identity();
    });
    if (_slideshow) {
      _slideProgress.forward(from: 0);
    }
  }

  void _close() {
    _slideProgress.stop();
    // 覆盖层只 push 不 go：直接 go 会把来路换成照片页，系统返回即退出应用。
    exitDetailRoute(context, fallbackRoute: '/photos');
  }

  // ── 缩放 ────────────────────────────────────────────────────────────

  void _toggleZoom() {
    if (_scale > 1.05) {
      _zoom.value = Matrix4.identity();
      return;
    }
    _setScale(2.4, focalPoint: _lastDoubleTapLocal);
  }

  void _setScale(double value, {Offset? focalPoint}) {
    final nextScale = value.clamp(1.0, 5.0);
    if (nextScale <= 1.001) {
      _zoom.value = Matrix4.identity();
      return;
    }
    final box = _stageKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) {
      _zoom.value = Matrix4.diagonal3Values(nextScale, nextScale, 1);
      return;
    }
    final size = box.size;
    final current = _zoom.value;
    final oldScale = current.getMaxScaleOnAxis().clamp(1.0, 5.0);
    final oldTx = current.storage[12];
    final oldTy = current.storage[13];
    final focal = focalPoint ?? Offset(size.width / 2, size.height / 2);
    final sceneX = (focal.dx - oldTx) / oldScale;
    final sceneY = (focal.dy - oldTy) / oldScale;
    final minTx = size.width * (1.0 - nextScale);
    final minTy = size.height * (1.0 - nextScale);
    final nextTx = (focal.dx - sceneX * nextScale).clamp(minTx, 0.0);
    final nextTy = (focal.dy - sceneY * nextScale).clamp(minTy, 0.0);
    _zoom.value =
        Matrix4.identity()
          ..translateByDouble(nextTx, nextTy, 0.0, 1.0)
          ..scaleByDouble(nextScale, nextScale, 1.0, 1.0);
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final delta = -event.scrollDelta.dy * 0.002;
    _setScale(_scale + delta);
  }

  // ── 动作 ────────────────────────────────────────────────────────────

  void _toggleSlideshow() {
    setState(() {
      _slideshow = !_slideshow;
    });
    if (_slideshow) {
      _slideProgress.forward(from: 0);
    } else {
      _slideProgress
        ..stop()
        ..reset();
    }
  }

  Future<void> _toggleFavorite(PhotoItem photo) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .toggleFavorite(photo.id, currentFavorite: photo.favorite);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      showDesktopToast(
        context,
        failureToast(l10n, l10n.photosFavorite, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

  Future<void> _moveToTrash(PhotoItem photo) async {
    final l10n = AppLocalizations.of(context);
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      await ref
          .read(photoCenterControllerProvider.notifier)
          .movePhotoToTrash(photo.id);
      if (!mounted) {
        return;
      }
      showDesktopToast(
        context,
        l10n.desktopPhotosMovedToTrash(1),
        icon: DesktopIcons.trash,
        actionLabel: l10n.desktopUndo,
        onAction: () => unawaited(_restoreFromTrash(container, photo.id, l10n)),
      );
      _close();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      showDesktopToast(
        context,
        failureToast(l10n, l10n.photosDelete, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

  Future<void> _restoreFromTrash(
    ProviderContainer container,
    String photoId,
    AppLocalizations l10n,
  ) async {
    try {
      await container
          .read(photoCenterControllerProvider.notifier)
          .restorePhotoFromTrash(photoId);
      container
          .read(desktopToastProvider.notifier)
          .show(l10n.photosTrashRestored, icon: DesktopIcons.check);
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

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_info) {
        setState(() => _info = false);
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete && !_shareOpen) {
      final photo = _currentPhoto();
      if (photo != null) {
        unawaited(_moveToTrash(photo));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI) {
      setState(() => _info = !_info);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add) {
      _setScale(_scale + 0.5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus) {
      _setScale(_scale - 0.5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      _toggleSlideshow();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  PhotoItem? _currentPhoto() {
    final detail = ref.read(photoDetailProvider(_currentId)).asData?.value;
    if (detail != null) {
      return detail;
    }
    final browseScope = ref.read(photoBrowseScopeProvider);
    if (browseScope.contains(_currentId)) {
      for (final item in browseScope.photos) {
        if (item.id == _currentId) {
          return item;
        }
      }
    }
    final items = ref.read(photoListProvider).asData?.value.items;
    if (items == null) {
      return null;
    }
    for (final item in items) {
      if (item.id == _currentId) {
        return item;
      }
    }
    return null;
  }
}

class _ViewerStage extends StatelessWidget {
  const _ViewerStage({
    required this.stageKey,
    required this.photo,
    required this.zoom,
    required this.rotation,
    required this.slideshow,
    required this.infoOpen,
    required this.onDismissInfo,
    required this.onDoubleTapDown,
    required this.onDoubleTap,
    required this.onWheel,
  });

  final GlobalKey stageKey;
  final PhotoItem photo;
  final TransformationController zoom;
  final double rotation;
  final bool slideshow;
  final bool infoOpen;
  final VoidCallback onDismissInfo;
  final ValueChanged<Offset> onDoubleTapDown;
  final VoidCallback onDoubleTap;
  final ValueChanged<PointerSignalEvent> onWheel;

  @override
  Widget build(BuildContext context) {
    final kenBurnsDuration = DesktopMotion.of(
      context,
      DesktopMotion.viewerKenBurns,
    );
    final animateKenBurns = slideshow && kenBurnsDuration != Duration.zero;
    final compact = MediaQuery.sizeOf(context).width <= 760;
    final basePadding =
        compact
            ? const EdgeInsets.fromLTRB(12, 68, 12, 84)
            : const EdgeInsets.fromLTRB(92, 72, 92, 92);
    final effectivePadding =
        infoOpen && !compact
            ? EdgeInsets.fromLTRB(
              basePadding.left,
              basePadding.top,
              350,
              basePadding.bottom,
            )
            : basePadding;
    return Positioned.fill(
      child: AnimatedPadding(
        duration: MotionToken.reduced(context, DesktopMotion.viewerStage),
        curve: DesktopMotion.ease,
        padding: effectivePadding,
        child: Listener(
          key: stageKey,
          onPointerSignal: onWheel,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: infoOpen ? onDismissInfo : null,
            onDoubleTapDown:
                (details) => onDoubleTapDown(details.localPosition),
            onDoubleTap: onDoubleTap,
            child: InteractiveViewer(
              transformationController: zoom,
              minScale: 1,
              maxScale: 5,
              child: TweenAnimationBuilder<double>(
                key: ValueKey<String>('${photo.id}-$slideshow'),
                tween: Tween<double>(begin: 0, end: animateKenBurns ? 1 : 0),
                duration: kenBurnsDuration,
                curve: DesktopMotion.easeOut,
                builder:
                    (context, progress, child) => Transform.scale(
                      scale: 1 + 0.14 * progress,
                      child: FractionalTranslation(
                        translation: Offset(
                          -0.015 * progress,
                          -0.01 * progress,
                        ),
                        child: child,
                      ),
                    ),
                child: Center(
                  child: AnimatedRotation(
                    turns: rotation / 360,
                    duration: DesktopMotion.of(context, DesktopMotion.fast),
                    curve: DesktopMotion.ease,
                    child: DesktopImage(
                      url: photo.coverUrl,
                      fit: BoxFit.contain,
                      fallbackIcon: DesktopIcons.image,
                      borderRadius: BorderRadius.circular(
                        DesktopMetrics.radiusSmall,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.photo,
    required this.index,
    required this.total,
    required this.info,
    required this.slideshow,
    required this.visible,
    required this.favorite,
    required this.onClose,
    required this.onToggleInfo,
    required this.onToggleSlideshow,
    required this.onRotate,
    required this.onToggleFavorite,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  final PhotoItem photo;
  final int index;
  final int total;
  final bool info;
  final bool slideshow;
  final bool visible;
  final bool favorite;
  final VoidCallback onClose;
  final VoidCallback onToggleInfo;
  final VoidCallback onToggleSlideshow;
  final VoidCallback onRotate;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: DesktopMotion.of(context, DesktopMotion.viewerChrome),
          child: SizedBox(
            height: 64,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DesktopWindowDragRegion(child: SizedBox.expand()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      DesktopIconButton(
                        icon: DesktopIcons.left,
                        size: 36,
                        iconSize: 18,
                        tooltip: l10n.photosClose,
                        onPressed: onClose,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: IgnorePointer(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _placeLabel(photo) ?? photo.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.cardTitle(skin.text),
                              ),
                              Text(
                                l10n.desktopPhotosIndex(index + 1, total),
                                style: DesktopType.caption(skin.text3),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DesktopIconButton(
                        icon:
                            slideshow ? DesktopIcons.pause : DesktopIcons.play,
                        size: 36,
                        iconSize: 17,
                        active: slideshow,
                        tooltip: l10n.photosSlideshow,
                        onPressed: onToggleSlideshow,
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.rotate,
                        size: 36,
                        iconSize: 18,
                        tooltip: l10n.photosRotate,
                        onPressed: onRotate,
                      ),
                      DesktopIconButton(
                        icon:
                            favorite
                                ? DesktopIcons.heartFilled
                                : DesktopIcons.heart,
                        size: 36,
                        iconSize: 18,
                        tooltip: l10n.photosFavorite,
                        onPressed: onToggleFavorite,
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.edit,
                        size: 36,
                        iconSize: 17,
                        tooltip: l10n.photosEdit,
                        onPressed: onEdit,
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.share,
                        size: 36,
                        iconSize: 17,
                        tooltip: l10n.filesShare,
                        onPressed: onShare,
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.trash,
                        size: 36,
                        iconSize: 17,
                        tooltip: l10n.photosDelete,
                        onPressed: onDelete,
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.info,
                        size: 36,
                        iconSize: 18,
                        active: info,
                        tooltip: l10n.desktopPhotosInfo,
                        onPressed: onToggleInfo,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.alignment,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Alignment alignment;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        // 样例 `.vw-nav`：52×52 圆钮、图标 26、左右各 20 边距。
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: DesktopIconButton(
          icon: icon,
          size: 52,
          iconSize: 26,
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.open,
    required this.photo,
    required this.scale,
    required this.onClose,
    required this.onZoom,
  });

  final bool open;
  final PhotoItem photo;
  final double scale;
  final VoidCallback onClose;
  final ValueChanged<double> onZoom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final exposure = [
      if (photo.aperture != null) photo.aperture!,
      if (photo.shutterSpeed != null) photo.shutterSpeed!,
      if (photo.iso != null) 'ISO ${photo.iso}',
      if (photo.focalLength != null) photo.focalLength!,
    ].join(' · ');
    final camera = [
      photo.cameraMake,
      photo.cameraModel,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
    final dimensions =
        photo.width != null && photo.height != null
            ? '${photo.width} × ${photo.height}'
            : '—';
    // 样例 `.vw-info`：浮在舞台上的圆角卡，顶栏之下（top 76）、胶片条之上
    // （bottom 96），宽 330，不挤压画面。
    return AnimatedPositioned(
      duration: DesktopMotion.of(context, DesktopMotion.pane),
      curve: DesktopMotion.ease,
      top: 76,
      bottom: 96,
      right: open ? 16 : -346,
      child: IgnorePointer(
        ignoring: !open,
        child: Container(
          width: 330,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
          decoration: BoxDecoration(
            color: skin.pop,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusLarge),
            border: Border.all(color: skin.line2),
            boxShadow: skin.shadow,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.desktopPhotosInfo.toUpperCase(),
                        style: DesktopType.eyebrow(skin.text3),
                      ),
                    ),
                    DesktopIconButton(
                      icon: DesktopIcons.close,
                      size: 28,
                      iconSize: 14,
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(photo.title, style: DesktopType.displaySm(skin.text)),
                const SizedBox(height: 16),
                DesktopKeyValues(
                  entries: [
                    if (photo.dateTaken != null)
                      MapEntry(
                        l10n.desktopPhotosTaken,
                        _formatDateTime(photo.dateTaken!),
                      ),
                    if (_placeLabel(photo) != null)
                      MapEntry(l10n.desktopPhotosLocation, _placeLabel(photo)!),
                    if (camera.isNotEmpty)
                      MapEntry(l10n.desktopPhotosCamera, camera),
                    if (exposure.isNotEmpty)
                      MapEntry(l10n.desktopPhotosExposure, exposure),
                    MapEntry(
                      l10n.desktopPhotosDimensions,
                      '$dimensions · ${formatFileSize(photo.fileSize)}',
                    ),
                  ],
                ),
                if (photo.tags.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    l10n.desktopPhotosTags.toUpperCase(),
                    style: DesktopType.eyebrow(skin.text3),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final tag in photo.tags) DesktopChip(tag)],
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  l10n.desktopPhotosZoom.toUpperCase(),
                  style: DesktopType.eyebrow(skin.text3),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    DesktopIconButton(
                      icon: DesktopIcons.zoomOut,
                      size: 28,
                      iconSize: 14,
                      onPressed: () => onZoom(scale - 0.5),
                    ),
                    Expanded(
                      child: DesktopSlider(
                        value: scale.clamp(1, 5),
                        max: 5,
                        onChanged: onZoom,
                      ),
                    ),
                    DesktopIconButton(
                      icon: DesktopIcons.zoomIn,
                      size: 28,
                      iconSize: 14,
                      onPressed: () => onZoom(scale + 0.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `gpsLocation` 是后端原样下发的地址字段集合，取第一个可读值。
String? _placeLabel(PhotoItem photo) {
  final location = photo.gpsLocation;
  if (location == null || location.isEmpty) {
    return null;
  }
  for (final key in const ['name', 'displayName', 'locality', 'city']) {
    final value = location[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
