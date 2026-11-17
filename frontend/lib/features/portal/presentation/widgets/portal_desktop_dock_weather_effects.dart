part of 'portal_desktop_visual_shells.dart';

class _WeatherReactiveDockSurface extends StatefulWidget {
  const _WeatherReactiveDockSurface({
    required this.palette,
    required this.weather,
    required this.child,
  });

  final PortalVisualPalette palette;
  final WeatherData? weather;
  final Widget child;

  @override
  State<_WeatherReactiveDockSurface> createState() =>
      _WeatherReactiveDockSurfaceState();
}

class _WeatherReactiveDockSurfaceState
    extends State<_WeatherReactiveDockSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _reactionInset = 54;

  late final AnimationController _controller;
  late final Stopwatch _clock;
  bool _animationsDisabled = false;

  /// 窗口最小化、失去焦点或退到后台时暂停：粒子画布按帧重绘，
  /// 不可见时继续跑只是白烧 CPU 与电池。
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
    _clock = Stopwatch();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncController();
  }

  @override
  void didUpdateWidget(covariant _WeatherReactiveDockSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  void _syncController() {
    final spec = WeatherSceneSpec.from(widget.weather);
    final visible = _lifecycleState == AppLifecycleState.resumed;
    final shouldAnimate =
        visible && !_animationsDisabled && (spec.isRain || spec.isSnow);
    if (shouldAnimate) {
      if (!_clock.isRunning) {
        _clock.start();
      }
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
      return;
    }
    _clock.stop();
    _clock.reset();
    _controller.stop();
    _controller.value = 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          top: -_reactionInset,
          bottom: 0,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _DockWeatherReactionPainter(
                      palette: widget.palette,
                      weather: widget.weather,
                      dockTopInset: _reactionInset,
                      elapsed:
                          _animationsDisabled
                              ? 0
                              : _clock.elapsedMilliseconds / 1000.0,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DockWeatherReactionPainter extends CustomPainter {
  const _DockWeatherReactionPainter({
    required this.palette,
    required this.weather,
    required this.dockTopInset,
    required this.elapsed,
  });

  final PortalVisualPalette palette;
  final WeatherData? weather;
  final double dockTopInset;
  final double elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final spec = WeatherSceneSpec.from(weather);
    switch (spec.scene) {
      case WeatherScene.rain:
      case WeatherScene.storm:
        _paintRainReaction(canvas, size, spec);
      case WeatherScene.snow:
        _paintSnowCap(canvas, size, spec);
      case WeatherScene.sunny:
      case WeatherScene.partlyCloudy:
      case WeatherScene.cloudy:
      case WeatherScene.fog:
      case WeatherScene.haze:
      case WeatherScene.dust:
      case WeatherScene.heat:
      case WeatherScene.cold:
        return;
    }
  }

  void _paintRainReaction(Canvas canvas, Size size, WeatherSceneSpec spec) {
    final intensity = spec.scene == WeatherScene.storm ? 1.0 : spec.intensity;
    final impactY = dockTopInset;
    final waterDepth = 7 + intensity * 6;
    final waterRect = Rect.fromLTWH(
      0,
      impactY - waterDepth * 0.42,
      size.width,
      waterDepth + 10,
    );
    final waterPaint =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(
                0xFFD8F8FF,
              ).withValues(alpha: 0.04 + intensity * 0.08),
              palette.accent.withValues(alpha: 0.16 + intensity * 0.16),
              const Color(
                0xFF6FCBE2,
              ).withValues(alpha: 0.12 + intensity * 0.10),
              Colors.transparent,
            ],
          ).createShader(waterRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(waterRect, const Radius.circular(8)),
      waterPaint,
    );
    final surfacePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.85
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: 0.30 * intensity),
              palette.accent.withValues(alpha: 0.26 * intensity),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTWH(0, impactY - 2, size.width, 8));
    canvas.drawLine(
      Offset(0, impactY),
      Offset(size.width, impactY),
      surfacePaint,
    );

    final splashPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final ripplePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
    final count = spec.dockRippleCount;
    for (var i = 0; i < count; i++) {
      final seed = _dockUnit(i * 97 + 23);
      final speed = 0.72 + intensity * 0.46 + _dockUnit(i * 43) * 0.40;
      final phase = (elapsed * speed + seed) % 1.0;
      if (phase > 0.70) {
        continue;
      }
      final x =
          (_dockUnit(i * 71 + 11) * size.width +
              math.sin(elapsed * 0.7 + i) * 8 +
              spec.wind * elapsed * 3) %
          size.width;
      final fade = (1 - phase / 0.70).clamp(0.0, 1.0);
      final rippleWidth = 9 + phase * (30 + intensity * 24);
      final rippleHeight = 2.2 + phase * (6 + intensity * 4);
      ripplePaint
        ..strokeWidth = 0.55 + _dockUnit(i * 13) * 0.42
        ..color = Colors.white.withValues(
          alpha: (0.32 * fade * intensity).clamp(0.0, 0.34),
        );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, impactY + 1.2 + phase * 2.6),
          width: rippleWidth,
          height: rippleHeight,
        ),
        ripplePaint,
      );
      final splashPhase = (phase / 0.34).clamp(0.0, 1.0);
      if (phase > 0.34) {
        continue;
      }
      final radius =
          2.4 + splashPhase * (5.8 + intensity * 4.6 + _dockUnit(i * 37) * 3);
      final alpha = (0.62 * (1 - splashPhase) * intensity).clamp(0.0, 0.60);
      splashPaint
        ..strokeWidth = 0.62 + _dockUnit(i * 13) * 0.58
        ..color = Colors.white.withValues(alpha: alpha);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(x, impactY - 0.5), radius: radius),
        math.pi * 1.05,
        math.pi * 0.9,
        false,
        splashPaint,
      );
      dotPaint.color = Colors.white.withValues(alpha: alpha * 0.7);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            x + math.cos(i) * radius * 0.34,
            impactY - 1 + math.sin(i * 1.7) * 2,
          ),
          width: 1.4 + _dockUnit(i * 19) * 1.0,
          height: 2.2 + _dockUnit(i * 29) * 1.2,
        ),
        dotPaint,
      );
      for (var shard = 0; shard < 2; shard++) {
        final shardSeed = _dockUnit(i * 83 + shard * 17);
        final dx = (shardSeed - 0.5) * radius * 0.9;
        final lift = (3 + shardSeed * 6) * (1 - splashPhase);
        canvas.drawLine(
          Offset(x + dx, impactY + 0.4),
          Offset(x + dx * 1.25, impactY - lift),
          splashPaint,
        );
      }
      dotPaint.color = Colors.white.withValues(alpha: alpha * 0.42);
      canvas.drawCircle(
        Offset(
          x + math.cos(i) * radius * 0.34 - 0.5,
          impactY - 2 + math.sin(i * 1.7) * 3,
        ),
        0.55,
        dotPaint,
      );
    }
  }

  void _paintSnowCap(Canvas canvas, Size size, WeatherSceneSpec spec) {
    final density = spec.intensity;
    final progress = (elapsed / spec.snowCapGrowthSeconds).clamp(0.0, 1.0);
    final dockRect = Rect.fromLTWH(
      0,
      dockTopInset,
      size.width,
      (size.height - dockTopInset).clamp(0.0, size.height),
    );
    if (dockRect.height <= 0) {
      return;
    }
    final snowDepth = math.min(
      dockRect.height * 0.18,
      3.2 + progress * (spec.heavy ? 7.2 : 5.0),
    );
    final snowBottom = dockTopInset + snowDepth;
    double crestAt(double x) {
      return dockTopInset +
          0.6 +
          math.sin(x * 0.040 + elapsed * 0.10) * 0.32 +
          _dockUnit(x.round() + 17) * (0.45 + density * 0.42);
    }

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(dockRect, const Radius.circular(10)),
    );

    final shadowPaint =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.18 + progress * 0.14),
              Colors.white.withValues(alpha: 0.10 + density * 0.08),
              Colors.transparent,
            ],
            stops: const [0, 0.68, 1],
          ).createShader(
            Rect.fromLTWH(0, dockTopInset, size.width, snowDepth + 3),
          );
    canvas.drawRect(
      Rect.fromLTWH(0, dockTopInset, size.width, snowDepth + 3),
      shadowPaint,
    );

    final path = Path()..moveTo(0, snowBottom);
    for (var x = 0.0; x <= size.width + 16; x += 16) {
      path.lineTo(x, crestAt(x));
    }
    path
      ..lineTo(size.width, snowBottom)
      ..lineTo(0, snowBottom)
      ..close();
    final paint =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.96),
              Colors.white.withValues(alpha: 0.78),
              Colors.white.withValues(alpha: 0.20),
              Colors.transparent,
            ],
            stops: const [0, 0.44, 0.82, 1],
          ).createShader(
            Rect.fromLTWH(0, dockTopInset, size.width, snowDepth + 2),
          );
    canvas.drawPath(path, paint);

    final crestPath = Path()..moveTo(0, crestAt(0));
    for (var x = 0.0; x <= size.width + 16; x += 16) {
      crestPath.lineTo(x, crestAt(x));
    }
    final underCrestPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2.0 + progress * 0.7
          ..color = Colors.white.withValues(alpha: 0.16 + progress * 0.12);
    canvas.drawPath(crestPath.shift(const Offset(0, 1.2)), underCrestPaint);
    final crestPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 1.0 + progress * 0.45
          ..color = Colors.white.withValues(alpha: 0.76 + progress * 0.14);
    canvas.drawPath(crestPath, crestPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DockWeatherReactionPainter oldDelegate) {
    return !hasSamePortalWeatherVisuals(oldDelegate.weather, weather) ||
        oldDelegate.elapsed != elapsed ||
        oldDelegate.dockTopInset != dockTopInset ||
        oldDelegate.palette != palette;
  }
}

double _dockUnit(num seed) {
  return (math.sin(seed * 12.9898) * 43758.5453123).abs() % 1.0;
}
