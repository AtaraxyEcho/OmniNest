import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/features/photos/application/photo_display_order_controller.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_panel.dart';

part 'desktop_photo_viewer_filmstrip.dart';

/// 桌面照片查看器（样例 `PhotoViewer`）：压暗背景 + 顶栏 + 左右翻页 +
/// 缩放/旋转舞台 + 底部胶片条 + 右侧信息面板 + 幻灯片自动播放。
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

class _DesktopPhotoViewerPageState
    extends ConsumerState<DesktopPhotoViewerPage> {
  static const Duration _slideInterval = Duration(milliseconds: 3800);

  final TransformationController _zoom = TransformationController();
  final FocusNode _focus = FocusNode(debugLabel: 'desktop-photo-viewer');

  late String _currentId = widget.photoId;
  double _rotation = 0;
  double _scale = 1;
  bool _info = false;
  bool _slideshow = false;
  bool _pointerInsideViewer = false;
  bool _shareOpen = false;
  bool _loadingMoreBrowsePhotos = false;
  Timer? _slideTimer;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_syncScale);
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _zoom
      ..removeListener(_syncScale)
      ..dispose();
    _focus.dispose();
    super.dispose();
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

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, event) => _onKey(event),
      child: MouseRegion(
        onEnter: (_) => _setPointerInsideViewer(true),
        onExit: (_) => _setPointerInsideViewer(false),
        child: ColoredBox(
          color: const Color(0xFF07090B),
          child: Stack(
            children: [
              // 背景：模糊放大的同一张图，压暗后作为环境光。
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.5,
                    child: ImageFiltered(
                      imageFilter: desktopGlassFilter(
                        blur: 46,
                        saturation: 1.5,
                        brightness: 0.8,
                      ),
                      child: DesktopImage(url: photo?.coverUrl),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF07090B).withValues(alpha: 0.55),
                        const Color(0xFF07090B).withValues(alpha: 0.2),
                        const Color(0xFF07090B).withValues(alpha: 0.82),
                      ],
                    ),
                  ),
                ),
              ),
              if (photo == null)
                const Center(child: SizedBox(width: 32, height: 32))
              else ...[
                _ViewerStage(
                  photo: photo,
                  zoom: _zoom,
                  rotation: _rotation,
                  slideshow: _slideshow,
                  onDoubleTap: _toggleZoom,
                  onWheel: _onWheel,
                ),
                _TopBar(
                  photo: photo,
                  index: index,
                  total: list.length,
                  info: _info,
                  slideshow: _slideshow,
                  visible: !_slideshow || _pointerInsideViewer,
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
                if (list.length > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: IgnorePointer(
                      ignoring: _slideshow && !_pointerInsideViewer,
                      child: AnimatedOpacity(
                        opacity: !_slideshow || _pointerInsideViewer ? 1 : 0,
                        duration: DesktopMotion.of(
                          context,
                          DesktopMotion.viewerChrome,
                        ),
                        child: _Filmstrip(
                          photos: list,
                          currentId: photo.id,
                          onPick: (id) => _select(id),
                        ),
                      ),
                    ),
                  ),
                if (_slideshow)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey<String>(photo.id),
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: _slideInterval,
                      builder:
                          (context, value, _) => LinearProgressIndicator(
                            value: value,
                            minHeight: 2,
                            backgroundColor: Colors.transparent,
                            color: skin.accent,
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
  }

  void _close() {
    _slideTimer?.cancel();
    // 覆盖层只 push 不 go：直接 go 会把来路换成照片页，系统返回即退出应用。
    exitDetailRoute(context, fallbackRoute: '/photos');
  }

  // ── 缩放 ────────────────────────────────────────────────────────────

  void _toggleZoom() {
    if (_scale > 1.05) {
      _zoom.value = Matrix4.identity();
      return;
    }
    _setScale(2.4);
  }

  void _setScale(double value) {
    final clamped = value.clamp(1.0, 5.0);
    _zoom.value = Matrix4.diagonal3Values(clamped, clamped, 1);
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
      _slideTimer?.cancel();
      if (_slideshow) {
        _slideTimer = Timer.periodic(_slideInterval, (_) => _step(1));
      }
    });
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
    required this.photo,
    required this.zoom,
    required this.rotation,
    required this.slideshow,
    required this.onDoubleTap,
    required this.onWheel,
  });

  final PhotoItem photo;
  final TransformationController zoom;
  final double rotation;
  final bool slideshow;
  final VoidCallback onDoubleTap;
  final ValueChanged<PointerSignalEvent> onWheel;

  @override
  Widget build(BuildContext context) {
    final kenBurnsDuration = DesktopMotion.of(
      context,
      DesktopMotion.viewerKenBurns,
    );
    final animateKenBurns = slideshow && kenBurnsDuration != Duration.zero;
    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(72, 78, 72, 108),
        child: Listener(
          onPointerSignal: onWheel,
          child: GestureDetector(
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
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
                  child: Column(
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
                DesktopIconButton(
                  icon: slideshow ? DesktopIcons.pause : DesktopIcons.play,
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
                      favorite ? DesktopIcons.heartFilled : DesktopIcons.heart,
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
