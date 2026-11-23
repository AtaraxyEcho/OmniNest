import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/desktop/desktop_ambient_mesh.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/core/theme/motion_token.dart';

part 'desktop_ambient_plain.dart';

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
    this.imageProvider,
  });

  final int id;
  final String? imageUrl;
  final bool showArt;
  final EditorialArtPreset artPreset;
  final Color? fallbackTone;
  final bool isReaderRoute;
  final AmbientMeshGrid? meshGrid;
  final ImageProvider<Object>? imageProvider;

  bool get hasCover => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasMesh => hasCover || meshGrid != null || fallbackTone != null;
  bool get hasArt => !isReaderRoute && hasCover && showArt;

  bool matchesSpec({
    required String? imageUrl,
    required bool showArt,
    required EditorialArtPreset artPreset,
    required Color? fallbackTone,
    required bool isReaderRoute,
    required ImageProvider<Object>? imageProvider,
  }) {
    return this.imageUrl == imageUrl &&
        this.showArt == showArt &&
        this.artPreset == artPreset &&
        this.fallbackTone == fallbackTone &&
        this.isReaderRoute == isReaderRoute &&
        this.imageProvider == imageProvider;
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
      imageProvider: imageProvider,
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
    this.imageProvider,
    this.onImageError,
    super.key,
  });

  final String? imageUrl;

  /// 0-100。
  final double intensity;
  final bool reduceMotion;

  /// 是否启用艺术图（Reader 路由下强制隐藏）。
  final bool showArt;

  /// 媒体艺术图预设。
  final EditorialArtPreset artPreset;

  /// 无封面图时的兜底色调（如 Reader 无封面图书的纸色）。
  final Color? fallbackTone;

  /// 是否处于 Reader 路由：隐藏艺术图，仅渲染柔焦 4×3 色网与中心光池。
  final bool isReaderRoute;

  /// 可选自定义图片提供器（如音乐本地封面鉴权通道）。
  final ImageProvider<Object>? imageProvider;

  /// 艺术图加载失败回调（用于通知上层清理失效 hint 并回落）。
  final VoidCallback? onImageError;

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
        oldWidget.isReaderRoute != widget.isReaderRoute ||
        oldWidget.imageProvider != widget.imageProvider;

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
      imageProvider: hasCover ? widget.imageProvider : null,
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
    final imageProvider = widget.imageProvider;
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
          imageProvider: imageProvider,
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
                imageProvider: imageProvider,
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
        imageProvider: imageProvider,
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
            imageProvider: imageProvider,
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
          imageProvider: nextFrame.imageProvider,
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
    final isLightReader = !skin.isDark && isReaderRoute;
    final showCoverLayer =
        isLightMedia ||
        isLightReader ||
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
            final content = Stack(
              fit: StackFit.expand,
              children: [
                // 边界 1：浅色非 Reader 为纯底色 #F4F6F2；浅色 Reader 为干净 #F4F6F2（无封面时叠轻 .amb-tone）；深色为 4×3 矢量色网双缓冲。
                if (showCoverLayer)
                  RepaintBoundary(
                    key: const ValueKey('ambient-cover'),
                    child:
                        isLightMedia
                            ? const ColoredBox(
                              color: desktopAmbientLightBaseColor,
                            )
                            : isLightReader
                            ? _buildLightReaderBackdrop(activeFrame)
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
                                    isReaderRoute: true,
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
                              isReaderRoute: false,
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
                // 边界 3：Reader 深色 70%×60% 椭圆光池（浅色对齐 polish.css:823 移除暗纱）；深色非 Reader 单层 35% 暗纱 + 5% overlay 细噪点。
                if (isReaderRoute && skin.isDark)
                  RepaintBoundary(
                    key: const ValueKey('ambient-veil'),
                    child: ClipRect(
                      child: Transform.scale(
                        scaleX: 1.167,
                        scaleY: 1.0,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(0.1, -0.1),
                              radius: 0.60,
                              colors: desktopReaderDarkPoolColors,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (!isReaderRoute && skin.isDark) ...[
                  const RepaintBoundary(
                    key: ValueKey('ambient-veil'),
                    child: ColoredBox(color: desktopAmbientDarkVeilColor),
                  ),
                  const RepaintBoundary(
                    key: ValueKey('ambient-grain'),
                    child: CustomPaint(
                      painter: _DarkAmbientGrainPainter(),
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ],
            );
            if (skin.isDark) {
              return Opacity(
                opacity: intensityFactor.clamp(0.0, 1.0),
                alwaysIncludeSemantics: true,
                child: content,
              );
            }
            return content;
          },
        ),
      ),
    );
  }

  Widget _buildLightReaderBackdrop(_AmbientSceneFrame? active) {
    final tone =
        (active != null && !active.hasCover) ? active.fallbackTone : null;
    if (tone == null) {
      return const ColoredBox(color: desktopAmbientLightBaseColor);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: desktopAmbientLightBaseColor),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.1, -0.1),
              radius: 0.85,
              colors: <Color>[
                tone.withValues(alpha: 0.24),
                tone.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDualBufferMesh({
    required DesktopSkin skin,
    required AmbientThemeProfile profile,
    required double intensityFactor,
    required bool isReaderRoute,
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
              isReaderRoute: isReaderRoute,
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
          isReaderRoute: isReaderRoute,
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
    required bool isReaderRoute,
    required _AmbientSceneFrame frame,
  }) {
    final meshAlpha =
        skin.isDark
            ? profile.meshAlpha.clamp(0.0, 1.0)
            : (profile.meshAlpha * intensityFactor).clamp(0.0, 1.0);
    final saturation = (skin.isDark && isReaderRoute) ? 1.35 : profile.meshSat;
    return DesktopAmbientMeshSurface(
      source: frame.imageUrl ?? '',
      imageProvider: frame.imageProvider,
      preloadedGrid: frame.meshGrid,
      opacity: meshAlpha,
      saturation: saturation,
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
            imageProvider: outgoing.imageProvider,
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
        imageProvider: active.imageProvider,
        onImageError: widget.onImageError,
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
