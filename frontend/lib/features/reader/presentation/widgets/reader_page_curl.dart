part of 'reader_page_view.dart';

/// 翻页方向：next 为向右翻（抓取右页外缘向左卷），prev 为向左翻（抓取左页外缘向右卷）。
enum CurlDirection { next, prev }

/// 抓角配置（1:1 对齐样例 `ReaderView.tsx:178` 的 `slant(fy)`）。
@immutable
class CurlGrabConfig {
  const CurlGrabConfig({required this.bottomCorner, required this.slant});

  /// true 抓取底角 (W, H)，false 抓取顶角 (W, 0)。
  final bool bottomCorner;

  /// 折线斜率，范围 [-0.34, 0.34]。
  final double slant;

  factory CurlGrabConfig.fromPointerFy(double fy) {
    final bottom = fy > 0.5;
    final raw = (bottom ? -1.0 : 1.0) * (0.12 + (fy - 0.5).abs() * 0.45);
    return CurlGrabConfig(bottomCorner: bottom, slant: raw.clamp(-0.34, 0.34));
  }

  static const defaultNext = CurlGrabConfig(bottomCorner: true, slant: -0.26);
  static const hoverPeek = CurlGrabConfig(bottomCorner: true, slant: -0.30);

  @override
  bool operator ==(Object other) =>
      other is CurlGrabConfig &&
      other.bottomCorner == bottomCorner &&
      other.slant == slant;

  @override
  int get hashCode => Object.hash(bottomCorner, slant);
}

/// 单帧卷页状态：由 ValueNotifier 直接驱动 CustomPainter 重绘，全程 0 Widget Rebuild。
@immutable
class CurlFrame {
  const CurlFrame({
    required this.progress,
    required this.direction,
    required this.config,
    this.isPeek = false,
  });

  final double progress;
  final CurlDirection direction;
  final CurlGrabConfig config;
  final bool isPeek;

  static const idle = CurlFrame(
    progress: 0,
    direction: CurlDirection.next,
    config: CurlGrabConfig.defaultNext,
  );

  bool get active => progress > 0.0005;
}

/// 预烘焙 128×128 纸张微噪点纹理（静止纸面与动态卷页共用同一份 Shader，耗时 < 0.05ms/帧）。
class PaperGrainCache {
  PaperGrainCache._();

  static final ValueNotifier<ui.ImageShader?> shaderListenable =
      ValueNotifier<ui.ImageShader?>(null);
  static Future<ui.ImageShader>? _pending;

  static ui.ImageShader? get shader => shaderListenable.value;

  /// 在 `ReaderViewPage.initState()` 中调用一次；重复调用安全幂等。
  static Future<ui.ImageShader> ensureLoaded() {
    final current = shaderListenable.value;
    if (current != null) return Future.value(current);
    return _pending ??= _bake();
  }

  static Future<ui.ImageShader> _bake() async {
    const size = 128;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rng = math.Random(20261120);
    final paint = Paint();
    for (var y = 0; y < size; y += 2) {
      for (var x = 0; x < size; x += 2) {
        final v = rng.nextDouble();
        if (v > 0.55) {
          paint.color = Colors.black.withValues(alpha: (v - 0.55) * 0.075);
          canvas.drawRect(
            Rect.fromLTWH(x.toDouble(), y.toDouble(), 2, 2),
            paint,
          );
        }
      }
    }
    final img = await recorder.endRecording().toImage(size, size);
    final baked = ui.ImageShader(
      img,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.identity().storage,
    );
    shaderListenable.value = baked;
    return baked;
  }
}

class _CurlSlice {
  const _CurlSlice({
    required this.clip,
    required this.transform,
    required this.isBack,
    required this.dark,
    required this.light,
  });

  final Path clip;
  final Matrix4 transform;
  final bool isBack;
  final double dark;
  final double light;
}

class _CurlGeometry {
  const _CurlGeometry({
    required this.frontClip,
    required this.frontTransform,
    required this.frontShadeFrom,
    required this.frontShadeTo,
    required this.slices,
    required this.flatClip,
    required this.flatTransform,
    required this.flatShadeFrom,
    required this.flatShadeTo,
    required this.shadowOrigin,
    required this.shadowAngle,
    required this.shadowOpacity,
  });

  final Path frontClip;
  final Matrix4 frontTransform;
  final Offset frontShadeFrom;
  final Offset frontShadeTo;
  final List<_CurlSlice> slices;
  final Path flatClip;
  final Matrix4 flatTransform;
  final Offset flatShadeFrom;
  final Offset flatShadeTo;
  final Offset shadowOrigin;
  final double shadowAngle;
  final double shadowOpacity;

  static const int sliceCount = 28;

  /// 1:1 移植自样例 `curl.ts:leafGeometry`。
  factory _CurlGeometry.compute({
    required double width,
    required double height,
    required double p,
    required CurlGrabConfig config,
    required bool flipFront,
    required bool flipBack,
  }) {
    final w = width;
    final h = height;
    final pp = p.clamp(1e-4, 1.0);
    final corner = Offset(w, config.bottomCorner ? h : 0.0);
    final q = Offset(
      w - 2 * w * pp,
      corner.dy + config.slant * 2 * w * pp * (1 - pp),
    );
    final mid = Offset((corner.dx + q.dx) / 2, (corner.dy + q.dy) / 2);
    final len = (corner - q).distance;
    final n = len < 1e-6 ? const Offset(1, 0) : (corner - q) / len;
    final m = mid.dx * n.dx + mid.dy * n.dy;

    final rho0 = (w * 0.085).clamp(22.0, 54.0);
    var rho = math.min(rho0, len / math.pi) * math.min(1.0, (1 - pp) * 5.0);
    if (rho < 0.8) rho = 0.0;
    final c = m - (math.pi * rho) / 2.0;
    final sEnd = c + math.pi * rho;

    final rect = <Offset>[
      Offset.zero,
      Offset(w, 0),
      Offset(w, h),
      Offset(0, h),
    ];

    Path band(double s0, double s1, bool flip) {
      var pts = rect;
      if (s0 > -1e8) {
        pts = _clipHalf(pts, n, Offset(n.dx * s0, n.dy * s0), 1.0);
      }
      if (s1 < 1e8) {
        pts = _clipHalf(pts, n, Offset(n.dx * s1, n.dy * s1), -1.0);
      }
      if (flip) {
        pts = pts.map((pt) => Offset(w - pt.dx, pt.dy)).toList(growable: false);
      }
      return _polygon(pts);
    }

    (Offset, Offset) shadeSpan(bool flip, double sStart, double sFinish) {
      final nn = flip ? Offset(-n.dx, n.dy) : n;
      final off = flip ? n.dx * w : 0.0;
      return (
        Offset(nn.dx * (sStart - off), nn.dy * (sStart - off)),
        Offset(nn.dx * (sFinish - off), nn.dy * (sFinish - off)),
      );
    }

    final slices = <_CurlSlice>[];
    if (rho > 0) {
      final da = (math.pi * rho) / sliceCount;
      for (var i = 0; i < sliceCount; i++) {
        final s0 = c + i * da;
        final s1 = s0 + da;
        final t0 = (i * da) / rho;
        final t1 = ((i + 1) * da) / rho;
        final u0 = c + rho * math.sin(t0);
        final u1 = c + rho * math.sin(t1);
        final rawK = (u1 - u0) / da;
        final k = rawK.abs() < 1e-3 ? (rawK < 0 ? -1e-3 : 1e-3) : rawK;
        final bigK = u0 - k * s0;
        final isBack = i >= sliceCount ~/ 2;
        final tm = (t0 + t1) / 2.0;
        final t = (tm - math.pi / 2.0) / (math.pi / 2.0);
        final flip = isBack ? flipBack : flipFront;
        final overlap = isBack ? 0.6 : 0.9;
        slices.add(
          _CurlSlice(
            clip: band(s0, s1 + overlap, flip),
            transform: _affineColumnMajor(n, k, bigK, flip, w),
            isBack: isBack,
            dark:
                isBack
                    ? 0.2 * math.pow(math.max(0.0, 1.0 - t), 1.6).toDouble() +
                        0.02
                    : 0.03 + 0.2 * math.sin(tm),
            light:
                isBack
                    ? 0.22 * math.exp(-math.pow((t - 0.5) / 0.24, 2).toDouble())
                    : 0.0,
          ),
        );
      }
    }

    final frontSpan = shadeSpan(flipFront, c - 110.0, c + 1.0);
    final flatSpan = shadeSpan(flipBack, sEnd - 1.0, sEnd + 150.0);
    final shadowOrigin = Offset(
      mid.dx + n.dx * (c + rho - m),
      mid.dy + n.dy * (c + rho - m),
    );
    final shadowOpacity = (math.min(1.0, pp * 9.0) *
            math.min(1.0, (1.0 - pp) * 7.0))
        .clamp(0.0, 1.0);

    return _CurlGeometry(
      frontClip: band(-1e9, c, flipFront),
      frontTransform: flipFront ? _mirrorXColumnMajor(w) : Matrix4.identity(),
      frontShadeFrom: frontSpan.$1,
      frontShadeTo: frontSpan.$2,
      slices: slices,
      flatClip: band(sEnd, 1e9, flipBack),
      flatTransform: _affineColumnMajor(n, -1.0, 2.0 * m, flipBack, w),
      flatShadeFrom: flatSpan.$1,
      flatShadeTo: flatSpan.$2,
      shadowOrigin: shadowOrigin,
      shadowAngle: math.atan2(n.dy, n.dx),
      shadowOpacity: shadowOpacity,
    );
  }
}

/// Sutherland–Hodgman 半平面裁剪：保留 `keep * n·(q - p) >= 0`。
List<Offset> _clipHalf(List<Offset> poly, Offset n, Offset p, double keep) {
  double side(Offset q) => keep * ((q.dx - p.dx) * n.dx + (q.dy - p.dy) * n.dy);
  final out = <Offset>[];
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final sa = side(a);
    final sb = side(b);
    if (sa >= 0) out.add(a);
    if ((sa >= 0) != (sb >= 0)) {
      final t = sa / (sa - sb);
      out.add(Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t));
    }
  }
  return out;
}

Path _polygon(List<Offset> points) {
  final path = Path();
  if (points.length < 3) return path;
  path.moveTo(points.first.dx, points.first.dy);
  for (final pt in points.skip(1)) {
    path.lineTo(pt.dx, pt.dy);
  }
  path.close();
  return path;
}

/// 严格按列主序构造 2D 仿射矩阵，1:1 对齐 CSS `matrix(a, b, c, d, tx, ty)`。
Matrix4 _cssMatrix2d(
  double a,
  double b,
  double c,
  double d,
  double tx,
  double ty,
) => Matrix4(a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);

Matrix4 _mirrorXColumnMajor(double w) => _cssMatrix2d(-1, 0, 0, 1, w, 0);

Matrix4 _affineColumnMajor(
  Offset n,
  double k,
  double offset,
  bool flip,
  double w,
) {
  final a = 1.0 + (k - 1.0) * n.dx * n.dx;
  final b = (k - 1.0) * n.dx * n.dy;
  final d = 1.0 + (k - 1.0) * n.dy * n.dy;
  final e = n.dx * offset;
  final f = n.dy * offset;
  if (flip) {
    return _cssMatrix2d(-a, -b, b, d, a * w + e, b * w + f);
  }
  return _cssMatrix2d(a, b, b, d, e, f);
}

/// 0-Rebuild 卷页画布：
/// - 生产路径传 [frameListenable]，由 CustomPainter 独立监听重绘（0 Widget Rebuild）。
/// - 兼容单测路径直接传 [progress]（及可选 [direction]/[spread]/[config]）。
class ReaderPageCurl extends StatelessWidget {
  const ReaderPageCurl({
    required this.front,
    required this.back,
    required this.paper,
    this.frameListenable,
    this.progress,
    this.direction = CurlDirection.next,
    this.spread = false,
    this.config = CurlGrabConfig.defaultNext,
    super.key,
  }) : assert(
         frameListenable != null || progress != null,
         'Either frameListenable or progress must be provided.',
       );

  final ui.Image front;
  final ui.Image back;
  final Color paper;
  final ValueListenable<CurlFrame>? frameListenable;
  final double? progress;
  final CurlDirection direction;
  final bool spread;
  final CurlGrabConfig config;

  @override
  Widget build(BuildContext context) {
    final listenable =
        frameListenable ??
        AlwaysStoppedAnimation<CurlFrame>(
          CurlFrame(
            progress: progress ?? 0.0,
            direction: direction,
            config: config,
          ),
        );
    return RepaintBoundary(
      child: CustomPaint(
        painter: _CurlPainter(
          frameListenable: listenable,
          front: front,
          back: back,
          paper: paper,
          spread: spread,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _CurlPainter extends CustomPainter {
  _CurlPainter({
    required this.frameListenable,
    required this.front,
    required this.back,
    required this.paper,
    required this.spread,
  }) : super(
         repaint: Listenable.merge([
           frameListenable,
           PaperGrainCache.shaderListenable,
         ]),
       );

  final ValueListenable<CurlFrame> frameListenable;
  final ui.Image front;
  final ui.Image back;
  final Color paper;
  final bool spread;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = frameListenable.value;
    if (size.isEmpty) return;

    final leafWidth = spread ? size.width / 2.0 : size.width;
    final height = size.height;
    final imageRect = Rect.fromLTWH(0, 0, leafWidth, height);
    final frontSrc = Rect.fromLTWH(
      0,
      0,
      front.width.toDouble(),
      front.height.toDouble(),
    );
    final imgPaint = Paint()..filterQuality = FilterQuality.medium;
    final paperPaint = Paint()..color = paper;
    final grainShader = PaperGrainCache.shader;
    final grainPaint =
        grainShader == null
            ? null
            : (Paint()
              ..shader = grainShader
              ..blendMode = BlendMode.multiply);

    if (!frame.active) {
      // 进度为 0 时直接贴合纸面平铺，无折痕。
      canvas.save();
      final spineX = spread ? size.width / 2.0 : 0.0;
      if (frame.direction == CurlDirection.next) {
        canvas.translate(spineX, 0);
      }
      canvas.drawRect(imageRect, paperPaint);
      canvas.drawImageRect(front, frontSrc, imageRect, imgPaint);
      if (grainPaint != null) canvas.drawRect(imageRect, grainPaint);
      canvas.restore();
      return;
    }

    final isPrev = frame.direction == CurlDirection.prev;
    final geometry = _CurlGeometry.compute(
      width: leafWidth,
      height: height,
      p: frame.progress,
      config: frame.config,
      flipFront: isPrev,
      flipBack: !isPrev,
    );
    final backSrc = Rect.fromLTWH(
      0,
      0,
      back.width.toDouble(),
      back.height.toDouble(),
    );

    canvas.save();
    final spineX = spread ? size.width / 2.0 : 0.0;
    canvas.translate(spineX, 0);
    if (isPrev) {
      if (!spread) canvas.translate(leafWidth, 0);
      canvas.scale(-1.0, 1.0);
    }

    // 1. 正面平铺段
    canvas.save();
    canvas.transform(geometry.frontTransform.storage);
    canvas.clipPath(geometry.frontClip);
    canvas.drawRect(imageRect, paperPaint);
    canvas.drawImageRect(front, frontSrc, imageRect, imgPaint);
    if (grainPaint != null) canvas.drawRect(imageRect, grainPaint);
    canvas.drawRect(
      imageRect,
      Paint()
        ..shader = ui.Gradient.linear(
          geometry.frontShadeFrom,
          geometry.frontShadeTo,
          const [Color(0x00000000), Color(0x33000000), Color(0x00000000)],
          const [0.0, 0.98, 1.0],
        ),
    );
    _drawPaperRim(canvas, imageRect, isRightLeaf: !isPrev);
    canvas.restore();

    // 2. 折线投射在下层纸面的软阴影条带（.cu-strip）
    if (geometry.shadowOpacity > 0.002) {
      canvas.save();
      canvas.translate(geometry.shadowOrigin.dx, geometry.shadowOrigin.dy);
      canvas.rotate(geometry.shadowAngle);
      final stripRect = Rect.fromLTWH(0, -height * 1.5, 130, height * 3);
      final a = geometry.shadowOpacity;
      canvas.drawRect(
        stripRect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.36 * a),
              Colors.black.withValues(alpha: 0.20 * a),
              Colors.black.withValues(alpha: 0.08 * a),
              Colors.black.withValues(alpha: 0.025 * a),
              Colors.transparent,
            ],
            stops: const [0.0, 0.077, 0.308, 0.692, 1.0],
          ).createShader(stripRect),
      );
      canvas.restore();
    }

    // 3. 28 片圆柱卷曲条带（内部关闭抗锯齿杜绝 1px 白缝）
    for (final slice in geometry.slices) {
      canvas.save();
      canvas.transform(slice.transform.storage);
      canvas.clipPath(slice.clip, doAntiAlias: false);
      canvas.drawRect(imageRect, paperPaint);
      canvas.drawImageRect(
        slice.isBack ? back : front,
        slice.isBack ? backSrc : frontSrc,
        imageRect,
        imgPaint,
      );
      if (slice.dark > 0.001) {
        canvas.drawRect(
          imageRect,
          Paint()
            ..color = Colors.black.withValues(alpha: slice.dark.clamp(0, 1)),
        );
      }
      if (slice.light > 0.001) {
        canvas.drawRect(
          imageRect,
          Paint()
            ..color = const Color(
              0xFFFFFBEE,
            ).withValues(alpha: slice.light.clamp(0, 1)),
        );
      }
      canvas.restore();
    }

    // 4. 背面平铺段（.cu-wrap > .cu-flat）
    if (frame.progress >= 0.002) {
      canvas.save();
      canvas.translate(-2.0, 3.0);
      canvas.transform(geometry.flatTransform.storage);
      // 用轻量多层半透明偏移替代每帧昂贵的 MaskFilter.blur，60/120fps 丝滑无掉帧。
      final flatShadowAlpha = (0.24 * geometry.shadowOpacity).clamp(0.0, 0.24);
      if (flatShadowAlpha > 0.002) {
        canvas.drawPath(
          geometry.flatClip,
          Paint()
            ..color = Colors.black.withValues(alpha: flatShadowAlpha * 0.45),
        );
        canvas.save();
        canvas.translate(-3.0, 4.0);
        canvas.drawPath(
          geometry.flatClip,
          Paint()
            ..color = Colors.black.withValues(alpha: flatShadowAlpha * 0.28),
        );
        canvas.restore();
      }
      canvas.restore();

      canvas.save();
      canvas.transform(geometry.flatTransform.storage);
      canvas.clipPath(geometry.flatClip);
      canvas.drawRect(imageRect, paperPaint);
      canvas.drawImageRect(back, backSrc, imageRect, imgPaint);
      if (grainPaint != null) canvas.drawRect(imageRect, grainPaint);
      canvas.drawRect(
        imageRect,
        Paint()
          ..shader = ui.Gradient.linear(
            geometry.flatShadeFrom,
            geometry.flatShadeTo,
            const [Color(0x42000000), Color(0x1A000000), Color(0x05000000)],
            const [0.0, 0.17, 1.0],
          ),
      );
      _drawPaperRim(canvas, imageRect, isRightLeaf: isPrev);
      canvas.restore();
    }

    canvas.restore();
  }

  void _drawPaperRim(Canvas canvas, Rect rect, {required bool isRightLeaf}) {
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.black.withValues(alpha: 0.14),
    );
    final edgeX = isRightLeaf ? rect.right - 1.0 : rect.left + 1.0;
    canvas.drawLine(
      Offset(edgeX, rect.top),
      Offset(edgeX, rect.bottom),
      Paint()
        ..strokeWidth = 2.0
        ..color = Colors.white.withValues(alpha: 0.55),
    );
    // 对齐样例 reader.css:18-19 顶边纸缘高光
    canvas.drawLine(
      Offset(rect.left, rect.top + 1.0),
      Offset(rect.right, rect.top + 1.0),
      Paint()
        ..strokeWidth = 2.0
        ..color = Colors.white.withValues(alpha: 0.30),
    );
  }

  @override
  bool shouldRepaint(_CurlPainter oldDelegate) =>
      oldDelegate.front != front ||
      oldDelegate.back != back ||
      oldDelegate.paper != paper ||
      oldDelegate.spread != spread ||
      oldDelegate.frameListenable != frameListenable;
}
