part of 'reader_page_view.dart';

/// 卷页几何（样例 `curl.ts` 的 `leafGeometry`）：把翻起的那一页当成一张
/// 纸——平铺到 `c` 之后绕半径 `rho` 的圆柱卷半圈，再反面平铺回去。每一片
/// 圆柱条带都是整页的仿射变换，28 片拼出卷曲的脊线。
///
/// 只实现「下一页」的几何（书脊在 x=0、外缘在 x=W）；样例对「上一页」是
/// 把同一个画面整体镜像，这里暂时仍退回 cover 平移。
class _CurlSlice {
  const _CurlSlice({
    required this.clip,
    required this.transform,
    required this.back,
    required this.dark,
    required this.light,
  });

  final Path clip;
  final Matrix4 transform;

  /// 这一片露出的是纸背（后 14 片）。
  final bool back;
  final double dark;
  final double light;
}

class _CurlGeometry {
  const _CurlGeometry({
    required this.front,
    required this.slices,
    required this.flat,
    required this.flatTransform,
    required this.foldFrom,
    required this.foldTo,
    required this.flatFrom,
    required this.flatTo,
    required this.shadowCenter,
    required this.shadowAngle,
    required this.shadowOpacity,
    required this.rho,
  });

  final Path front;
  final List<_CurlSlice> slices;
  final Path flat;
  final Matrix4 flatTransform;

  /// 卷曲脊线的渐隐区间（页坐标沿法线 `n` 的投影）。
  final Offset foldFrom;
  final Offset foldTo;
  final Offset flatFrom;
  final Offset flatTo;
  final Offset shadowCenter;
  final double shadowAngle;
  final double shadowOpacity;
  final double rho;

  static const sliceCount = 28;

  /// [p] 为 0（摊平）到 1（完全翻过）。
  factory _CurlGeometry.compute({
    required double width,
    required double height,
    required double p,
  }) {
    final w = width;
    final h = height;
    final pp = p.clamp(1e-4, 1.0);
    const slant = -0.28;
    // 抓住右下角，折线随进度向左推进。
    final corner = Offset(w, h);
    final outer = Offset(w - 2 * w * pp, h + slant * 2 * w * pp * (1 - pp));
    final fold = Offset((corner.dx + outer.dx) / 2, (corner.dy + outer.dy) / 2);
    final length = (corner - outer).distance;
    final n = length == 0 ? const Offset(-1, 0) : (corner - outer) / length;
    final m = fold.dx * n.dx + fold.dy * n.dy;
    final rho0 = (w * 0.085).clamp(22.0, 54.0);
    var rho = math.min(rho0, length / math.pi) * math.min(1.0, (1 - pp) * 5);
    if (rho < 0.8) {
      rho = 0;
    }
    final c = m - (math.pi * rho) / 2;
    final end = c + math.pi * rho;
    List<Offset> rectPoints() => [
      Offset.zero,
      Offset(w, 0),
      Offset(w, h),
      Offset(0, h),
    ];

    final front = _polygon(_clipHalf(rectPoints(), n, fold, -1));
    final flatPolygon = _clipHalf(
      rectPoints(),
      n,
      Offset(n.dx * end, n.dy * end),
      1,
    );

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
        final k = (u1 - u0) / da;
        final scale = k.abs() < 1e-3 ? 1e-3 : k;
        final offset = u0 - scale * s0;
        final back = i >= sliceCount / 2;
        final tm = (t0 + t1) / 2;
        final t = (tm - math.pi / 2) / (math.pi / 2);
        var polygon = _clipHalf(
          rectPoints(),
          n,
          Offset(n.dx * s0, n.dy * s0),
          1,
        );
        polygon = _clipHalf(
          polygon,
          n,
          Offset(
            n.dx * (s1 + (back ? 0 : 0.9)),
            n.dy * (s1 + (back ? 0 : 0.9)),
          ),
          -1,
        );
        slices.add(
          _CurlSlice(
            clip: _polygon(polygon),
            transform: _affine(n, scale, offset, back, w),
            back: back,
            dark:
                back
                    ? 0.2 * math.pow(math.max(0.0, 1 - t), 1.6) + 0.02
                    : 0.03 + 0.2 * math.sin(tm),
            light:
                back
                    ? 0.22 *
                        math.exp(
                          -math.pow(((t - 0.5) / 0.24).abs(), 2).toDouble(),
                        )
                    : 0,
          ),
        );
      }
    }
    final shadow = Offset(
      fold.dx + n.dx * (c + rho - m),
      fold.dy + n.dy * (c + rho - m),
    );
    return _CurlGeometry(
      front: front,
      slices: slices,
      flat: _polygon(flatPolygon),
      flatTransform: _affine(n, -1, 2 * m, true, w),
      foldFrom: fold - n * 110,
      foldTo: fold + n,
      flatFrom: Offset(n.dx * (end - 1), n.dy * (end - 1)),
      flatTo: Offset(n.dx * (end + 150), n.dy * (end + 150)),
      shadowCenter: shadow,
      shadowAngle: math.atan2(n.dy, n.dx),
      shadowOpacity: (math.min(1.0, p * 9) * math.min(1.0, (1 - p) * 7)).clamp(
        0.0,
        1.0,
      ),
      rho: rho,
    );
  }
}

/// Sutherland–Hodgman：保留 `keep * n·(q - p) >= 0` 的一侧。
List<Offset> _clipHalf(List<Offset> poly, Offset n, Offset p, double keep) {
  double side(Offset q) => keep * ((q.dx - p.dx) * n.dx + (q.dy - p.dy) * n.dy);
  final out = <Offset>[];
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final sa = side(a);
    final sb = side(b);
    if (sa >= 0) {
      out.add(a);
    }
    if ((sa >= 0) != (sb >= 0)) {
      final t = sa / (sa - sb);
      out.add(Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t));
    }
  }
  return out;
}

Path _polygon(List<Offset> points) {
  final path = Path();
  if (points.length < 3) {
    return path;
  }
  path.moveTo(points.first.dx, points.first.dy);
  for (final point in points.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  path.close();
  return path;
}

/// 2D 仿射：`q' = q + n * (K + (k - 1) * (n·q))`；[flip] 先把整页水平镜像。
Matrix4 _affine(Offset n, double k, double offset, bool flip, double w) {
  final a = 1 + (k - 1) * n.dx * n.dx;
  final b = (k - 1) * n.dx * n.dy;
  final d = 1 + (k - 1) * n.dy * n.dy;
  final e = n.dx * offset;
  final f = n.dy * offset;
  if (flip) {
    return Matrix4(
      -a,
      -b,
      0,
      a * w + e,
      b,
      d,
      0,
      b * w + f,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
    );
  }
  return Matrix4(a, b, 0, e, b, d, 0, f, 0, 0, 1, 0, 0, 0, 0, 1);
}

/// 卷起的那一页：正面图 + 背面图 + 折线阴影。图片由外层一次性抓取，
/// 之后每帧只做 28 次贴图，避免把整页子树重建 28 份。
class ReaderPageCurl extends StatelessWidget {
  const ReaderPageCurl({
    required this.front,
    required this.back,
    required this.progress,
    required this.paper,
    super.key,
  });

  final ui.Image front;
  final ui.Image back;

  /// 0 为摊平，1 为完全翻过。
  final double progress;
  final Color paper;

  @override
  Widget build(BuildContext context) =>
      _CurlSurface(front: front, back: back, progress: progress, paper: paper);
}

class _CurlSurface extends StatelessWidget {
  const _CurlSurface({
    required this.front,
    required this.back,
    required this.progress,
    required this.paper,
  });

  final ui.Image front;
  final ui.Image back;
  final double progress;
  final Color paper;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
        final height =
            constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height;
        final geometry = _CurlGeometry.compute(
          width: width,
          height: height,
          p: progress,
        );
        return CustomPaint(
          painter: _CurlPainter(
            geometry: geometry,
            front: front,
            back: back,
            paper: paper,
            width: width,
            height: height,
          ),
          size: Size(width, height),
        );
      },
    );
  }
}

class _CurlPainter extends CustomPainter {
  _CurlPainter({
    required this.geometry,
    required this.front,
    required this.back,
    required this.paper,
    required this.width,
    required this.height,
  });

  final _CurlGeometry geometry;
  final ui.Image front;
  final ui.Image back;
  final Color paper;
  final double width;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final imageRect = Rect.fromLTWH(0, 0, width, height);
    final source = Rect.fromLTWH(
      0,
      0,
      front.width.toDouble(),
      front.height.toDouble(),
    );
    final backSource = Rect.fromLTWH(
      0,
      0,
      back.width.toDouble(),
      back.height.toDouble(),
    );
    final paint = Paint()..filterQuality = FilterQuality.medium;

    // 折线落在下面那张纸上投出的阴影：先画，后画纸片。
    canvas.save();
    canvas.translate(geometry.shadowCenter.dx, geometry.shadowCenter.dy);
    canvas.rotate(geometry.shadowAngle);
    final stripRect = Rect.fromLTWH(0, -height * 1.5, 130, height * 3);
    canvas.drawRect(
      stripRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.36),
            Colors.black.withValues(alpha: 0.2),
            Colors.black.withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.025),
            Colors.transparent,
          ],
          stops: const [0, 0.08, 0.31, 0.7, 1],
        ).createShader(stripRect),
    );
    canvas.restore();

    // 正面：卷起前一直平铺到折线。
    canvas.save();
    canvas.clipPath(geometry.front);
    canvas.drawRect(imageRect, Paint()..color = paper);
    canvas.drawImageRect(front, source, imageRect, paint);
    canvas.restore();
    _shade(
      canvas,
      geometry.front,
      geometry.foldFrom,
      geometry.foldTo,
      [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.2),
        Colors.transparent,
      ],
      const [0, 0.98, 1],
    );

    // 反面平铺段：过脊线后重新铺回纸面；先在下层纸上落一层软影。
    canvas.save();
    canvas.clipPath(geometry.flat);
    canvas.transform(geometry.flatTransform.storage);
    canvas.drawRect(
      imageRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.restore();
    canvas.save();
    canvas.clipPath(geometry.flat);
    canvas.transform(geometry.flatTransform.storage);
    canvas.drawRect(imageRect, Paint()..color = paper);
    canvas.drawImageRect(back, backSource, imageRect, paint);
    canvas.restore();
    _shade(
      canvas,
      geometry.flat,
      geometry.flatFrom,
      geometry.flatTo,
      [
        Colors.black.withValues(alpha: 0.26),
        Colors.black.withValues(alpha: 0.1),
        Colors.black.withValues(alpha: 0.02),
      ],
      const [0, 0.17, 1],
    );

    // 28 片圆柱条带。
    for (final slice in geometry.slices) {
      canvas.save();
      canvas.clipPath(slice.clip);
      canvas.transform(slice.transform.storage);
      canvas.drawRect(imageRect, Paint()..color = paper);
      canvas.drawImageRect(
        slice.back ? back : front,
        slice.back ? backSource : source,
        imageRect,
        paint,
      );
      canvas.restore();
      if (slice.dark > 0.001) {
        canvas.drawPath(
          slice.clip,
          Paint()
            ..color = Colors.black.withValues(alpha: slice.dark.clamp(0, 1)),
        );
      }
      if (slice.light > 0.001) {
        canvas.drawPath(
          slice.clip,
          Paint()
            ..color = (Color.lerp(paper, Colors.white, 0.75) ?? Colors.white)
                .withValues(alpha: slice.light.clamp(0, 1)),
        );
      }
      canvas.drawPath(
        slice.clip,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.07),
      );
    }
  }

  void _shade(
    Canvas canvas,
    Path clip,
    Offset from,
    Offset to,
    List<Color> colors,
    List<double> stops,
  ) {
    final bounds = clip.getBounds();
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          colors: colors,
          stops: stops,
        ).createShader(Rect.fromPoints(from, to)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CurlPainter oldDelegate) {
    return oldDelegate.geometry != geometry ||
        oldDelegate.front != front ||
        oldDelegate.back != back ||
        oldDelegate.paper != paper;
  }
}
