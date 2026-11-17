part of 'weather_detail_dialog.dart';

/// 为天气详情绘制连续的云层、雾带和降水效果。
class _WeatherScenePainter extends CustomPainter {
  const _WeatherScenePainter({
    required this.spec,
    required this.elapsed,
    required this.particleColor,
  });

  final WeatherSceneSpec spec;
  final double elapsed;
  final Color particleColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    switch (spec.scene) {
      case WeatherScene.sunny:
      case WeatherScene.heat:
        _paintSunlight(canvas, size);
        _paintAirParticles(canvas, size, count: 18);
        break;
      case WeatherScene.partlyCloudy:
        _paintSunlight(canvas, size);
        _paintClouds(canvas, size, opacity: 0.24);
        break;
      case WeatherScene.cloudy:
        _paintClouds(canvas, size, opacity: 0.32);
        break;
      case WeatherScene.rain:
        _paintClouds(canvas, size, opacity: 0.34);
        _paintRain(canvas, size);
        break;
      case WeatherScene.storm:
        _paintClouds(canvas, size, opacity: 0.4);
        _paintRain(canvas, size);
        _paintLightning(canvas, size);
        break;
      case WeatherScene.snow:
      case WeatherScene.cold:
        _paintClouds(canvas, size, opacity: 0.25);
        _paintSnow(canvas, size);
        break;
      case WeatherScene.fog:
      case WeatherScene.haze:
        _paintFog(canvas, size, opacity: 0.24);
        _paintAirParticles(canvas, size, count: 24);
        break;
      case WeatherScene.dust:
        _paintFog(canvas, size, opacity: 0.18);
        _paintAirParticles(canvas, size, count: 34);
        break;
    }
  }

  void _paintSunlight(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.78, size.height * 0.19);
    final pulse = 0.94 + math.sin(elapsed * 0.45) * 0.04;
    final radius = math.min(size.width, size.height) * 0.095 * pulse;
    final halo =
        Paint()
          ..shader = RadialGradient(
            colors: [
              particleColor.withValues(alpha: 0.34),
              particleColor.withValues(alpha: 0.09),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius * 2.8));
    canvas.drawCircle(center, radius * 2.8, halo);

    final rayPaint =
        Paint()
          ..color = particleColor.withValues(alpha: 0.18)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.4;
    for (var i = 0; i < 10; i++) {
      final angle = i * math.pi * 2 / 10 + elapsed * 0.025;
      final start = center + Offset.fromDirection(angle, radius * 1.25);
      final end = center + Offset.fromDirection(angle, radius * 1.8);
      canvas.drawLine(start, end, rayPaint);
    }
  }

  void _paintClouds(Canvas canvas, Size size, {required double opacity}) {
    final count = math.min(spec.cloudCount, 7);
    for (var i = 0; i < count; i++) {
      final seed = i * 41 + 7;
      final cloudWidth = size.width * (0.22 + _weatherUnit(seed) * 0.18);
      final cloudHeight = cloudWidth * (0.2 + _weatherUnit(seed + 1) * 0.08);
      final travel = size.width + cloudWidth * 2;
      final speed = 5.0 + _weatherUnit(seed + 2) * 7.0;
      final x =
          (_weatherUnit(seed + 3) * travel + elapsed * speed) % travel -
          cloudWidth;
      final y = size.height * (0.07 + _weatherUnit(seed + 4) * 0.34);
      final path =
          Path()
            ..moveTo(x, y + cloudHeight * 0.72)
            ..cubicTo(
              x + cloudWidth * 0.08,
              y + cloudHeight * 0.28,
              x + cloudWidth * 0.25,
              y + cloudHeight * 0.26,
              x + cloudWidth * 0.34,
              y + cloudHeight * 0.48,
            )
            ..cubicTo(
              x + cloudWidth * 0.43,
              y - cloudHeight * 0.08,
              x + cloudWidth * 0.69,
              y - cloudHeight * 0.02,
              x + cloudWidth * 0.72,
              y + cloudHeight * 0.45,
            )
            ..cubicTo(
              x + cloudWidth * 0.86,
              y + cloudHeight * 0.28,
              x + cloudWidth,
              y + cloudHeight * 0.42,
              x + cloudWidth,
              y + cloudHeight * 0.75,
            )
            ..cubicTo(
              x + cloudWidth * 0.78,
              y + cloudHeight,
              x + cloudWidth * 0.23,
              y + cloudHeight,
              x,
              y + cloudHeight * 0.72,
            )
            ..close();
      final paint =
          Paint()
            ..color = particleColor.withValues(
              alpha: opacity * (0.72 + _weatherUnit(seed + 5) * 0.28),
            )
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawPath(path, paint);
    }
  }

  void _paintFog(Canvas canvas, Size size, {required double opacity}) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    for (var i = 0; i < 7; i++) {
      final phase = (elapsed * (4 + i * 0.35) + i * 97) % (size.width * 0.2);
      final y = size.height * (0.18 + i * 0.1);
      final path =
          Path()
            ..moveTo(-size.width * 0.18 + phase, y)
            ..cubicTo(
              size.width * 0.2,
              y - 16,
              size.width * 0.38,
              y + 18,
              size.width * 0.56,
              y,
            )
            ..cubicTo(
              size.width * 0.72,
              y - 14,
              size.width * 0.88,
              y + 12,
              size.width * 1.18 + phase,
              y - 2,
            );
      paint
        ..color = particleColor.withValues(alpha: opacity - i * 0.018)
        ..strokeWidth = 16 + i * 2.5;
      canvas.drawPath(path, paint);
    }
  }

  void _paintRain(Canvas canvas, Size size) {
    final count = math.min(spec.rainFarCount + spec.rainNearCount, 54);
    final paint =
        Paint()
          ..color = particleColor.withValues(alpha: spec.heavy ? 0.42 : 0.3)
          ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final seed = i * 53 + 11;
      final speed = 120 + _weatherUnit(seed) * 150;
      final x = _weatherUnit(seed + 1) * (size.width + 100) - 50;
      final y =
          (_weatherUnit(seed + 2) * size.height + elapsed * speed) %
              (size.height + 80) -
          40;
      final length = 10 + _weatherUnit(seed + 3) * 20;
      paint.strokeWidth = 0.7 + _weatherUnit(seed + 4) * 1.1;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - 5 - spec.wind * 6, y + length),
        paint,
      );
    }
  }

  void _paintSnow(Canvas canvas, Size size) {
    final count = math.min(spec.snowCount, 48);
    final paint = Paint()..color = particleColor.withValues(alpha: 0.7);
    for (var i = 0; i < count; i++) {
      final seed = i * 67 + 13;
      final speed = 16 + _weatherUnit(seed) * 34;
      final drift = math.sin(elapsed * 0.5 + seed) * (8 + spec.wind * 12);
      final x = (_weatherUnit(seed + 1) * size.width + drift) % size.width;
      final y =
          (_weatherUnit(seed + 2) * size.height + elapsed * speed) %
              (size.height + 20) -
          10;
      canvas.drawCircle(
        Offset(x, y),
        1.1 + _weatherUnit(seed + 3) * 2.2,
        paint,
      );
    }
  }

  void _paintAirParticles(Canvas canvas, Size size, {required int count}) {
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final seed = i * 73 + 19;
      final x =
          (_weatherUnit(seed) * size.width +
              elapsed * (2 + _weatherUnit(seed + 1) * 4)) %
          size.width;
      final y = _weatherUnit(seed + 2) * size.height;
      paint.color = particleColor.withValues(
        alpha: 0.08 + _weatherUnit(seed + 3) * 0.16,
      );
      canvas.drawCircle(
        Offset(x, y),
        0.7 + _weatherUnit(seed + 4) * 1.8,
        paint,
      );
    }
  }

  void _paintLightning(Canvas canvas, Size size) {
    final phase = elapsed % 5.8;
    if (phase > 0.14) return;
    final opacity = (1 - phase / 0.14).clamp(0.0, 1.0);
    final path =
        Path()
          ..moveTo(size.width * 0.68, size.height * 0.08)
          ..lineTo(size.width * 0.61, size.height * 0.22)
          ..lineTo(size.width * 0.66, size.height * 0.21)
          ..lineTo(size.width * 0.57, size.height * 0.39);
    final paint =
        Paint()
          ..color = WeatherDetailChromeColors.lightning.withValues(
            alpha: opacity,
          )
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2.2;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WeatherScenePainter oldDelegate) {
    return oldDelegate.spec != spec ||
        oldDelegate.elapsed != elapsed ||
        oldDelegate.particleColor != particleColor;
  }
}

double _weatherUnit(int seed) {
  return (math.sin(seed * 12.9898) * 43758.5453123).abs() % 1.0;
}
