import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/desktop/desktop_ambient_mesh.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 桌面环境光层（样例 `Shell.tsx` 的 `Ambient`）。
///
/// 四层叠出「界面浮在环境里」：当前模块封面的 `4×3` 矢量色网（零马赛克、零 blur）、
/// 可选的右侧 64% 高清编辑艺术面板（`showArt: true`）、三团缓慢漂移的色场、
/// 以及把中心让给内容的暗纱。强度由外观设置的 ambient 控制，关闭减动效时漂移停在静帧。
class DesktopAmbient extends StatefulWidget {
  const DesktopAmbient({
    required this.imageUrl,
    required this.intensity,
    required this.reduceMotion,
    this.showArt = false,
    super.key,
  });

  final String? imageUrl;

  /// 0-100。
  final double intensity;
  final bool reduceMotion;

  /// Movies / Photos / Music / Reader 路由启用右侧 64% 高清艺术面板。
  final bool showArt;

  @override
  State<DesktopAmbient> createState() => _DesktopAmbientState();
}

class _DesktopAmbientState extends State<DesktopAmbient>
    with TickerProviderStateMixin {
  /// 预烘焙噪点瓦片边长（128×128 离屏 ui.Image，进程级复用一次生成）。
  static const int _grainTileSize = 128;
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
    // 与原先每 900px² 1 个噪点的稀疏密度一致（128×128 / 900 ≈ 18），
    // 以 ImageShader(TileMode.repeated) 单次 drawRect 铺满视口。
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

  // 三团光各走自己的周期（样例 26s / 34s / 40s，`alternate`）：共用一个
  // 控制器时三团永远同相，屏幕上会一起呼吸，像一整个色块在闪。
  // 循环周期而非过渡时长，故不走 ≤320ms 档。
  late final AnimationController _blobA = AnimationController(
    duration: DesktopMotion.blobCycleFast,
    vsync: this,
  );
  late final AnimationController _blobB = AnimationController(
    duration: DesktopMotion.blobCycleMid,
    vsync: this,
  );
  late final AnimationController _blobC = AnimationController(
    duration: DesktopMotion.blobCycleSlow,
    vsync: this,
  );
  // 样例 `.amb-img.in` 的 `drift 40s alternate`：色网自身也缓慢推拉。
  // 变换挂在保留边界**之上**，边界内的画面只录一次，漂移走合成变换。
  late final AnimationController _drift = AnimationController(
    duration: DesktopMotion.blobCycleSlow,
    vsync: this,
  );

  // 拖边/最大化期间停漂移：整屏色场每帧重画在拖边的每一帧上都是纯浪费，
  // 而且 DWM 会把这一帧和上一帧混在一起看起来像残影。停手 220ms 后恢复。
  Size? _lastSize;
  Timer? _resizeSettle;
  bool _resizing = false;
  int _coverSwapSeq = 0;
  ui.Image? _grainImage = _grainImageCache;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    if (_lastSize != null && size != _lastSize) {
      _resizing = true;
      _syncMotion();
      _resizeSettle?.cancel();
      _resizeSettle = Timer(const Duration(milliseconds: 220), () {
        if (mounted) {
          setState(() => _resizing = false);
          _syncMotion();
        }
      });
    }
    _lastSize = size;
    _syncMotion();
  }

  @override
  void initState() {
    super.initState();
    _syncMotion();
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
  void didUpdateWidget(DesktopAmbient oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _coverSwapSeq += 1;
    }
    _syncMotion();
  }

  bool get _canAnimate =>
      !_resizing &&
      !widget.reduceMotion &&
      !MotionToken.prefersReducedOnPlatform() &&
      widget.intensity > 0;

  void _syncMotion() {
    if (_canAnimate) {
      for (final controller in [_blobA, _blobB, _blobC, _drift]) {
        if (!controller.isAnimating) {
          controller.repeat(reverse: true);
        }
      }
    } else {
      // 静止时停在各自相位上，三团仍然错开，而不是叠成一团；封面回到
      // 样例的起始变换（只有 112% 基础 overscan，无附加推拉）。
      for (final (controller, rest) in [
        (_blobA, 0.35),
        (_blobB, 0.62),
        (_blobC, 0.18),
        (_drift, 0.0),
      ]) {
        controller
          ..stop()
          ..value = rest;
      }
    }
  }

  @override
  void dispose() {
    _resizeSettle?.cancel();
    _blobA.dispose();
    _blobB.dispose();
    _blobC.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.intensity <= 0) {
      return const SizedBox.shrink();
    }
    final skin = DesktopSkin.of(context);
    final targetIntensity = (widget.intensity / 100).clamp(0.0, 1.0);
    final hasCover = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    final viewport = MediaQuery.sizeOf(context);
    final unit = math.max(viewport.width, viewport.height);
    return ExcludeSemantics(
      child: IgnorePointer(
        // 移除外层 AnimatedOpacity，避免 Windows Skia 每帧对整屏环境光执行
        // 离屏 saveLayer；改为仅在 intensity 变化时用 TweenAnimationBuilder 补间，
        // 并将系数直接乘入色网、艺术面板、三团色块与暗纱/噪点各自的 alpha。
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: targetIntensity),
          duration: DesktopMotion.ambientLayer,
          curve: Curves.ease,
          builder: (context, intensityFactor, _) {
            if (intensityFactor <= 0.001) {
              return const SizedBox.shrink();
            }
            final veilOpacity = ((skin.isDark ? 0.86 : 0.70) * intensityFactor)
                .clamp(0.0, 1.0);
            final veilColor = skin.veil.withValues(
              alpha: (skin.veil.a * veilOpacity).clamp(0.0, 1.0),
            );
            // 对齐 desktop.css:170 `.amb-veil` 线性底色为 veil 70%。
            final linearVeilColor = veilColor.withValues(
              alpha: (veilColor.a * 0.70).clamp(0.0, 1.0),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                // 静态层：4×3 矢量色网，只有换封面、改尺寸或调强度时重绘。
                // drift 变换挂在边界之上，边界内画面保留，漂移不触发重录。
                if (hasCover)
                  AnimatedBuilder(
                    animation: _drift,
                    builder: (context, child) {
                      final drift = Curves.easeInOut.transform(
                        _drift.value.clamp(0.0, 1.0),
                      );
                      return Transform(
                        transform:
                            Matrix4.identity()
                              ..translateByDouble(
                                viewport.width * 0.02 * drift,
                                -viewport.height * 0.02 * drift,
                                0,
                                1,
                              )
                              ..scaleByDouble(
                                1.12 * (1 + 0.12 * drift),
                                1.12 * (1 + 0.12 * drift),
                                1.12 * (1 + 0.12 * drift),
                                1,
                              ),
                        alignment: Alignment.center,
                        child: child,
                      );
                    },
                    child: RepaintBoundary(
                      key: const ValueKey('ambient-cover'),
                      child: _coverStack(skin, intensityFactor),
                    ),
                  ),
                // 右侧 64% 高清编辑艺术面板（独立 RepaintBoundary，不污染 ambient-cover）。
                if (hasCover && widget.showArt)
                  RepaintBoundary(
                    key: const ValueKey('ambient-art'),
                    child: EditorialArtPanel(
                      source: widget.imageUrl!,
                      isDark: skin.isDark,
                      intensityFactor: intensityFactor,
                      animate: _canAnimate,
                    ),
                  ),
                // 样例 `.blob` 是「光栅一次的径向渐变纹理 + 合成器 transform」。
                // 这里同构：每团预录静态纹理成保留边界，相位只驱动其上的 Transform。
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
                        alpha: 0.25 * intensityFactor,
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
                        alpha: 0.14 * intensityFactor,
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
                        alpha: 0.12 * intensityFactor,
                        size: viewport,
                        unit: unit,
                      ),
                    ],
                  ),
                ),
                // 静态层：暗纱 alpha 直接折叠进绘制颜色，噪点用 128×128 离屏瓦片平铺，
                // 彻底消除 Opacity saveLayer 与逐像素 drawRect。
                RepaintBoundary(
                  key: const ValueKey('ambient-veil'),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // CSS 先铺 70% 线性实色，再叠径向 10%→95% 透明到 veil 的渐变。
                      ColoredBox(color: linearVeilColor),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.topCenter,
                            radius: 1.25,
                            colors: [Colors.transparent, veilColor],
                            stops: const [0.10, 0.95],
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

  /// 封面换页：样例 `Shell.tsx` 只留最多两层——旧层 `.out` 1.6s 淡出，
  /// 新层 `.in` 1.6s 淡入。直接换图会在切路由时硬切一下。
  Widget _coverStack(DesktopSkin skin, double intensityFactor) {
    final source = widget.imageUrl;
    if (source == null || source.isEmpty) {
      return const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: DesktopMotion.ambientCoverSwap,
      switchInCurve: Curves.ease,
      switchOutCurve: Curves.ease,
      layoutBuilder:
          (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, if (current != null) current],
          ),
      child: KeyedSubtree(
        key: ValueKey<(int, String)>((_coverSwapSeq, source)),
        child: _cover(skin, source, intensityFactor),
      ),
    );
  }

  /// 样例 `.amb-img.amb-mesh`：4×3 矢量色网 + `saturate(1.55) brightness(1.05)`，
  /// 彻底移除 `_mushWidth = 64` 裸拉伸，任意分辨率 0 马赛克。
  Widget _cover(DesktopSkin skin, String source, double intensityFactor) {
    final meshAlpha = ((skin.isDark ? 0.85 : 0.55) * intensityFactor).clamp(
      0.0,
      1.0,
    );
    return DesktopAmbientMeshSurface(
      source: source,
      opacity: meshAlpha,
      saturation: 1.55,
      brightness: 1.05,
    );
  }

  /// 单团色光：静态径向渐变纹理留在保留边界里只录一次；相位只驱动边界
  /// 之上的 Transform。变换与原先逐帧 paint 的公式逐字等价：中心平移
  /// `(a*unit*0.08, a*unit*0.06)`、半径 `unit*(r0+0.2a)` 即绕基中心缩放
  /// `(r0+0.2a)/r0`，故像素中性。
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

/// 样例 `.grain`：预烘焙 128×128 离屏噪点瓦片 + ImageShader 平铺，单次 drawRect 完成绘制。
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
