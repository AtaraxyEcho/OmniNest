import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 桌面环境光层（样例 `Shell.tsx` 的 `Ambient`）。
///
/// 三件事叠出「界面浮在环境里」：当前模块封面的饱和投影（样例无 blur）、
/// 三团缓慢漂移的色场、以及把中心让给内容的暗纱。强度由外观设置的 ambient
/// 控制，关闭减动效时漂移停在静帧而不是逐帧空转。
class DesktopAmbient extends StatefulWidget {
  const DesktopAmbient({
    required this.imageUrl,
    required this.intensity,
    required this.reduceMotion,
    super.key,
  });

  final String? imageUrl;

  /// 0-100。
  final double intensity;
  final bool reduceMotion;

  @override
  State<DesktopAmbient> createState() => _DesktopAmbientState();
}

class _DesktopAmbientState extends State<DesktopAmbient>
    with TickerProviderStateMixin {
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
  // 样例 `.amb-img.in` 的 `drift 40s alternate`：封面自身也缓慢推拉。
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
  }

  @override
  void didUpdateWidget(DesktopAmbient oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    // 缩放期间连漂移也停：整屏 blob 每帧重画一次，在拖边的每一帧上
    // 都是纯浪费，而且DWM 会把这一帧和上一帧混在一起看起来像残影。
    final animate =
        !_resizing &&
        !widget.reduceMotion &&
        !MotionToken.prefersReducedOnPlatform() &&
        widget.intensity > 0;
    if (animate) {
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
    // 样例 `.ambient { opacity: ambient/100 }`：强度只作用于整层一次。
    // 亮暗差异由封面 opacity(.55/.4) 与暗纱 alpha(.86/.7) 各自承担，
    // 不再额外乘一个整层系数（那会把亮色的色团/噪点也压暗，偏离样例）。
    final opacity = widget.intensity / 100;
    final hasCover = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    final viewport = MediaQuery.sizeOf(context);
    final unit = math.max(viewport.width, viewport.height);
    final drift = Curves.easeInOut.transform(_drift.value.clamp(0.0, 1.0));
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        // 合成顺序必须与样例 `.ambient` 一致：饱和封面 → 漂移色场 →
        // 径向暗纱 → 暗纱实色 → 噪点。拆成三个边界只改「何时重录」，
        // 不改画什么、按什么顺序画、什么透明度。
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 静态层：只有换封面、改尺寸时重绘。drift 变换挂在边界之上，
            // 边界内画面保留，漂移不触发重录（样例走 CSS transform 同理）。
            if (hasCover)
              AnimatedBuilder(
                animation: _drift,
                builder: (context, child) => Transform(
                  transform: Matrix4.identity()
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
                ),
                child: RepaintBoundary(
                  key: const ValueKey('ambient-cover'),
                  child: _cover(skin),
                ),
              ),
            // 样例 `.blob` 是「光栅一次的径向渐变纹理 + 合成器 transform」。
            // 这里同构：每团预录静态纹理成保留边界，相位只驱动其上的
            // Transform（平移 + 绕自身中心缩放），整层不再每帧重录/重光栅，
            // 外层 group opacity 的 saveLayer 也随之进入保留态。
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
                    alpha: 0.25,
                    size: viewport,
                    unit: unit,
                  ),
                  _blobLayer(
                    controller: _blobB,
                    base: Offset(viewport.width * 0.96, viewport.height * 1.04),
                    radius: unit * 0.50,
                    color: skin.warm,
                    alpha: 0.14,
                    size: viewport,
                    unit: unit,
                  ),
                  _blobLayer(
                    controller: _blobC,
                    base: Offset(viewport.width * 0.52, viewport.height * 0.55),
                    radius: unit * 0.34,
                    color: DesktopPalette.ambientCool,
                    alpha: 0.12,
                    size: viewport,
                    unit: unit,
                  ),
                ],
              ),
            ),
            // 静态层：暗纱与噪点只录一次；≤4200 个 1×1 rect 不再每帧重录。
            RepaintBoundary(
              key: const ValueKey('ambient-veil'),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.25,
                        colors: [Colors.transparent, skin.veil],
                        stops: const [0.0, 0.85],
                      ),
                    ),
                  ),
                  // 直接用皮肤里的暗纱色（已含 .86/.7 的透明度）。
                  ColoredBox(color: skin.veil),
                  const CustomPaint(painter: _GrainPainter()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 样例 `.amb-img { filter: saturate(1.6) }`：**只有饱和，没有 blur**。
  /// 此前额外的 48σ 全屏高斯是偏离样例的多余效果，也是最大单点 GPU 成本，
  /// 已移除。不降采样：无低通掩盖时缩图拉伸的细节缺失可见，须原生解码。
  Widget _cover(DesktopSkin skin) => ColorFiltered(
    colorFilter: desktopColorGrade(saturation: 1.6),
    child: Opacity(
      opacity: skin.isDark ? 0.55 : 0.40,
      child: Image.network(
        widget.imageUrl!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    ),
  );

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
          transform: Matrix4.identity()
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
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
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

/// 样例 `.grain`：固定种子的稀疏噪点，只画一次，不参与动画重绘。
class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final random = math.Random(20261114);
    final paint = Paint()..color = DesktopPalette.grain;
    final count = (size.width * size.height / 900).clamp(0, 4200).round();
    for (var i = 0; i < count; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
          1,
          1,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) => false;
}
