import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/desktop/desktop_ambient_mesh.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 原子环境光场景帧：将 4×3 色网与可选右侧柔焦艺术面板打包为一个双缓冲单元。
@immutable
class _AmbientSceneFrame {
  const _AmbientSceneFrame({
    required this.id,
    required this.imageUrl,
    required this.showArt,
    required this.artPreset,
    required this.fallbackTone,
    required this.meshGrid,
  });

  final int id;
  final String? imageUrl;
  final bool showArt;
  final EditorialArtPreset artPreset;
  final Color? fallbackTone;
  final AmbientMeshGrid? meshGrid;

  bool get hasCover => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasMesh => hasCover || meshGrid != null || fallbackTone != null;
  bool get hasArt => hasCover && showArt;

  bool matchesSpec({
    required String? imageUrl,
    required bool showArt,
    required EditorialArtPreset artPreset,
    required Color? fallbackTone,
  }) {
    return this.imageUrl == imageUrl &&
        this.showArt == showArt &&
        this.artPreset == artPreset &&
        this.fallbackTone == fallbackTone;
  }

  _AmbientSceneFrame copyWith({AmbientMeshGrid? meshGrid}) {
    return _AmbientSceneFrame(
      id: id,
      imageUrl: imageUrl,
      showArt: showArt,
      artPreset: artPreset,
      fallbackTone: fallbackTone,
      meshGrid: meshGrid ?? this.meshGrid,
    );
  }
}

/// 桌面环境光层。
///
/// 四大独立重绘边界：
/// - `ambient-cover`：4×3 矢量色网双缓冲层（彻底废除 40s `_drift`）；
/// - `ambient-art`：右侧静态轻柔焦艺术面板双缓冲层（与色网同步 720ms 交叉淡入淡出）；
/// - `ambient-blobs`：三团事件驱动 2.4s 缓动色场，落位后自动停表（稳态 0fps GPU 唤醒）；
/// - `ambient-veil`：深浅色精细差异化暗纱与预烘焙 128×128 噪点瓦片。
class DesktopAmbient extends StatefulWidget {
  const DesktopAmbient({
    required this.imageUrl,
    required this.intensity,
    required this.reduceMotion,
    this.showArt = false,
    this.artPreset = EditorialArtPreset.landscape,
    this.fallbackTone,
    super.key,
  });

  final String? imageUrl;

  /// 0-100。
  final double intensity;
  final bool reduceMotion;

  /// 是否启用右侧静态轻柔焦编辑艺术面板。
  final bool showArt;

  /// 右侧艺术面板的构图与柔焦预设。
  final EditorialArtPreset artPreset;

  /// 无封面图时的兜底色调（如 Reader 无封面图书的纸色）。
  final Color? fallbackTone;

  @override
  State<DesktopAmbient> createState() => _DesktopAmbientState();
}

class _DesktopAmbientState extends State<DesktopAmbient>
    with TickerProviderStateMixin {
  /// 预烘焙噪点瓦片边长（128×128 离屏 ui.Image，进程级复用一次生成）。
  static const int _grainTileSize = 128;
  static const Duration _blobSettleDuration = Duration(milliseconds: 2400);
  static const Duration _sceneCrossfadeDuration = Duration(milliseconds: 720);

  static ui.Image? _grainImageCache;
  static Future<ui.Image>? _grainImageFuture;

  static Future<ui.Image> _ensureGrainImage() {
    final cached = _grainImageCache;
    if (cached != null) {
      return Future<ui.Image>.value(cached);
    }
    return _grainImageFuture ??= _bakeGrainImage().then((image) {
      _grainImageCache = image;
      return image;
    });
  }

  static Future<ui.Image> _bakeGrainImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final random = math.Random(20261114);
    final paint = Paint()..color = DesktopPalette.grain;
    const dotCount = 18;
    for (var i = 0; i < dotCount; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          random.nextDouble() * _grainTileSize,
          random.nextDouble() * _grainTileSize,
          1,
          1,
        ),
        paint,
      );
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(_grainTileSize, _grainTileSize);
    } finally {
      picture.dispose();
    }
  }

  // 三团色场改为事件驱动 2.4s 缓动：挂载、切页或换封面时平滑推到新相位并自动停表，
  // 稳态 0fps GPU 唤醒；窗口缩放时仅 stop() 保留当前相位不跳变。
  late final AnimationController _blobA = AnimationController(
    duration: _blobSettleDuration,
    value: 0.35,
    vsync: this,
  );
  late final AnimationController _blobB = AnimationController(
    duration: _blobSettleDuration,
    value: 0.62,
    vsync: this,
  );
  late final AnimationController _blobC = AnimationController(
    duration: _blobSettleDuration,
    value: 0.18,
    vsync: this,
  );

  // 双缓冲原子场景帧交叉淡入淡出控制器（720ms Curves.easeInOutCubic）。
  late final AnimationController _crossfade = AnimationController(
    duration: _sceneCrossfadeDuration,
    value: 1.0,
    vsync: this,
  );
  late final CurvedAnimation _crossfadeIn = CurvedAnimation(
    parent: _crossfade,
    curve: Curves.easeInOutCubic,
  );
  late final Animation<double> _crossfadeOut = Tween<double>(
    begin: 1.0,
    end: 0.0,
  ).animate(_crossfadeIn);

  Size? _lastSize;
  Timer? _resizeSettle;
  bool _resizing = false;
  int _sceneSeq = 0;
  int _prepareToken = 0;
  int _blobStep = 0;
  bool _initialScenePrepared = false;
  _AmbientSceneFrame? _activeFrame;
  _AmbientSceneFrame? _outgoingFrame;
  ui.Image? _grainImage = _grainImageCache;

  @override
  void initState() {
    super.initState();
    _crossfade.addStatusListener(_handleCrossfadeStatus);
    _seedInitialFrameSync();
    if (_grainImage == null) {
      unawaited(
        _ensureGrainImage().then((image) {
          if (mounted) {
            setState(() => _grainImage = image);
          }
        }),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    if (_lastSize != null && size != _lastSize) {
      _resizing = true;
      _pauseBlobsInPlace();
      _resizeSettle?.cancel();
      _resizeSettle = Timer(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        setState(() => _resizing = false);
      });
    }
    _lastSize = size;
    if (!_initialScenePrepared) {
      _initialScenePrepared = true;
      _prepareScene(isInitial: true);
      if (_canAnimate) {
        _triggerBlobSettle();
      }
    }
  }

  @override
  void didUpdateWidget(DesktopAmbient oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sceneChanged =
        oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.showArt != widget.showArt ||
        oldWidget.artPreset != widget.artPreset ||
        oldWidget.fallbackTone != widget.fallbackTone;

    if (!_canAnimate) {
      _pauseBlobsInPlace();
      if (_outgoingFrame != null || _crossfade.isAnimating) {
        _crossfade
          ..stop()
          ..value = 1.0;
        _outgoingFrame = null;
      }
    }

    if (sceneChanged) {
      _prepareScene(isInitial: false);
    } else if (!oldWidget.reduceMotion && widget.reduceMotion) {
      _pauseBlobsInPlace();
    } else if ((oldWidget.reduceMotion && !widget.reduceMotion) ||
        (oldWidget.intensity <= 0 && widget.intensity > 0)) {
      if (oldWidget.intensity <= 0 && widget.intensity > 0) {
        // 强度从 0 恢复：补跑一次场景准备，把被跳过的色网与艺术层补上。
        _prepareScene(isInitial: false);
      }
      if (_canAnimate) {
        _triggerBlobSettle();
      }
    }
  }

  bool get _canAnimate =>
      !_resizing &&
      !widget.reduceMotion &&
      !MotionToken.prefersReducedOnPlatform() &&
      widget.intensity > 0;

  void _handleCrossfadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _outgoingFrame != null &&
        mounted) {
      setState(() {
        _outgoingFrame = null;
      });
    }
  }

  /// 仅停止色场动画，严格保留当前相位不重置，避免缩放或停帧时突然跳回原点。
  void _pauseBlobsInPlace() {
    for (final controller in [_blobA, _blobB, _blobC]) {
      if (controller.isAnimating) {
        controller.stop();
      }
    }
  }

  /// 事件驱动 2.4s 缓动：每次挂载/切页/换封面推进三团色场到新相位后自动停表。
  void _triggerBlobSettle() {
    if (!_canAnimate) {
      _pauseBlobsInPlace();
      return;
    }
    _blobStep += 1;
    final targets = <double>[
      _nextBlobPhase(_blobA.value, 0.27 + (_blobStep % 3) * 0.04),
      _nextBlobPhase(_blobB.value, 0.31 + ((_blobStep + 1) % 3) * 0.05),
      _nextBlobPhase(_blobC.value, 0.23 + ((_blobStep + 2) % 3) * 0.04),
    ];
    final controllers = <AnimationController>[_blobA, _blobB, _blobC];
    for (var i = 0; i < controllers.length; i++) {
      unawaited(
        controllers[i].animateTo(
          targets[i],
          duration: _blobSettleDuration,
          curve: Curves.easeInOutCubic,
        ),
      );
    }
  }

  static double _nextBlobPhase(double current, double delta) {
    final shifted = (current - 0.08 + delta) % 0.84;
    return (0.08 + shifted).clamp(0.08, 0.92);
  }

  /// 首帧同步建立初始 `_activeFrame`，确保首帧即挂载有效节点且无白闪。
  void _seedInitialFrameSync() {
    final source = widget.imageUrl;
    final hasCover = source != null && source.isNotEmpty;
    AmbientMeshGrid? grid;
    if (hasCover) {
      grid = DesktopAmbientMeshCache.instance.peek(source);
    } else if (widget.fallbackTone != null) {
      grid = AmbientMeshGrid.fromTone(widget.fallbackTone!);
    }
    _activeFrame = _AmbientSceneFrame(
      id: ++_sceneSeq,
      imageUrl: hasCover ? source : null,
      showArt: widget.showArt,
      artPreset: widget.artPreset,
      fallbackTone: widget.fallbackTone,
      meshGrid: grid,
    );
  }

  /// 后台并行采样色网 + 预解码艺术面板（220ms 软超时），就绪后原子切换双缓冲。
  void _prepareScene({required bool isInitial}) {
    // 强度为 0 时整层不构建：跳过色网采样与艺术层预解码，避免无谓的网络请求。
    if (widget.intensity <= 0) {
      return;
    }
    final token = ++_prepareToken;
    final rawUrl = widget.imageUrl;
    final source = (rawUrl != null && rawUrl.isNotEmpty) ? rawUrl : null;
    final showArt = widget.showArt;
    final artPreset = widget.artPreset;
    final fallbackTone = widget.fallbackTone;

    // 纯纸色或无封面：同步落帧，不等待异步 I/O。
    if (source == null) {
      final grid =
          fallbackTone != null ? AmbientMeshGrid.fromTone(fallbackTone) : null;
      if (isInitial && _activeFrame != null) {
        if (_activeFrame!.meshGrid != grid) {
          setState(() => _activeFrame = _activeFrame!.copyWith(meshGrid: grid));
        }
        return;
      }
      _commitScene(
        _AmbientSceneFrame(
          id: ++_sceneSeq,
          imageUrl: null,
          showArt: false,
          artPreset: artPreset,
          fallbackTone: fallbackTone,
          meshGrid: grid,
        ),
      );
      return;
    }

    final cachedGrid = DesktopAmbientMeshCache.instance.peek(source);
    if (isInitial) {
      // 首帧已命中色网缓存且不需等艺术预热时直接完成；否则后台补齐色网不闪黑。
      if (cachedGrid != null && !showArt) {
        return;
      }
      unawaited(
        resolveAmbientSceneAssets(
          context: context,
          source: source,
          showArt: showArt,
          artPreset: artPreset,
          cachedGrid: cachedGrid,
        ).then((grid) {
          if (!mounted || token != _prepareToken) return;
          final current = _activeFrame;
          if (current == null ||
              !current.matchesSpec(
                imageUrl: source,
                showArt: showArt,
                artPreset: artPreset,
                fallbackTone: fallbackTone,
              )) {
            return;
          }
          if (grid != null && current.meshGrid != grid) {
            setState(() {
              _activeFrame = current.copyWith(meshGrid: grid);
            });
          }
        }),
      );
      return;
    }

    // 切页 / 换图：保持旧帧稳定可见，后台并行采样 + precacheImage（220ms 软超时）。
    unawaited(
      resolveAmbientSceneAssets(
        context: context,
        source: source,
        showArt: showArt,
        artPreset: artPreset,
        cachedGrid: cachedGrid,
      ).then((grid) {
        if (!mounted || token != _prepareToken) return;
        final effectiveGrid =
            grid ??
            DesktopAmbientMeshCache.instance.peek(source) ??
            (fallbackTone != null
                ? AmbientMeshGrid.fromTone(fallbackTone)
                : null);
        _commitScene(
          _AmbientSceneFrame(
            id: ++_sceneSeq,
            imageUrl: source,
            showArt: showArt,
            artPreset: artPreset,
            fallbackTone: fallbackTone,
            meshGrid: effectiveGrid,
          ),
        );
      }),
    );
  }

  void _commitScene(_AmbientSceneFrame nextFrame) {
    if (!mounted) return;
    final previous = _activeFrame;
    if (previous != null &&
        previous.matchesSpec(
          imageUrl: nextFrame.imageUrl,
          showArt: nextFrame.showArt,
          artPreset: nextFrame.artPreset,
          fallbackTone: nextFrame.fallbackTone,
        ) &&
        previous.meshGrid == nextFrame.meshGrid) {
      return;
    }

    if (!_canAnimate || previous == null) {
      setState(() {
        _outgoingFrame = null;
        _activeFrame = nextFrame;
        _crossfade
          ..stop()
          ..value = 1.0;
      });
      return;
    }

    setState(() {
      // 严格最多 2 层双缓冲：新帧切入时丢弃更早的旧帧，彻底消灭连点堆叠。
      _outgoingFrame = previous;
      _activeFrame = nextFrame;
    });
    _crossfade.forward(from: 0.0);
    _triggerBlobSettle();
  }

  @override
  void dispose() {
    _resizeSettle?.cancel();
    _crossfade.removeStatusListener(_handleCrossfadeStatus);
    _crossfadeIn.dispose();
    _crossfade.dispose();
    _blobA.dispose();
    _blobB.dispose();
    _blobC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.intensity <= 0) {
      return const SizedBox.shrink();
    }
    final skin = DesktopSkin.of(context);
    final profile = AmbientThemeProfile.of(isDark: skin.isDark);
    final targetIntensity = (widget.intensity / 100).clamp(0.0, 1.0);
    final viewport = MediaQuery.sizeOf(context);
    final unit = math.max(viewport.width, viewport.height);
    final activeFrame = _activeFrame;
    final outgoingFrame = _outgoingFrame;
    final showCoverLayer =
        (activeFrame?.hasMesh ?? false) || (outgoingFrame?.hasMesh ?? false);
    final showArtLayer =
        (activeFrame?.hasArt ?? false) || (outgoingFrame?.hasArt ?? false);

    return ExcludeSemantics(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: targetIntensity),
          duration: DesktopMotion.ambientLayer,
          curve: Curves.ease,
          builder: (context, intensityFactor, _) {
            if (intensityFactor <= 0.001) {
              return const SizedBox.shrink();
            }
            final veilOpacity = (profile.veilOpacity * intensityFactor).clamp(
              0.0,
              1.0,
            );
            final veilColor = skin.veil.withValues(
              alpha: (skin.veil.a * veilOpacity).clamp(0.0, 1.0),
            );
            final linearVeilColor = veilColor.withValues(
              alpha: (veilColor.a * profile.linearFactor).clamp(0.0, 1.0),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                // 边界 1：4×3 矢量色网双缓冲层（彻底废除 40s _drift 晃动）。
                if (showCoverLayer)
                  RepaintBoundary(
                    key: const ValueKey('ambient-cover'),
                    child: _buildDualBufferMesh(
                      skin: skin,
                      profile: profile,
                      intensityFactor: intensityFactor,
                      active: activeFrame,
                      outgoing: outgoingFrame,
                    ),
                  ),
                // 边界 2：右侧静态轻柔焦艺术面板双缓冲层（与色网同步 720ms 过渡）。
                if (showArtLayer)
                  RepaintBoundary(
                    key: const ValueKey('ambient-art'),
                    child: _buildDualBufferArt(
                      skin: skin,
                      profile: profile,
                      intensityFactor: intensityFactor,
                      active: activeFrame,
                      outgoing: outgoingFrame,
                    ),
                  ),
                // 边界 3：三团事件驱动 2.4s 缓动色场，落位停表 0fps GPU 唤醒。
                RepaintBoundary(
                  key: const ValueKey('ambient-blobs'),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _blobLayer(
                        controller: _blobA,
                        base: Offset(viewport.width * 0.06, -unit * 0.12),
                        radius: unit * 0.52,
                        color: skin.accent,
                        alpha: (skin.isDark ? 0.25 : 0.16) * intensityFactor,
                        size: viewport,
                        unit: unit,
                      ),
                      _blobLayer(
                        controller: _blobB,
                        base: Offset(
                          viewport.width * 0.96,
                          viewport.height * 1.04,
                        ),
                        radius: unit * 0.50,
                        color: skin.warm,
                        alpha: (skin.isDark ? 0.14 : 0.10) * intensityFactor,
                        size: viewport,
                        unit: unit,
                      ),
                      _blobLayer(
                        controller: _blobC,
                        base: Offset(
                          viewport.width * 0.52,
                          viewport.height * 0.55,
                        ),
                        radius: unit * 0.34,
                        color: DesktopPalette.ambientCool,
                        alpha: (skin.isDark ? 0.12 : 0.08) * intensityFactor,
                        size: viewport,
                        unit: unit,
                      ),
                    ],
                  ),
                ),
                // 边界 4：深浅色精细差异化暗纱 + 预烘焙 128×128 噪点瓦片。
                RepaintBoundary(
                  key: const ValueKey('ambient-veil'),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: linearVeilColor),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.topCenter,
                            radius: 1.25,
                            colors: [Colors.transparent, veilColor],
                            stops: profile.radialStops,
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: _GrainPainter(
                          image: _grainImage,
                          opacity: veilOpacity,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDualBufferMesh({
    required DesktopSkin skin,
    required AmbientThemeProfile profile,
    required double intensityFactor,
    required _AmbientSceneFrame? active,
    required _AmbientSceneFrame? outgoing,
  }) {
    final layers = <Widget>[];
    if (outgoing != null && outgoing.hasMesh) {
      layers.add(
        FadeTransition(
          key: ValueKey<int>(outgoing.id),
          opacity: _crossfadeOut,
          alwaysIncludeSemantics: true,
          child: RepaintBoundary(
            child: _meshFrameWidget(
              skin: skin,
              profile: profile,
              intensityFactor: intensityFactor,
              frame: outgoing,
            ),
          ),
        ),
      );
    }
    if (active != null && active.hasMesh) {
      final child = RepaintBoundary(
        child: _meshFrameWidget(
          skin: skin,
          profile: profile,
          intensityFactor: intensityFactor,
          frame: active,
        ),
      );
      layers.add(
        outgoing != null
            ? FadeTransition(
              key: ValueKey<int>(active.id),
              opacity: _crossfadeIn,
              alwaysIncludeSemantics: true,
              child: child,
            )
            : KeyedSubtree(key: ValueKey<int>(active.id), child: child),
      );
    }
    if (layers.isEmpty) {
      return const SizedBox.shrink();
    }
    if (layers.length == 1) {
      return layers.first;
    }
    return Stack(fit: StackFit.expand, children: layers);
  }

  Widget _meshFrameWidget({
    required DesktopSkin skin,
    required AmbientThemeProfile profile,
    required double intensityFactor,
    required _AmbientSceneFrame frame,
  }) {
    final meshAlpha = (profile.meshAlpha * intensityFactor).clamp(0.0, 1.0);
    return DesktopAmbientMeshSurface(
      source: frame.imageUrl ?? '',
      preloadedGrid: frame.meshGrid,
      opacity: meshAlpha,
      saturation: profile.meshSat,
      brightness: profile.meshBright,
      fallbackColor:
          frame.fallbackTone?.withValues(alpha: meshAlpha) ??
          Colors.transparent,
      washColor: profile.lightWash > 0 ? skin.bg : null,
      washOpacity: profile.lightWash,
    );
  }

  Widget _buildDualBufferArt({
    required DesktopSkin skin,
    required AmbientThemeProfile profile,
    required double intensityFactor,
    required _AmbientSceneFrame? active,
    required _AmbientSceneFrame? outgoing,
  }) {
    final layers = <Widget>[];
    if (outgoing != null && outgoing.hasArt) {
      layers.add(
        FadeTransition(
          key: ValueKey<int>(outgoing.id),
          opacity: _crossfadeOut,
          alwaysIncludeSemantics: true,
          child: EditorialArtPanel(
            source: outgoing.imageUrl!,
            isDark: skin.isDark,
            intensityFactor: intensityFactor,
            preset: outgoing.artPreset,
            profile: profile,
          ),
        ),
      );
    }
    if (active != null && active.hasArt) {
      final panel = EditorialArtPanel(
        source: active.imageUrl!,
        isDark: skin.isDark,
        intensityFactor: intensityFactor,
        preset: active.artPreset,
        profile: profile,
      );
      layers.add(
        outgoing != null
            ? FadeTransition(
              key: ValueKey<int>(active.id),
              opacity: _crossfadeIn,
              alwaysIncludeSemantics: true,
              child: panel,
            )
            : KeyedSubtree(key: ValueKey<int>(active.id), child: panel),
      );
    }
    if (layers.isEmpty) {
      return const SizedBox.shrink();
    }
    if (layers.length == 1) {
      return layers.first;
    }
    return Stack(fit: StackFit.expand, children: layers);
  }

  Widget _blobLayer({
    required AnimationController controller,
    required Offset base,
    required double radius,
    required Color color,
    required double alpha,
    required Size size,
    required double unit,
  }) {
    final alignment = Alignment(
      base.dx / size.width * 2 - 1,
      base.dy / size.height * 2 - 1,
    );
    return AnimatedBuilder(
      animation: controller,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BlobBasePainter(
            center: base,
            radius: radius,
            color: color,
            alpha: alpha,
          ),
          child: const SizedBox.expand(),
        ),
      ),
      builder: (context, child) {
        final a = Curves.easeInOut.transform(controller.value.clamp(0.0, 1.0));
        final s = (radius + 0.2 * a * unit) / radius;
        return Transform(
          alignment: alignment,
          transform:
              Matrix4.identity()
                ..translateByDouble(a * unit * 0.08, a * unit * 0.06, 0, 1)
                ..scaleByDouble(s, s, s, 1),
          child: child,
        );
      },
    );
  }
}

/// 单团色光的静态基帧：一圈径向渐变，位置/半径/配色不变时不重录。
class _BlobBasePainter extends CustomPainter {
  const _BlobBasePainter({
    required this.center,
    required this.radius,
    required this.color,
    required this.alpha,
  });

  final Offset center;
  final double radius;
  final Color color;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
          stops: const [0.0, 0.68],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_BlobBasePainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.radius != radius ||
      oldDelegate.color != color ||
      oldDelegate.alpha != alpha;
}

/// 预烘焙 128×128 离屏噪点瓦片 + ImageShader 平铺，单次 drawRect 完成绘制。
class _GrainPainter extends CustomPainter {
  const _GrainPainter({required this.image, required this.opacity});

  final ui.Image? image;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final tile = image;
    if (tile == null || size.isEmpty || opacity <= 0) {
      return;
    }
    final paint =
        Paint()
          ..shader = ui.ImageShader(
            tile,
            ui.TileMode.repeated,
            ui.TileMode.repeated,
            Matrix4.identity().storage,
          );
    if (opacity < 1.0) {
      paint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    }
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) =>
      !identical(oldDelegate.image, image) || oldDelegate.opacity != opacity;
}
