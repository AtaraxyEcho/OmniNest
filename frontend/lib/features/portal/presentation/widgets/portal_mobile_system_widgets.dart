part of 'portal_mobile_shell.dart';

class _WeeklyStatsCard extends StatelessWidget {
  const _WeeklyStatsCard({this.readingCount, this.musicPlays, this.photoCount});

  final int? readingCount;
  final int? musicPlays;
  final int? photoCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.portalWeatherWeeklyStats,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  icon: Icons.menu_book_outlined,
                  value: readingCount ?? 0,
                  label: l10n.portalWeatherStatReading,
                  color: scheme.tertiary,
                ),
                _StatItem(
                  icon: Icons.music_note_outlined,
                  value: musicPlays ?? 0,
                  label: l10n.portalWeatherStatPlaying,
                  color: scheme.primary,
                ),
                _StatItem(
                  icon: Icons.photo_outlined,
                  value: photoCount ?? 0,
                  label: l10n.portalWeatherStatPhotos,
                  color: scheme.secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个统计项 — 数字变化时播放计数动画
class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        TweenAnimationBuilder<int>(
          key: ValueKey(value),
          tween: IntTween(begin: 0, end: value),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder:
              (context, animatedValue, _) => Text(
                '$animatedValue',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
class _CardParticlePainter extends CustomPainter {
  _CardParticlePainter({required this.weather, required this.elapsed});

  final WeatherData weather;
  final double elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final spec = WeatherSceneSpec.from(weather);
    final profile = spec.profile;
    final scene = spec.scene;
    final atm = WeatherCardAtmosphere.forScene(scene, profile);

    canvas.drawRect(Offset.zero & size, Paint()..color = atm.tint);

    switch (scene) {
      case WeatherScene.rain || WeatherScene.storm:
        _paintRain(
          canvas,
          size,
          atm,
          intensity: spec.intensity,
          heavy: spec.heavy,
          wind: spec.wind,
        );
      case WeatherScene.snow:
        _paintSnow(canvas, size, atm, spec);
      case WeatherScene.sunny:
        _paintSunGlow(canvas, size, atm, profile: profile);
      case WeatherScene.partlyCloudy:
        _paintSunGlow(canvas, size, atm, profile: profile, dimmed: true);
        _paintClouds(canvas, size, atm, 2, profile: profile);
      case WeatherScene.cloudy:
        _paintClouds(canvas, size, atm, 3, profile: profile);
      case WeatherScene.fog:
        _paintFog(canvas, size, atm, profile: profile);
      case WeatherScene.haze:
        _paintFog(canvas, size, atm, profile: profile);
        _paintHaze(canvas, size, atm);
      case WeatherScene.dust:
        _paintDust(canvas, size, atm);
      case WeatherScene.heat:
        _paintSunGlow(canvas, size, atm, profile: profile);
        _paintHeat(canvas, size, atm);
      case WeatherScene.cold:
        _paintFog(canvas, size, atm, profile: profile);
        _paintCold(canvas, size, atm);
    }
  }

  void _paintRain(
    Canvas canvas,
    Size size,
    WeatherCardAtmosphere atm, {
    required double intensity,
    required bool heavy,
    required double wind,
  }) {
    final rng = math.Random(42);
    final density = heavy ? 1.0 : intensity.clamp(0.0, 1.0);
    final count = heavy ? 14 : (6 + density * 8).round();
    final slant = (heavy ? 0.044 : 0.014 + density * 0.020) * wind.sign;
    final p =
        Paint()
          ..strokeWidth = 0.44
          ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final bx = rng.nextDouble() * size.width * 1.2 - size.width * 0.1;
      final sp = 0.28 + density * 0.18 + rng.nextDouble() * 0.34;
      final y = ((elapsed * sp + rng.nextDouble()) % 1.4 - 0.2) * size.height;
      final len = 5 + density * 2 + rng.nextDouble() * 5.5;
      final op = (0.1 + rng.nextDouble() * 0.15).clamp(0.0, 1.0);
      p.color = atm.particle.withValues(alpha: op * 0.86);
      canvas.drawLine(Offset(bx, y), Offset(bx - len * slant, y + len), p);
    }
  }

  void _paintSnow(
    Canvas canvas,
    Size size,
    WeatherCardAtmosphere atm,
    WeatherSceneSpec spec,
  ) {
    final profile = spec.profile;
    final rng = math.Random(7);
    final p = Paint()..style = PaintingStyle.fill;
    final density = spec.intensity;
    final count = (4 + density * 7 + (spec.heavy ? 4 : 0)).round();
    final detailedEvery = spec.heavy ? 5 : 7;
    for (var i = 0; i < count; i++) {
      final bx = rng.nextDouble() * size.width;
      final sp =
          (spec.heavy ? 0.13 : 0.075) +
          density * (spec.heavy ? 0.095 : 0.060) +
          rng.nextDouble() * 0.075;
      final y = ((elapsed * sp + rng.nextDouble()) % 1.3 - 0.15) * size.height;
      final drift =
          math.sin(elapsed * 0.35 + rng.nextDouble() * 6) *
              (1.3 + density * 2.0) +
          profile.wind * elapsed * (0.8 + density * 1.4);
      final r =
          0.8 + density * 0.12 + rng.nextDouble() * (0.85 + density * 0.45);
      final op = (0.78 + density * 0.10 + rng.nextDouble() * 0.10).clamp(
        0.0,
        0.98,
      );
      final center = Offset(bx + drift, y);
      p
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: op * 0.12);
      canvas.drawCircle(center, r * 1.36, p);
      p
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: op);
      canvas.drawCircle(center, r, p);
      p
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: op * 0.76);
      canvas.drawCircle(center.translate(-r * 0.22, -r * 0.24), r * 0.30, p);
      if (i % detailedEvery == 0) {
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = (r * 0.18).clamp(0.28, 0.46)
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: op * 0.84);
        for (var spoke = 0; spoke < 3; spoke++) {
          final angle = math.pi / 3 * spoke;
          final delta = Offset(math.cos(angle), math.sin(angle)) * r * 1.65;
          canvas.drawLine(center - delta, center + delta, p);
        }
      }
    }
  }

  void _paintSunGlow(
    Canvas canvas,
    Size size,
    WeatherCardAtmosphere atm, {
    required PortalWeatherProfile profile,
    bool dimmed = false,
  }) {
    final c = Offset(
      size.width * (profile.isTransition ? 0.78 : 0.85),
      size.height *
          (profile.isDawn
              ? 0.18
              : profile.isDusk
              ? 0.24
              : 0.15),
    );
    final r = size.width * 0.35;
    if (profile.isNight) {
      final p =
          Paint()
            ..shader = RadialGradient(
              colors: [
                WeatherCardFxColors.nightGlow.withValues(
                  alpha: dimmed ? 0.05 : 0.10,
                ),
                WeatherCardFxColors.nightGlowSoft.withValues(
                  alpha: dimmed ? 0.02 : 0.04,
                ),
                Colors.transparent,
              ],
            ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, p);
      canvas.drawCircle(
        c,
        12,
        Paint()..color = Colors.white.withValues(alpha: dimmed ? 0.22 : 0.34),
      );
      return;
    }
    final glowColor =
        profile.isDawn
            ? WeatherCardFxColors.dawnGlow
            : profile.isDusk
            ? WeatherCardFxColors.duskGlow
            : atm.particle;
    final p =
        Paint()
          ..shader = RadialGradient(
            colors: [
              glowColor.withValues(alpha: dimmed ? 0.06 : 0.12),
              glowColor.withValues(alpha: dimmed ? 0.02 : 0.04),
              Colors.transparent,
            ],
            stops: const [0, 0.5, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, p);
  }

  void _paintClouds(
    Canvas canvas,
    Size size,
    WeatherCardAtmosphere atm,
    int count, {
    required PortalWeatherProfile profile,
  }) {
    final p = Paint();
    final cloudColor =
        profile.isNight
            ? WeatherCardFxColors.nightGlow.withValues(alpha: 0.42)
            : profile.isDawn
            ? WeatherCardFxColors.dawnGlow.withValues(alpha: 0.42)
            : profile.isDusk
            ? WeatherCardFxColors.duskCloud.withValues(alpha: 0.42)
            : atm.particle;
    for (var i = 0; i < count; i++) {
      final depth = 0.46 + _cardUnit(i * 37 + 13) * 0.74;
      final by =
          size.height * (0.12 + _cardUnit(i * 43 + 7) * 0.36) +
          math.sin(elapsed * 0.16 + i) * (2.5 + depth * 4);
      final sp = 0.005 + depth * 0.012;
      final totalW = size.width * 1.68;
      final bx = _cardUnit(i * 59 + 23) * totalW;
      final x =
          ((bx + elapsed * sp * size.width * 2.0) % totalW) - size.width * 0.34;
      final width = size.width * (0.36 + depth * 0.38);
      final height = 22 + depth * 25;
      final op = (0.030 + depth * 0.052).clamp(0.0, 0.10);
      final rect = Rect.fromCenter(
        center: Offset(x, by),
        width: width,
        height: height,
      );
      p.shader = RadialGradient(
        colors: [
          cloudColor.withValues(alpha: op),
          cloudColor.withValues(alpha: op * 0.44),
          Colors.transparent,
        ],
        stops: const [0.0, 0.58, 1.0],
      ).createShader(rect);
      canvas.drawOval(rect, p);

      final tailRect = Rect.fromCenter(
        center: Offset(x - width * 0.20, by + height * 0.08),
        width: width * 1.22,
        height: height * 0.58,
      );
      p.shader = LinearGradient(
        colors: [
          Colors.transparent,
          cloudColor.withValues(alpha: op * 0.20),
          cloudColor.withValues(alpha: op * 0.11),
          Colors.transparent,
        ],
        stops: const [0.0, 0.36, 0.70, 1.0],
      ).createShader(tailRect);
      canvas.drawOval(tailRect, p);
    }

    for (var i = 0; i < 2; i++) {
      final y =
          size.height * (0.24 + i * 0.18) + math.sin(elapsed * 0.14 + i) * 3;
      final drift =
          ((elapsed * (0.008 + i * 0.003) + _cardUnit(i * 29)) % 1.4 - 0.2) *
          size.width;
      final rect = Rect.fromCenter(
        center: Offset(drift, y),
        width: size.width * (1.06 + i * 0.16),
        height: 18 + i * 6,
      );
      p.shader = RadialGradient(
        colors: [
          cloudColor.withValues(alpha: 0.018 + i * 0.006),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect);
      canvas.drawOval(rect, p);
    }
  }

  void _paintFog(
    Canvas canvas,
    Size size,
    WeatherCardAtmosphere atm, {
    required PortalWeatherProfile profile,
  }) {
    final p = Paint();
    final fogColor =
        profile.isNight
            ? WeatherCardFxColors.nightGlow
            : profile.isDawn
            ? WeatherCardFxColors.dawnFog
            : profile.isDusk
            ? WeatherCardFxColors.duskFog
            : atm.particle;
    for (var i = 0; i < 4; i++) {
      final by = size.height * (0.18 + i * 0.19);
      final drift = math.sin(elapsed * 0.25 + i * 1.0) * (8 + i * 4);
      final breath = 0.58 + math.sin(elapsed * 0.20 + i * 0.6) * 0.22;
      final op = ((0.025 + i * 0.012) * breath).clamp(0.0, 0.12);
      final rect = Rect.fromCenter(
        center: Offset(
          size.width * (0.50 + (i.isEven ? 0.07 : -0.05)),
          by + drift,
        ),
        width: size.width * (1.04 + i * 0.12),
        height: 30 + i * 8,
      );
      p.shader = RadialGradient(
        colors: [
          fogColor.withValues(alpha: op),
          fogColor.withValues(alpha: op * 0.42),
          Colors.transparent,
        ],
        stops: const [0, 0.56, 1],
      ).createShader(rect);
      canvas.drawOval(rect, p);
    }
  }

  void _paintHaze(Canvas canvas, Size size, WeatherCardAtmosphere atm) {
    final p = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 14; i++) {
      final x =
          (_cardUnit(i * 41 + 5) * size.width +
              math.sin(elapsed * 0.12 + i) * 3) %
          size.width;
      final y = _cardUnit(i * 53 + 3) * size.height * 0.78;
      p.color = atm.particle.withValues(alpha: 0.025 + _cardUnit(i) * 0.035);
      canvas.drawCircle(Offset(x, y), 0.6 + _cardUnit(i * 19) * 1.0, p);
    }
  }

  void _paintDust(Canvas canvas, Size size, WeatherCardAtmosphere atm) {
    final p = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 4; i++) {
      final x =
          ((elapsed * (0.018 + i * 0.004) + _cardUnit(i * 37)) % 1.3 - 0.15) *
          size.width;
      final y = size.height * (0.22 + i * 0.14);
      final rect = Rect.fromCenter(
        center: Offset(x, y + math.sin(elapsed * 0.18 + i) * 4),
        width: size.width * (0.70 + i * 0.12),
        height: 22 + i * 4,
      );
      p.shader = RadialGradient(
        colors: [
          atm.particle.withValues(alpha: 0.08 + i * 0.018),
          atm.particle.withValues(alpha: 0.025),
          Colors.transparent,
        ],
        stops: const [0, 0.58, 1],
      ).createShader(rect);
      canvas.drawOval(rect, p);
    }
    p.shader = null;
    for (var i = 0; i < 18; i++) {
      final x =
          ((elapsed * (0.020 + _cardUnit(i) * 0.012) + _cardUnit(i * 47)) %
                  1.2 -
              0.1) *
          size.width;
      final y = size.height * (0.12 + _cardUnit(i * 59) * 0.70);
      p.color = atm.particle.withValues(alpha: 0.07 + _cardUnit(i * 11) * 0.08);
      canvas.drawCircle(Offset(x, y), 0.55 + _cardUnit(i * 17) * 1.25, p);
    }
  }

  void _paintHeat(Canvas canvas, Size size, WeatherCardAtmosphere atm) {
    final p =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (0.34 + i * 0.11);
      final path = Path();
      for (var x = -12.0; x <= size.width + 12; x += 14) {
        final wave = math.sin(x * 0.05 + elapsed * 0.8 + i) * (1.2 + i * 0.3);
        if (x == -12) {
          path.moveTo(x, y + wave);
        } else {
          path.lineTo(x, y + wave);
        }
      }
      p
        ..strokeWidth = 0.8
        ..color = atm.particle.withValues(alpha: 0.055 + i * 0.012);
      canvas.drawPath(path, p);
    }
  }

  void _paintCold(Canvas canvas, Size size, WeatherCardAtmosphere atm) {
    final p =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 0.42;
    for (var i = 0; i < 8; i++) {
      final center = Offset(
        (_cardUnit(i * 43 + 7) * size.width +
                math.sin(elapsed * 0.16 + i) * 2.5) %
            size.width,
        ((elapsed * (0.025 + _cardUnit(i * 11) * 0.02) + _cardUnit(i * 31)) %
                    1.2 -
                0.1) *
            size.height,
      );
      final r = 1.1 + _cardUnit(i * 17) * 1.7;
      p.color = atm.particle.withValues(alpha: 0.18 + _cardUnit(i * 23) * 0.18);
      for (var spoke = 0; spoke < 3; spoke++) {
        final angle = math.pi / 3 * spoke;
        final delta = Offset(math.cos(angle), math.sin(angle)) * r;
        canvas.drawLine(center - delta, center + delta, p);
      }
    }
  }

  @override
  bool shouldRepaint(_CardParticlePainter old) {
    return !hasSamePortalWeatherVisuals(old.weather, weather) ||
        old.elapsed != elapsed;
  }
}

double _cardUnit(num seed) {
  return (math.sin(seed * 12.9898) * 43758.5453123).abs() % 1.0;
}
