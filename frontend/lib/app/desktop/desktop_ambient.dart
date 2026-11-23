import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/desktop/desktop_ambient_mesh.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 原子环境光场景帧：将 4×3 色网与可选全出血艺术层打包为一个双缓冲单元。
@immutable
class _AmbientSceneFrame {
  const _AmbientSceneFrame({
    required this.id,
    required this.imageUrl,
    required this.showArt,
    required this.artPreset,
    required this.fallbackTone,
    required this.isReaderRoute,
    required this.meshGrid,
  });

  final int id;
  final String? imageUrl;
  final bool showArt;
  final EditorialArtPreset artPreset;
  final Color? fallbackTone;
  final bool isReaderRoute;
  final AmbientMeshGrid? meshGrid;

  bool get hasCover => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasMesh => hasCover || meshGrid != null || fallbackTone != null;
  bool get hasArt => !isReaderRoute && hasCover && showArt;

  bool matchesSpec({
    required String? imageUrl,
    required bool showArt,
    required EditorialArtPreset artPreset,
    required Color? fallbackTone,
    required bool isReaderRoute,
  }) {
    return this.imageUrl == imageUrl &&
        this.showArt == showArt &&
        this.artPreset == artPreset &&
        this.fallbackTone == fallbackTone &&
        this.isReaderRoute == isReaderRoute;
  }

  _AmbientSceneFrame copyWith({AmbientMeshGrid? meshGrid}) {
    return _AmbientSceneFrame(
      id: id,
      imageUrl: imageUrl,
      showArt: showArt,
      artPreset: artPreset,
      fallbackTone: fallbackTone,
      isReaderRoute: isReaderRoute,
      meshGrid: meshGrid ?? this.meshGrid,
    );
  }
}

/// 桌面环境光层（v16 稳态 0fps，移除 blobs）。
///
/// 重绘边界：
/// - `ambient-cover`：深色/Reader 4×3 矢量色网双缓冲层，浅色非 Reader 为 `#F4F6F2` 底色；
/// - `ambient-art`：非 Reader 媒体页全出血艺术图双缓冲层（Reader 路由隐藏）；
/// - `ambient-veil`：深色非 Reader 单层 35% 暗纱，Reader 深/浅色中心光池，浅色非 Reader 不渲染。
class DesktopAmbient extends StatefulWidget {
  const DesktopAmbient({
    required this.imageUrl,
    required this.intensity,
    required this.reduceMotion,
    this.showArt = false,
    this.artPreset = EditorialArtPreset.landscape,
    this.fallbackTone,
    this.isReaderRoute = false,
    super.key,
  });

  final String? imageUrl;

  /// 0-100。
  final double intensity;
  final bool reduceMotion;

  /// 是否启用全出血艺术图（Reader 路由下强制隐藏）。
  final bool showArt;

  /// 媒体艺术图预设。
  final EditorialArtPreset artPreset;

  /// 无封面图时的兜底色调（如 Reader 无封面图书的纸色）。
  final Color? fallbackTone;

  /// 是否处于 Reader 路由：隐藏艺术图，仅渲染柔焦 4×3 色网与中心光池。
  final bool isReaderRoute;

  @override
  State<DesktopAmbient> createState() => _DesktopAmbientState();
}

class _DesktopAmbientState extends State<DesktopAmbient>
    with SingleTickerProviderStateMixin {
  static const Duration _sceneCrossfadeDuration = Duration(milliseconds: 720);

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
  bool? _lastIsDark;
  bool _isDark = true;
  Timer? _resizeSettle;
  bool _resizing = false;
  int _sceneSeq = 0;
  int _prepareToken = 0;
  bool _initialScenePrepared = false;
  _AmbientSceneFrame? _activeFrame;
  _AmbientSceneFrame? _outgoingFrame;

  @override
  void initState() {
    super.initState();
    _crossfade.addStatusListener(_handleCrossfadeStatus);
    _seedInitialFrameSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final isDark = DesktopSkin.of(context).isDark;
    final polarityChanged = _lastIsDark != null && _lastIsDark != isDark;
    _isDark = isDark;
    _lastIsDark = isDark;

    if (_lastSize != null && size != _lastSize) {
      _resizing = true;
      _resizeSettle?.cancel();
      _resizeSettle = Timer(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        setState(() => _resizing = false);
      });
    }
    _lastSize = size;

    // 严禁在 didChangeDependencies 同步 setState / precacheImage / 启动动画，
    // 统一经 scheduleMicrotask 异步调度场景准备。
    if (!_initialScenePrepared) {
      _initialScenePrepared = true;
      _schedulePrepareScene(isInitial: true);
    } else if (polarityChanged) {
      _schedulePrepareScene(isInitial: false);
    }
  }

  @override
  void didUpdateWidget(DesktopAmbient oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sceneChanged =
        oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.showArt != widget.showArt ||
        oldWidget.artPreset != widget.artPreset ||
        oldWidget.fallbackTone != widget.fallbackTone ||
        oldWidget.isReaderRoute != widget.isReaderRoute;

    if (!_canAnimate && (_outgoingFrame != null || _crossfade.isAnimating)) {
      _crossfade
        ..stop()
        ..value = 1.0;
      _outgoingFrame = null;
    }

    // 严禁在 didUpdateWidget 同步 setState / precacheImage / 启动动画，
    // 统一经 scheduleMicrotask 异步调度，同时推进 token 取消旧任务监听。
    if (sceneChanged || (oldWidget.intensity <= 0 && widget.intensity > 0)) {
      _schedulePrepareScene(isInitial: false);
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
      showArt: widget.showArt && !widget.isReaderRoute,
      artPreset: widget.artPreset,
      fallbackTone: widget.fallbackTone,
      isReaderRoute: widget.isReaderRoute,
      meshGrid: grid,
    );
  }

  /// 统一经 `scheduleMicrotask` 调度，彻底杜绝生命周期内同步卡死与旧 token 残留。
  void _schedulePrepareScene({required bool isInitial}) {
    final token = ++_prepareToken;
    scheduleMicrotask(() {
      if (!mounted || token != _prepareToken) return;
      _prepareScene(isInitial: isInitial, token: token);
    });
  }

  /// 后台按需采样色网 + 预解码艺术图（220ms 软超时），就绪后原子切换双缓冲。
  void _prepareScene({required bool isInitial, required int token}) {
    if (!mounted || token != _prepareToken) return;
    if (widget.intensity <= 0) {
      return;
    }
    final rawUrl = widget.imageUrl;
    final source = (rawUrl != null && rawUrl.isNotEmpty) ? rawUrl : null;
    final isReaderRoute = widget.isReaderRoute;
    final showArt = widget.showArt && !isReaderRoute;
    final artPreset = widget.artPreset;
    final fallbackTone = widget.fallbackTone;
    // 浅色非 Reader 路由完全跳过 4×3 色网采样。
    final skipMeshSampling = !_isDark && !isReaderRoute;

    // 纯纸色或无封面：同步落帧，不等待异步 I/O。
    if (source == null) {
      final grid =
          (!skipMeshSampling && fallbackTone != null)
              ? AmbientMeshGrid.fromTone(fallbackTone)
              : null;
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
          isReaderRoute: isReaderRoute,
          meshGrid: grid,
        ),
      );
      return;
    }

    final cachedGrid =
        skipMeshSampling ? null : DesktopAmbientMeshCache.instance.peek(source);

    if (isInitial) {
      if ((skipMeshSampling || cachedGrid != null) && !showArt) {
        return;
      }
      unawaited(
        resolveAmbientSceneAssets(
          context: context,
          source: source,
          showArt: showArt,
          artPreset: artPreset,
          cachedGrid: cachedGrid,
          skipMeshSampling: skipMeshSampling,
          isCancelled: () => !mounted || token != _prepareToken,
        ).then((grid) {
          if (!mounted || token != _prepareToken) return;
          final current = _activeFrame;
          if (current == null ||
              !current.matchesSpec(
                imageUrl: source,
                showArt: showArt,
                artPreset: artPreset,
                fallbackTone: fallbackTone,
                isReaderRoute: isReaderRoute,
              )) {
            return;
          }
          if (!skipMeshSampling && grid != null && current.meshGrid != grid) {
            setState(() {
              _activeFrame = current.copyWith(meshGrid: grid);
            });
          }
        }),
      );
      return;
    }

    unawaited(
      resolveAmbientSceneAssets(
        context: context,
        source: source,
        showArt: showArt,
        artPreset: artPreset,
        cachedGrid: cachedGrid,
        skipMeshSampling: skipMeshSampling,
        isCancelled: () => !mounted || token != _prepareToken,
      ).then((grid) {
        if (!mounted || token != _prepareToken) return;
        final effectiveGrid =
            skipMeshSampling
                ? null
                : (grid ??
                    DesktopAmbientMeshCache.instance.peek(source) ??
                    (fallbackTone != null
                        ? AmbientMeshGrid.fromTone(fallbackTone)
                        : null));
        _commitScene(
          _AmbientSceneFrame(
            id: ++_sceneSeq,
            imageUrl: source,
            showArt: showArt,
            artPreset: artPreset,
            fallbackTone: fallbackTone,
            isReaderRoute: isReaderRoute,
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
          isReaderRoute: nextFrame.isReaderRoute,
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
  }

  @override
  void dispose() {
    ++_prepareToken;
    _resizeSettle?.cancel();
    _crossfade.removeStatusListener(_handleCrossfadeStatus);
    _crossfadeIn.dispose();
    _crossfade.dispose();
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
    final activeFrame = _activeFrame;
    final outgoingFrame = _outgoingFrame;
    final isReaderRoute = widget.isReaderRoute;
    final isLightMedia = !skin.isDark && !isReaderRoute;
    final showCoverLayer =
        isLightMedia ||
        (activeFrame?.hasMesh ?? false) ||
        (outgoingFrame?.hasMesh ?? false);
    final showArtLayer =
        !isReaderRoute &&
        ((activeFrame?.hasArt ?? false) || (outgoingFrame?.hasArt ?? false));

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
            return Stack(
              fit: StackFit.expand,
              children: [
                // 边界 1：浅色非 Reader 为纯底色 #F4F6F2；深色/Reader 为 4×3 矢量色网双缓冲。
                if (showCoverLayer)
                  RepaintBoundary(
                    key: const ValueKey('ambient-cover'),
                    child:
                        isLightMedia
                            ? const ColoredBox(
                              color: desktopAmbientLightBaseColor,
                            )
                            : isReaderRoute
                            ? ClipRect(
                              child: Transform.scale(
                                scale: 1.04,
                                child: ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: 2.0,
                                    sigmaY: 2.0,
                                    tileMode: ui.TileMode.clamp,
                                  ),
                                  child: _buildDualBufferMesh(
                                    skin: skin,
                                    profile: profile,
                                    intensityFactor: intensityFactor,
                                    active: activeFrame,
                                    outgoing: outgoingFrame,
                                  ),
                                ),
                              ),
                            )
                            : _buildDualBufferMesh(
                              skin: skin,
                              profile: profile,
                              intensityFactor: intensityFactor,
                              active: activeFrame,
                              outgoing: outgoingFrame,
                            ),
                  ),
                // 边界 2：全出血无模糊无 mask 艺术图双缓冲（Reader 路由隐藏）。
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
                // 边界 3：Reader 深/浅色中心光池；深色媒体页单层平铺暗纱（35%）；浅色媒体页无暗纱无噪点。
                if (isReaderRoute)
                  RepaintBoundary(
                    key: const ValueKey('ambient-veil'),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.1, -0.1),
                          radius: 0.70,
                          colors:
                              skin.isDark
                                  ? desktopReaderDarkPoolColors
                                  : desktopReaderLightPoolColors,
                        ),
                      ),
                    ),
                  )
                else if (skin.isDark)
                  const RepaintBoundary(
                    key: ValueKey('ambient-veil'),
                    child: ColoredBox(color: desktopAmbientDarkVeilColor),
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
}

/// 纯净模式（Plain）背景：用于非五大媒体路由或用户关闭「随封面变色的背景」时。
///
/// 由 `skin.bg` 底色 + 右上角强调色径向光晕（深色 9% / 浅色 7%）+ 顶部纵向微渐变 +
/// 极轻静态噪点组成，整体外包 `RepaintBoundary`，稳态 0fps、零动画回调。
class DesktopAmbientPlain extends StatelessWidget {
  const DesktopAmbientPlain({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          key: const ValueKey('ambient-plain'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: skin.bg),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.92, -0.88),
                    radius: 1.05,
                    colors: <Color>[
                      skin.accent.withValues(alpha: skin.isDark ? 0.09 : 0.07),
                      skin.accent.withValues(alpha: 0.0),
                    ],
                    stops: const <double>[0.0, 0.72],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      (skin.isDark ? Colors.white : Colors.black).withValues(
                        alpha: skin.isDark ? 0.03 : 0.025,
                      ),
                      Colors.transparent,
                    ],
                    stops: const <double>[0.0, 0.36],
                  ),
                ),
              ),
              CustomPaint(
                painter: _PlainGrainPainter(isDark: skin.isDark),
                child: const SizedBox.expand(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plain 模式极轻静态噪点绘制器（仅在外层 `RepaintBoundary` 首次光栅化一次）。
class _PlainGrainPainter extends CustomPainter {
  const _PlainGrainPainter({required this.isDark});

  final bool isDark;

  static const double _tileSize = 128.0;
  static const List<Offset> _dots = <Offset>[
    Offset(12, 19),
    Offset(47, 8),
    Offset(89, 27),
    Offset(115, 14),
    Offset(26, 54),
    Offset(68, 46),
    Offset(103, 61),
    Offset(18, 92),
    Offset(55, 84),
    Offset(94, 98),
    Offset(38, 118),
    Offset(79, 112),
    Offset(121, 107),
    Offset(7, 73),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint =
        Paint()
          ..color = (isDark ? Colors.white : Colors.black).withValues(
            alpha: isDark ? 0.025 : 0.020,
          );
    final cols = math.min((size.width / _tileSize).ceil(), 32);
    final rows = math.min((size.height / _tileSize).ceil(), 20);
    for (var r = 0; r < rows; r++) {
      final baseY = r * _tileSize;
      for (var c = 0; c < cols; c++) {
        final baseX = c * _tileSize;
        for (final dot in _dots) {
          final x = baseX + dot.dx;
          final y = baseY + dot.dy;
          if (x < size.width && y < size.height) {
            canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PlainGrainPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
