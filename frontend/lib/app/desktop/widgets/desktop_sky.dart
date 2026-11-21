import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 首页天象的条件档（样例 `Sky.tsx` 的 `PROFILE`）。
enum DesktopSkyCondition {
  clear,
  partly,
  cloudy,
  fog,
  drizzle,
  rain,
  snow,
  storm,
}

/// 由天气文本与 QWeather 图标码推断条件档。
///
/// 后端下发的是文本 + 图标码而不是枚举，这里做一次性归一，
/// 天象绘制只认这八档。
DesktopSkyCondition desktopSkyConditionOf({
  required String iconCode,
  required String text,
}) {
  final code = int.tryParse(iconCode.trim()) ?? 0;
  if (code >= 300 && code <= 399) {
    if (code >= 313 || code == 312 || code == 311) {
      return DesktopSkyCondition.rain;
    }
    return code <= 305 ? DesktopSkyCondition.drizzle : DesktopSkyCondition.rain;
  }
  if (code >= 400 && code <= 499) {
    return DesktopSkyCondition.snow;
  }
  if (code >= 500 && code <= 515) {
    return DesktopSkyCondition.fog;
  }
  if (code == 100 || code == 150) {
    return DesktopSkyCondition.clear;
  }
  if (code == 101 || code == 102 || code == 103 || code == 151 || code == 152) {
    return DesktopSkyCondition.partly;
  }
  if (code == 104 || code == 153) {
    return DesktopSkyCondition.cloudy;
  }
  final lower = text.toLowerCase();
  if (lower.contains('雷') ||
      lower.contains('storm') ||
      lower.contains('thunder')) {
    return DesktopSkyCondition.storm;
  }
  if (lower.contains('雪') || lower.contains('snow')) {
    return DesktopSkyCondition.snow;
  }
  if (lower.contains('雨') || lower.contains('rain')) {
    return DesktopSkyCondition.rain;
  }
  if (lower.contains('雾') || lower.contains('霾') || lower.contains('fog')) {
    return DesktopSkyCondition.fog;
  }
  if (lower.contains('阴') || lower.contains('overcast')) {
    return DesktopSkyCondition.cloudy;
  }
  if (lower.contains('云') || lower.contains('cloud')) {
    return DesktopSkyCondition.partly;
  }
  return DesktopSkyCondition.clear;
}

/// 程序化天象（样例 `Sky`）：时段渐变、星野、日月弧、云团、降水与远山。
///
/// 只画一幅静态帧再靠控制器缓慢推进相位：没有逐帧物理模拟，
/// 27 寸屏上也只有一层 CustomPaint 在重绘。
class DesktopSky extends StatefulWidget {
  const DesktopSky({
    required this.condition,
    required this.hour,
    required this.isDay,
    required this.reduceMotion,
    super.key,
  });

  final DesktopSkyCondition condition;

  /// 0-24 的小数小时。
  final double hour;
  final bool isDay;
  final bool reduceMotion;

  @override
  State<DesktopSky> createState() => _DesktopSkyState();
}

class _DesktopSkyState extends State<DesktopSky>
    with SingleTickerProviderStateMixin {
  // 循环周期而非过渡时长：云层与降水需要持续相位，归零会停在死帧。
  late final AnimationController _phase = AnimationController(
    duration: MotionToken.chart * 60,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DesktopSky oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate =
        !widget.reduceMotion && !MotionToken.prefersReducedOnPlatform();
    if (animate) {
      if (!_phase.isAnimating) {
        _phase.repeat();
      }
    } else {
      _phase.stop();
      _phase.value = 0.2;
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profiles[widget.condition]!;
    // 像素中性拆层：不依赖 phase 的部分（底/灰纱、日月、雾、远山）各成
    // 静态保留边界只录一次；依赖 phase 的部分（星闪、云、降水）单独成
    // 动态边界。**层序与原单幅 paint 的 interleaving 逐字一致**，故像素
    // 不变，只是逐帧重录量从数百 op 降到星/云/降水子集。
    Widget layer(_SkyPart part, {required bool animated}) {
      Widget paintAt(double phase) => CustomPaint(
        painter: _SkyPainter(
          part: part,
          condition: widget.condition,
          hour: widget.hour,
          isDay: widget.isDay,
          phase: phase,
        ),
        child: const SizedBox.expand(),
      );
      if (!animated) {
        return RepaintBoundary(child: paintAt(0));
      }
      // painter 必须在 builder 内按当前相位重建：复用同一 painter 实例
      // 会让 RenderCustomPaint 认为无变化而不重绘。
      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: _phase,
          builder: (context, _) => paintAt(_phase.value),
        ),
      );
    }

    final starsActive = !widget.isDay;
    final cloudsActive = profile.cloud > 0;
    final precipActive = profile.rain > 0.02 || profile.snow > 0.02;
    return Stack(
      fit: StackFit.expand,
      children: [
        layer(_SkyPart.base, animated: false),
        if (starsActive) layer(_SkyPart.stars, animated: true),
        layer(_SkyPart.body, animated: false),
        if (cloudsActive) layer(_SkyPart.clouds, animated: true),
        layer(_SkyPart.fog, animated: false),
        if (precipActive) layer(_SkyPart.precip, animated: true),
        layer(_SkyPart.ridges, animated: false),
        // 闪电是唯一画在远山之上的层（样例在 ridges 之后 fillRect）。
        if (profile.lightning > 0) layer(_SkyPart.lightning, animated: true),
      ],
    );
  }
}

/// 天象的分层部件。顺序即原单幅 paint 的绘制顺序，拆层不得重排。
enum _SkyPart { base, stars, body, clouds, fog, precip, ridges, lightning }

class _SkyProfile {
  const _SkyProfile(
    this.cloud,
    this.grey,
    this.rain,
    this.snow,
    this.fog, [
    this.lightning = 0,
  ]);

  final double cloud;
  final double grey;
  final double rain;
  final double snow;
  final double fog;

  /// 雷暴闪电强度档（样例只在 `cur.storm > 0.5` 时打闪）。
  final double lightning;
}

const Map<DesktopSkyCondition, _SkyProfile> _profiles = {
  DesktopSkyCondition.clear: _SkyProfile(0.15, 0, 0, 0, 0),
  DesktopSkyCondition.partly: _SkyProfile(0.55, 0.08, 0, 0, 0),
  DesktopSkyCondition.cloudy: _SkyProfile(1, 0.5, 0, 0, 0),
  DesktopSkyCondition.fog: _SkyProfile(0.7, 0.45, 0, 0, 1),
  DesktopSkyCondition.drizzle: _SkyProfile(1, 0.5, 0.35, 0, 0.15),
  DesktopSkyCondition.rain: _SkyProfile(1, 0.62, 1, 0, 0),
  DesktopSkyCondition.snow: _SkyProfile(0.95, 0.42, 0, 1, 0.2),
  DesktopSkyCondition.storm: _SkyProfile(1, 0.78, 1, 0, 0, 1),
};

class _SkyPainter extends CustomPainter {
  const _SkyPainter({
    required this.part,
    required this.condition,
    required this.hour,
    required this.isDay,
    required this.phase,
  });

  final _SkyPart part;
  final DesktopSkyCondition condition;
  final double hour;
  final bool isDay;
  final double phase;

  List<Color> _gradient() {
    if (!isDay) {
      return const [
        DesktopPalette.skyNightTop,
        DesktopPalette.skyNightMid,
        DesktopPalette.skyNightLow,
      ];
    }
    if (hour < 8) {
      return const [
        DesktopPalette.skyDawnTop,
        DesktopPalette.skyDawnMid,
        DesktopPalette.skyDawnLow,
      ];
    }
    if (hour < 17) {
      return const [
        DesktopPalette.skyDayTop,
        DesktopPalette.skyDayMid,
        DesktopPalette.skyDayLow,
      ];
    }
    if (hour < 19.5) {
      return const [
        DesktopPalette.skyDuskTop,
        DesktopPalette.skyDuskMid,
        DesktopPalette.skyDuskLow,
      ];
    }
    return const [
      DesktopPalette.skyLateTop,
      DesktopPalette.skyLateMid,
      DesktopPalette.skyLateLow,
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final profile = _profiles[condition]!;
    final colors = _gradient();
    switch (part) {
      case _SkyPart.base:
        _paintBase(canvas, size, profile, colors);
      case _SkyPart.stars:
        _paintStars(canvas, size, profile);
      case _SkyPart.body:
        _paintBody(canvas, size, profile, colors);
      case _SkyPart.clouds:
        _paintClouds(canvas, size, profile);
      case _SkyPart.fog:
        _paintFog(canvas, size, profile);
      case _SkyPart.precip:
        _paintPrecip(canvas, size, profile);
      case _SkyPart.ridges:
        _paintRidges(canvas, size);
      case _SkyPart.lightning:
        _paintLightning(canvas, size, profile);
    }
  }

  /// 雷暴闪电（样例 `Sky.tsx:80-93`）：按「每约 6 秒一次、0.9/帧 衰减」的
  /// 节奏换算成相位驱动的确定性函数——相位是唯一时间源，不额外挂控制器，
  /// 也不随帧率变速。折线用本次闪电的序号做随机种子，同一次内不抖动。
  void _paintLightning(Canvas canvas, Size size, _SkyProfile profile) {
    if (size.isEmpty || profile.lightning <= 0) {
      return;
    }
    // 与 `_phase` 的周期一致：chart * 60。
    final totalSeconds = (MotionToken.chart * 60).inMilliseconds / 1000.0;
    const slotSeconds = 6.0;
    final t = phase * totalSeconds;
    final slot = (t / slotSeconds).floor();
    final local = t - slot * slotSeconds;
    final dice = math.Random(slot * 7919 + 13);
    // 每次窗口有一半概率真的打闪，避免机械的等间隔。
    if (dice.nextDouble() < 0.45) {
      return;
    }
    // 0.9^(local/0.016) 近似样例的逐帧衰减。
    final flash = math.pow(0.9, local / 0.016).toDouble();
    if (flash <= 0.01) {
      return;
    }
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0xFFDFE8FF).withValues(alpha: flash * 0.55),
    );
    if (flash <= 0.7) {
      return;
    }
    final bolt = math.Random(slot * 104729 + 7);
    var bx = size.width * (0.3 + bolt.nextDouble() * 0.4);
    var by = 0.0;
    final path = Path()..moveTo(bx, by);
    while (by < size.height * 0.68) {
      bx += (bolt.nextDouble() - 0.5) * size.width * 0.02;
      by += size.height * 0.034;
      path.lineTo(bx, by);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFF4F7FF).withValues(alpha: flash),
    );
  }

  void _paintBase(
    Canvas canvas,
    Size size,
    _SkyProfile profile,
    List<Color> colors,
  ) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: const [0.0, 0.6, 1.0],
        ).createShader(rect),
    );

    if (profile.grey > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = (isDay
                  ? DesktopPalette.skyOvercastDay
                  : DesktopPalette.skyOvercastNight)
              .withValues(alpha: profile.grey),
      );
    }
  }

  void _paintStars(Canvas canvas, Size size, _SkyProfile profile) {
    final random = math.Random(7);
    final starPaint = Paint()..color = DesktopPalette.onStage;
    for (var i = 0; i < 130; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height * 0.62;
      final radius = random.nextDouble() * 1.2 + 0.3;
      final twinkle = 0.45 + 0.55 * math.sin(phase * math.pi * 2 * 3 + i).abs();
      starPaint.color = DesktopPalette.onStage.withValues(
        alpha: (twinkle * (1 - profile.cloud * 0.95)).clamp(0.0, 1.0),
      );
      canvas.drawCircle(Offset(x, y), radius, starPaint);
    }
  }

  void _paintBody(
    Canvas canvas,
    Size size,
    _SkyProfile profile,
    List<Color> colors,
  ) {
    final dim = (1 - profile.cloud * 0.55 - profile.grey * 0.2).clamp(0.0, 1.0);
    // 日月沿弧线走：白天 5.5→20.5，夜间取补段。
    final progress =
        isDay
            ? ((hour - 5.5) / 15).clamp(0.0, 1.0)
            : (((hour + 24 - 20.5) % 24) / 9).clamp(0.0, 1.0);
    final bodyX = size.width * (0.15 + progress * 0.7);
    final bodyY = size.height * (0.78 - math.sin(progress * math.pi) * 0.55);
    final bodyRadius = isDay ? 26.0 : 18.0;
    final glow =
        Paint()
          ..shader = RadialGradient(
            colors: [
              (isDay ? DesktopPalette.sunGlow : DesktopPalette.moonGlow)
                  .withValues(alpha: dim * (isDay ? 0.55 : 0.28)),
              DesktopPalette.onStage.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(bodyX, bodyY),
              radius: bodyRadius * 5,
            ),
          );
    canvas.drawCircle(Offset(bodyX, bodyY), bodyRadius * 5, glow);
    canvas.drawCircle(
      Offset(bodyX, bodyY),
      bodyRadius,
      Paint()
        ..color = (isDay ? DesktopPalette.sunBody : DesktopPalette.moonBody)
            .withValues(alpha: dim),
    );
    if (!isDay) {
      canvas.drawCircle(
        Offset(bodyX + bodyRadius * 0.42, bodyY - bodyRadius * 0.2),
        bodyRadius * 0.88,
        Paint()..color = colors.first,
      );
    }
  }

  void _paintClouds(Canvas canvas, Size size, _SkyProfile profile) {
    // 云团：五瓣径向渐变叠成一朵，随相位横向漂移。
    final heavy = math.max(
      profile.rain,
      math.max(profile.snow * 0.6, profile.grey),
    );
    for (var i = 0; i < 7; i++) {
      final seed = math.Random(31 + i);
      final visibility = (profile.cloud * (0.4 + (i % 3) * 0.3)).clamp(
        0.0,
        1.0,
      );
      if (visibility < 0.02) {
        continue;
      }
      final speed = 0.004 + seed.nextDouble() * 0.008;
      final x =
          ((seed.nextDouble() + phase * speed * 26) % 1.3 - 0.15) * size.width;
      final y = (0.08 + seed.nextDouble() * 0.3) * size.height;
      final width = size.width * 0.22 * (0.6 + seed.nextDouble() * 0.9);
      final tone =
          isDay
              ? (heavy > 0.5
                  ? DesktopPalette.cloudHeavyDay
                  : DesktopPalette.cloudLightDay)
              : (heavy > 0.5
                  ? DesktopPalette.cloudHeavyNight
                  : DesktopPalette.cloudLightNight);
      for (var petal = 0; petal < 5; petal++) {
        final cx = x + (petal - 2) * width * 0.22;
        final cy = y + math.sin(petal * 2.1 + i) * width * 0.05;
        final radius = width * (0.26 - (petal - 2).abs() * 0.03);
        canvas.drawCircle(
          Offset(cx, cy),
          radius,
          Paint()
            ..shader = RadialGradient(
              colors: [
                tone.withValues(alpha: 0.5 * visibility * (isDay ? 0.9 : 0.5)),
                tone.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: Offset(cx, cy), radius: radius),
            ),
        );
      }
    }
  }

  void _paintFog(Canvas canvas, Size size, _SkyProfile profile) {
    if (profile.fog > 0.02) {
      for (var band = 0; band < 4; band++) {
        final y = size.height * (0.45 + band * 0.13);
        final height = size.height * 0.14;
        final tone = isDay ? DesktopPalette.fogDay : DesktopPalette.fogNight;
        canvas.drawRect(
          Rect.fromLTWH(0, y - height, size.width, height * 2),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tone.withValues(alpha: 0),
                tone.withValues(alpha: 0.42 * profile.fog),
                tone.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTWH(0, y - height, size.width, height * 2),
            ),
        );
      }
    }
  }

  void _paintPrecip(Canvas canvas, Size size, _SkyProfile profile) {
    if (profile.rain > 0.02) {
      final paint =
          Paint()
            ..color = DesktopPalette.precipitation.withValues(
              alpha: 0.45 * profile.rain,
            )
            ..strokeWidth = 1;
      for (var i = 0; i < 200; i++) {
        final seed = math.Random(101 + i);
        final x = seed.nextDouble() * size.width;
        final y =
            ((seed.nextDouble() + phase * (1.4 + seed.nextDouble())) % 1) *
            size.height;
        canvas.drawLine(
          Offset(x, y),
          Offset(x - size.width * 0.004, y + size.height * 0.035),
          paint,
        );
      }
    }

    if (profile.snow > 0.02) {
      for (var i = 0; i < 130; i++) {
        final seed = math.Random(211 + i);
        final radius = 0.8 + seed.nextDouble() * 2.2;
        final x =
            (seed.nextDouble() + math.sin(phase * math.pi * 2 + i) * 0.01) *
            size.width;
        final y =
            ((seed.nextDouble() + phase * (0.5 + seed.nextDouble())) % 1) *
            size.height;
        canvas.drawCircle(
          Offset(x, y),
          radius,
          Paint()
            ..color = DesktopPalette.onStage.withValues(
              alpha: (0.35 + radius / 3 * 0.55) * profile.snow,
            ),
        );
      }
    }
  }

  void _paintRidges(Canvas canvas, Size size) {
    // 远山三层：夜色更沉，雪后山脊描一道白。
    final ridges = <(double, double, double, Color)>[
      (
        0.72,
        0.14,
        2.1,
        isDay ? DesktopPalette.ridgeFarDay : DesktopPalette.ridgeFarNight,
      ),
      (
        0.80,
        0.10,
        3.3,
        isDay ? DesktopPalette.ridgeMidDay : DesktopPalette.ridgeMidNight,
      ),
      (
        0.90,
        0.07,
        4.7,
        isDay ? DesktopPalette.ridgeNearDay : DesktopPalette.ridgeNearNight,
      ),
    ];
    for (final ridge in ridges) {
      final path = Path()..moveTo(0, size.height);
      for (var x = 0.0; x <= size.width; x += 12) {
        final n = x / size.width;
        final y =
            size.height *
            (ridge.$1 +
                math.sin(n * ridge.$3 * 3 + ridge.$3) * ridge.$2 * 0.4 +
                math.sin(n * ridge.$3 * 7.3) * ridge.$2 * 0.12);
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = ridge.$4);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) =>
      oldDelegate.part != part ||
      oldDelegate.phase != phase ||
      oldDelegate.condition != condition ||
      oldDelegate.hour != hour ||
      oldDelegate.isDay != isDay;
}
