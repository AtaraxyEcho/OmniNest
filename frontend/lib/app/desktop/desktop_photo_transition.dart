import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 照片卡片在窗口坐标系中的实时锚点快照，供查看器进出过渡展开/收起。
@immutable
class DesktopPhotoAnchorSnapshot {
  const DesktopPhotoAnchorSnapshot({
    required this.rect,
    required this.coverUrl,
    required this.aspectRatio,
    required this.borderRadius,
  });

  final Rect rect;
  final String? coverUrl;
  final double aspectRatio;
  final double borderRadius;
}

/// 照片查看器当前舞台状态快照，供退出过渡时定位当前图片并缩回对应卡片。
@immutable
class DesktopPhotoViewerStageSnapshot {
  const DesktopPhotoViewerStageSnapshot({
    required this.photoId,
    required this.coverUrl,
    required this.aspectRatio,
    required this.infoOpen,
    required this.canFlyBack,
    this.imageKey,
  });

  final String photoId;
  final String? coverUrl;
  final double? aspectRatio;
  final bool infoOpen;
  final bool canFlyBack;
  final GlobalKey? imageKey;
}

class _PhotoAnchorEntry {
  _PhotoAnchorEntry({
    required this.photoId,
    required this.context,
    required this.coverUrl,
    required this.aspectRatio,
    required this.borderRadius,
  });

  String photoId;
  final BuildContext context;
  String? coverUrl;
  double? aspectRatio;
  double borderRadius;
}

/// 桌面端照片墙与全窗查看器之间的跨 Navigator 锚点注册表。
///
/// 桌面端工作区位于内层 `ShellRoute` Navigator，而 `/photos/:photoId` 推在
/// 根 Navigator 上以保持照片墙零卸载与滚动位置不丢失；Flutter 原生 `Hero`
/// 无法跨 Navigator 飞行，因此通过本注册表在进出过渡期间读取源卡片与舞台的
/// 实时全局矩形，实现「点击放大展开、退出缩回原图」的共享元素过渡。
class DesktopPhotoTransitionRegistry {
  DesktopPhotoTransitionRegistry._();

  static final DesktopPhotoTransitionRegistry instance =
      DesktopPhotoTransitionRegistry._();

  final Map<String, List<_PhotoAnchorEntry>> _anchors =
      <String, List<_PhotoAnchorEntry>>{};
  Object? _viewerOwner;
  DesktopPhotoViewerStageSnapshot? _viewerStage;

  DesktopPhotoViewerStageSnapshot? get viewerStage => _viewerStage;

  void _register(_PhotoAnchorEntry entry) {
    final bucket = _anchors.putIfAbsent(
      entry.photoId,
      () => <_PhotoAnchorEntry>[],
    );
    if (!bucket.contains(entry)) {
      bucket.add(entry);
    }
  }

  void _unregister(_PhotoAnchorEntry entry) {
    final bucket = _anchors[entry.photoId];
    if (bucket == null) return;
    bucket.remove(entry);
    if (bucket.isEmpty) {
      _anchors.remove(entry.photoId);
    }
  }

  /// 查询指定照片在当前视口内可见的源卡片全局矩形。
  DesktopPhotoAnchorSnapshot? resolveAnchor(String photoId, {Rect? viewport}) {
    final bucket = _anchors[photoId];
    if (bucket == null || bucket.isEmpty) {
      return null;
    }
    for (var i = bucket.length - 1; i >= 0; i--) {
      final entry = bucket[i];
      if (!entry.context.mounted) {
        continue;
      }
      final renderObject = entry.context.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize ||
          renderObject.size.isEmpty) {
        continue;
      }
      final topLeft = renderObject.localToGlobal(Offset.zero);
      final rect = topLeft & renderObject.size;
      if (!rect.isFinite || rect.width < 4 || rect.height < 4) {
        continue;
      }
      if (viewport != null && !rect.overlaps(viewport)) {
        continue;
      }
      final ratio =
          (entry.aspectRatio != null && entry.aspectRatio! > 0)
              ? entry.aspectRatio!
              : (rect.width / rect.height);
      return DesktopPhotoAnchorSnapshot(
        rect: rect,
        coverUrl: entry.coverUrl,
        aspectRatio: ratio,
        borderRadius: entry.borderRadius,
      );
    }
    return null;
  }

  /// 由查看器同步当前正在展示的照片与舞台状态，保证翻页后退出也能缩回当前照片。
  void updateViewerStage(
    Object owner,
    DesktopPhotoViewerStageSnapshot snapshot,
  ) {
    _viewerOwner = owner;
    _viewerStage = snapshot;
  }

  /// 查看器卸载时释放自身登记的舞台快照。
  void clearViewerStage(Object owner) {
    if (identical(_viewerOwner, owner)) {
      _viewerOwner = null;
      _viewerStage = null;
    }
  }

  /// 读取查看器舞台图片的实时全局矩形，保证退出动画从像素对齐的位置起步。
  Rect? resolveViewerImageRect() {
    final key = _viewerStage?.imageKey;
    final context = key?.currentContext;
    if (context == null || !context.mounted) {
      return null;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize ||
        renderObject.size.isEmpty) {
      return null;
    }
    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    if (!rect.isFinite || rect.width < 4 || rect.height < 4) {
      return null;
    }
    return rect;
  }

  /// 按与 `_ViewerStage` 一致的留白与 `BoxFit.contain` 规则推算目标落点矩形。
  static Rect computeViewerTargetRect(
    Size viewportSize, {
    required double aspectRatio,
    required bool infoOpen,
  }) {
    final compact = viewportSize.width <= 760;
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
    final stageRect = effectivePadding.deflateRect(Offset.zero & viewportSize);
    if (stageRect.width <= 0 || stageRect.height <= 0) {
      return Offset.zero & viewportSize;
    }
    final safeRatio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1;
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(safeRatio.toDouble(), 1),
      stageRect.size,
    );
    return Alignment.center.inscribe(fitted.destination, stageRect);
  }

  @visibleForTesting
  void reset() {
    _anchors.clear();
    _viewerOwner = null;
    _viewerStage = null;
  }
}

/// 照片墙卡片锚点包装：挂载期间向 [DesktopPhotoTransitionRegistry] 登记当前卡片。
class DesktopPhotoAnchor extends StatefulWidget {
  const DesktopPhotoAnchor({
    required this.photo,
    required this.borderRadius,
    required this.child,
    super.key,
  });

  final PhotoItem photo;
  final double borderRadius;
  final Widget child;

  @override
  State<DesktopPhotoAnchor> createState() => _DesktopPhotoAnchorState();
}

class _DesktopPhotoAnchorState extends State<DesktopPhotoAnchor> {
  _PhotoAnchorEntry? _entry;

  double? _aspectRatioOf(PhotoItem photo) {
    final width = photo.width;
    final height = photo.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final entry = _PhotoAnchorEntry(
      photoId: widget.photo.id,
      context: context,
      coverUrl: widget.photo.coverUrl,
      aspectRatio: _aspectRatioOf(widget.photo),
      borderRadius: widget.borderRadius,
    );
    _entry = entry;
    DesktopPhotoTransitionRegistry.instance._register(entry);
  }

  @override
  void didUpdateWidget(covariant DesktopPhotoAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final entry = _entry;
    if (entry == null) return;
    if (oldWidget.photo.id != widget.photo.id) {
      DesktopPhotoTransitionRegistry.instance._unregister(entry);
      entry.photoId = widget.photo.id;
      DesktopPhotoTransitionRegistry.instance._register(entry);
    }
    entry
      ..coverUrl = widget.photo.coverUrl
      ..aspectRatio = _aspectRatioOf(widget.photo)
      ..borderRadius = widget.borderRadius;
  }

  @override
  void dispose() {
    final entry = _entry;
    if (entry != null) {
      DesktopPhotoTransitionRegistry.instance._unregister(entry);
      _entry = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 过渡飞行状态作用域：飞行期间临时隐藏查看器舞台中的静止照片，避免重影。
class DesktopPhotoTransitionFlightScope extends InheritedWidget {
  const DesktopPhotoTransitionFlightScope({
    required this.hideStageImage,
    required super.child,
    super.key,
  });

  final bool hideStageImage;

  static bool shouldHideStageImage(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<
              DesktopPhotoTransitionFlightScope
            >()
            ?.hideStageImage ??
        false;
  }

  @override
  bool updateShouldNotify(DesktopPhotoTransitionFlightScope oldWidget) =>
      oldWidget.hideStageImage != hideStageImage;
}

/// 桌面照片查看器进出过渡包装：有源卡片锚点时从源矩形放大展开、退出缩回原卡片；
/// 无源锚点（直达深链、查看器翻页至屏外或缩放/旋转状态）时回退为居中缩放淡入淡出。
class DesktopPhotoViewerTransition extends StatefulWidget {
  const DesktopPhotoViewerTransition({
    required this.initialPhotoId,
    required this.animation,
    required this.child,
    super.key,
  });

  final String initialPhotoId;
  final Animation<double> animation;
  final Widget child;

  @override
  State<DesktopPhotoViewerTransition> createState() =>
      _DesktopPhotoViewerTransitionState();
}

class _DesktopPhotoViewerTransitionState
    extends State<DesktopPhotoViewerTransition> {
  static const double _fallbackMinScale = 0.88;

  AnimationStatus? _latchedStatus;
  DesktopPhotoAnchorSnapshot? _flightSource;
  Rect? _flightTarget;
  String? _flightPhotoId;
  String? _flightCoverUrl;

  void _syncFlightPlan(Size viewportSize) {
    final status = widget.animation.status;
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      _latchedStatus = status;
      _flightSource = null;
      _flightTarget = null;
      _flightPhotoId = null;
      _flightCoverUrl = null;
      return;
    }
    if (_latchedStatus == status) {
      return;
    }
    _latchedStatus = status;
    final viewport = Offset.zero & viewportSize;
    final registry = DesktopPhotoTransitionRegistry.instance;

    if (status == AnimationStatus.forward) {
      final anchor = registry.resolveAnchor(
        widget.initialPhotoId,
        viewport: viewport,
      );
      final coverUrl = anchor?.coverUrl;
      if (anchor != null && coverUrl != null && coverUrl.isNotEmpty) {
        _flightSource = anchor;
        _flightPhotoId = widget.initialPhotoId;
        _flightCoverUrl = coverUrl;
        _flightTarget = DesktopPhotoTransitionRegistry.computeViewerTargetRect(
          viewportSize,
          aspectRatio: anchor.aspectRatio,
          infoOpen: false,
        );
      } else {
        _flightSource = null;
        _flightTarget = null;
        _flightPhotoId = null;
        _flightCoverUrl = null;
      }
      return;
    }

    if (status == AnimationStatus.reverse) {
      final stage = registry.viewerStage;
      if (stage != null && !stage.canFlyBack) {
        _flightSource = null;
        _flightTarget = null;
        _flightPhotoId = null;
        _flightCoverUrl = null;
        return;
      }
      final targetPhotoId = stage?.photoId ?? widget.initialPhotoId;
      final anchor = registry.resolveAnchor(targetPhotoId, viewport: viewport);
      final coverUrl = stage?.coverUrl ?? anchor?.coverUrl;
      if (anchor != null && coverUrl != null && coverUrl.isNotEmpty) {
        _flightSource = anchor;
        _flightPhotoId = targetPhotoId;
        _flightCoverUrl = coverUrl;
        _flightTarget =
            registry.resolveViewerImageRect() ??
            DesktopPhotoTransitionRegistry.computeViewerTargetRect(
              viewportSize,
              aspectRatio: stage?.aspectRatio ?? anchor.aspectRatio,
              infoOpen: stage?.infoOpen ?? false,
            );
      } else {
        _flightSource = null;
        _flightTarget = null;
        _flightPhotoId = null;
        _flightCoverUrl = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return widget.child;
    }
    final viewportSize = MediaQuery.sizeOf(context);
    return AnimatedBuilder(
      animation: widget.animation,
      child: widget.child,
      builder: (context, child) {
        final rawT = widget.animation.value.clamp(0.0, 1.0);
        final status = widget.animation.status;
        if (status == AnimationStatus.completed) {
          _syncFlightPlan(viewportSize);
          return DesktopPhotoTransitionFlightScope(
            hideStageImage: false,
            child: child!,
          );
        }

        _syncFlightPlan(viewportSize);
        final isReverse =
            status == AnimationStatus.reverse ||
            status == AnimationStatus.dismissed;
        final curvedT =
            isReverse
                ? (1.0 - DesktopMotion.ease.transform(1.0 - rawT)).clamp(
                  0.0,
                  1.0,
                )
                : DesktopMotion.ease.transform(rawT).clamp(0.0, 1.0);

        final source = _flightSource;
        final target = _flightTarget;
        final coverUrl = _flightCoverUrl;
        if (source == null || target == null || coverUrl == null) {
          final scale = ui.lerpDouble(_fallbackMinScale, 1.0, curvedT)!;
          return DesktopPhotoTransitionFlightScope(
            hideStageImage: false,
            child: Opacity(
              opacity: curvedT,
              alwaysIncludeSemantics: true,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: child!,
              ),
            ),
          );
        }

        final viewerOpacity =
            isReverse
                ? Curves.easeIn.transform(rawT).clamp(0.0, 1.0)
                : Curves.easeOut.transform(rawT).clamp(0.0, 1.0);
        final flightRect = Rect.lerp(source.rect, target, curvedT)!;
        final flightRadius =
            ui.lerpDouble(
              source.borderRadius,
              DesktopMetrics.radiusSmall,
              curvedT,
            )!;

        return Stack(
          fit: StackFit.expand,
          children: [
            DesktopPhotoTransitionFlightScope(
              hideStageImage: true,
              child: Opacity(
                opacity: viewerOpacity,
                alwaysIncludeSemantics: true,
                child: child!,
              ),
            ),
            Positioned.fromRect(
              rect: flightRect,
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    key: const ValueKey<String>('desktop-photo-flight-card'),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(flightRadius),
                      child: DesktopCover(
                        url: coverUrl,
                        kind: DesktopCoverKind.network,
                        fallbackIcon: DesktopIcons.image,
                        cacheKey: 'desktop-photo-${_flightPhotoId ?? ''}',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
