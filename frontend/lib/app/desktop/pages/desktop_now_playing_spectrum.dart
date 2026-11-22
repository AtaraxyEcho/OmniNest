import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:omninest/features/music/application/music_spectrum_analyzer.dart';

/// 新版样例 5 层频谱脉动背景（零逐帧 Blur，对照 `Wallpaper.tsx` & `audioBus.ts`）：
/// - 读取 `musicSpectrumFeedProvider` 的真实 `nativeFft` 32 频段镜像重采样为 56 点对称山峰
///   （中心低频、两侧高频），并用 `frame.beat` 触发 `onset`；静音/无真实信号自动回退种子 BPM 模拟；
/// - 双级阻尼状态机：`hit`（4.5/s）、`pulse`（0.9/s）、`beat`（3.2/1.3）、`glow`（1.6）；
/// - 预烘焙 `64×64` `ui.Image` 柔光 Sprite（仅 `|sprH - h0| > 3°` 时离屏重绘，dispose 释放）；
/// - 五层渲染：深空底+底部暖光晕 → 14 颗景深散景光斑 → 最多 90 颗峰顶火花 →
///   4 层半透明频谱丝带（`0.96H` 升起、`maxH = 0.58H`，上升 `2.5×` 回落 `1.0×`，3 点平滑 + 二次贝塞尔，
///   L0 叠宽柔光描边与亮白细峰线）。
class NpSpectrumBackdrop extends ConsumerStatefulWidget {
  const NpSpectrumBackdrop({
    required this.hueColor,
    required this.playing,
    required this.seed,
    super.key,
  });

  final Color hueColor;
  final bool playing;
  final String seed;

  @override
  ConsumerState<NpSpectrumBackdrop> createState() => _NpSpectrumBackdropState();
}

class _NpSpectrumBackdropState extends ConsumerState<NpSpectrumBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final _SpectrumState _state;
  Duration? _lastElapsed;
  ValueListenable<MusicSpectrumFrame>? _feed;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _state = _SpectrumState(
      initialHue: HSLColor.fromColor(widget.hueColor).hue,
      seed: widget.seed,
    );
    _ticker = createTicker(_onTick);
    _scheduleSpriteBake(_state.h0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  void _bindFeed(ValueListenable<MusicSpectrumFrame> next) {
    if (identical(_feed, next)) return;
    _feed?.removeListener(_onFeedUpdate);
    _feed = next;
    _feed?.addListener(_onFeedUpdate);
  }

  void _onFeedUpdate() {
    // 保持对 MusicSpectrumSampler 的活跃监听以解锁底层原生 FFT 采样，
    // 实际画面更新仍由 _ticker 按刷新率统一步进。
  }

  @override
  void didUpdateWidget(NpSpectrumBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) {
      _state.updateSeed(widget.seed);
      _state.resetAudioTracking();
    } else if (!oldWidget.playing && widget.playing) {
      _state.resetAudioTracking();
    }
    _syncTicker();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _state.stepStill(
        playing: widget.playing,
        targetHue: HSLColor.fromColor(widget.hueColor).hue,
        frame: _feed?.value,
      );
      if ((_state.sprH - _state.h0).abs() > 3.0) {
        _scheduleSpriteBake(_state.h0);
      }
    }
  }

  void _syncTicker() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!reduceMotion && !_ticker.isActive) {
      _lastElapsed = null;
      _ticker.start();
    } else if (reduceMotion && _ticker.isActive) {
      _ticker.stop();
      _lastElapsed = null;
    }
  }

  void _onTick(Duration elapsed) {
    final prev = _lastElapsed;
    _lastElapsed = elapsed;
    final dt =
        prev == null
            ? 0.016
            : ((elapsed - prev).inMicroseconds / 1000000.0).clamp(0.0, 0.05);
    if (dt <= 0) return;

    _state.step(
      dt: dt,
      playing: widget.playing,
      targetHue: HSLColor.fromColor(widget.hueColor).hue,
      frame: _feed?.value,
    );
    if ((_state.sprH - _state.h0).abs() > 3.0 && !_state.spriteBaking) {
      _scheduleSpriteBake(_state.h0);
    }
  }

  void _scheduleSpriteBake(double hue) {
    if (_disposed || _state.spriteBaking) return;
    _state.spriteBaking = true;
    _state.sprH = hue;
    unawaited(
      _bakeSoftGlowSprite(hue)
          .then((image) {
            if (_disposed) {
              image.dispose();
              return;
            }
            _state.replaceSprite(image, hue);
          })
          .catchError((Object _) {
            _state.spriteBaking = false;
          }),
    );
  }

  static Future<ui.Image> _bakeSoftGlowSprite(double h0) async {
    const size = 64.0;
    const center = Offset(32, 32);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint =
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              HSLColor.fromAHSL(1.0, (h0 + 25.0) % 360.0, 0.95, 0.88).toColor(),
              HSLColor.fromAHSL(
                0.55,
                (h0 + 15.0) % 360.0,
                0.90,
                0.70,
              ).toColor(),
              HSLColor.fromAHSL(0.0, h0 % 360.0, 0.90, 0.60).toColor(),
            ],
            stops: const <double>[0.0, 0.25, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: 32));
    canvas.drawRect(const Rect.fromLTWH(0, 0, size, size), paint);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(64, 64);
    } finally {
      picture.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _feed?.removeListener(_onFeedUpdate);
    _feed = null;
    _ticker.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _bindFeed(ref.watch(musicSpectrumFeedProvider));
    return RepaintBoundary(
      child: CustomPaint(
        painter: _NpSpectrumPainter(state: _state),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RibbonLayerConfig {
  const _RibbonLayerConfig({
    required this.follow,
    required this.amp,
    required this.dh,
    required this.alpha,
  });

  final double follow;
  final double amp;
  final double dh;
  final double alpha;
}

class _BokehOrb {
  _BokehOrb({
    required this.x,
    required this.y,
    required this.z,
    required this.r,
    required this.v,
    required this.p,
    required this.sw,
  });

  final double x;
  double y;
  final double z;
  final double r;
  final double v;
  final double p;
  final double sw;
}

class _CrestSpark {
  _CrestSpark({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.maxLife,
    required this.scale,
  });

  /// 归一化坐标 `0..1`（在绘制阶段乘以画布宽高，适配任意缩放与首帧尺寸未知）。
  double x;
  double y;
  double vx;
  double vy;
  double life;
  final double maxLife;
  final double scale;
}

class _SpectrumState extends ChangeNotifier {
  _SpectrumState({required double initialHue, required String seed})
    : h0 = initialHue {
    updateSeed(seed);
  }

  static const int pointCount = 56;
  static const int maxSparks = 90;
  static const List<_RibbonLayerConfig> layers = <_RibbonLayerConfig>[
    _RibbonLayerConfig(follow: 12.0, amp: 1.0, dh: 0.0, alpha: 0.50),
    _RibbonLayerConfig(follow: 7.0, amp: 0.82, dh: 22.0, alpha: 0.42),
    _RibbonLayerConfig(follow: 5.0, amp: 0.62, dh: 48.0, alpha: 0.36),
    _RibbonLayerConfig(follow: 3.5, amp: 0.40, dh: -26.0, alpha: 0.30),
  ];

  final Float32List target = Float32List(pointCount);
  final Float32List bands = Float32List(pointCount);
  final List<Float32List> vals = List<Float32List>.generate(
    layers.length,
    (_) => Float32List(pointCount),
    growable: false,
  );
  final Float32List crestNormY = Float32List(pointCount);
  final List<_CrestSpark> sparks = <_CrestSpark>[];
  final math.Random _rand = math.Random();
  List<_BokehOrb> orbs = <_BokehOrb>[];

  double h0;
  double sprH = -999.0;
  bool spriteBaking = false;
  ui.Image? sprite;

  double t = 0.0;
  double idle = 0.0;
  double hit = 0.0;
  double pulse = 0.0;
  double beat = 0.0;
  double glow = 0.0;
  double nextBeat = 0.0;

  int _sd = 7;
  int _bpm = 108;

  // 真实音频自动增益与静音回退状态（对齐 audioBus.ts）。
  double _peak = 0.35;
  double _bassAvg = 0.0;
  double _lastOnsetAt = -10.0;
  int _silentFrames = 0;

  void resetAudioTracking() {
    _peak = 0.35;
    _bassAvg = 0.0;
    _lastOnsetAt = -10.0;
    _silentFrames = 0;
  }

  void updateSeed(String seed) {
    var sd = 7;
    for (final unit in seed.codeUnits) {
      sd = (sd * 31 + unit) & 0xFFFFFFFF;
    }
    _sd = sd;
    _bpm = 92 + (sd % 36);
    orbs = List<_BokehOrb>.generate(14, (i) {
      final z = _rnd(i + 5.0);
      return _BokehOrb(
        x: _rnd(i.toDouble()),
        y: _rnd(i + 50.0),
        z: z,
        r: 0.008 + z * 0.02,
        v: 0.01 + z * 0.035,
        p: _rnd(i + 3.0) * 6.28,
        sw: 0.01 + _rnd(i + 8.0) * 0.03,
      );
    }, growable: false);
    for (var i = 0; i < pointCount; i++) {
      crestNormY[i] = 0.94;
    }
  }

  double _rnd(double i) {
    final v = math.sin(i * 127.1 + _sd) * 43758.5453;
    return v - v.floorToDouble();
  }

  void replaceSprite(ui.Image next, double hue) {
    final old = sprite;
    sprite = next;
    sprH = hue;
    spriteBaking = false;
    old?.dispose();
    notifyListeners();
  }

  /// 读取真实 `nativeFft` 32 频段并镜像重采样为 56 点对称山峰（中心低频、两侧高频）。
  /// 无真实信号或连续静音超过 20 帧返回 null，自动回退种子 BPM 模拟。
  double? _readRealOnset(MusicSpectrumFrame? frame) {
    if (frame == null ||
        !frame.active ||
        frame.source != MusicSpectrumSource.nativeFft ||
        frame.bands.isEmpty) {
      _silentFrames = 21;
      return null;
    }
    final src = frame.bands;
    final srcMaxIdx = src.length - 1;
    var maxVal = 0.0;
    for (var i = 0; i < pointCount; i++) {
      // f = 0（中心低频）.. 1（两侧高频）。
      final f = ((i / (pointCount - 1)) - 0.5).abs() * 2.0;
      final pos = f * srcMaxIdx;
      final lo = pos.floor().clamp(0, srcMaxIdx);
      final hi = math.min(srcMaxIdx, lo + 1);
      final frac = pos - lo;
      final raw = (src[lo] * (1.0 - frac) + src[hi] * frac).clamp(0.0, 1.0);
      bands[i] = raw;
      if (raw > maxVal) maxVal = raw;
    }
    if (maxVal < 0.02) {
      _silentFrames += 1;
      if (_silentFrames > 20) return null;
    } else {
      _silentFrames = 0;
    }
    // 自动增益：快升慢落（audioBus.ts:37）。
    final targetPeak = math.max(maxVal, 0.2);
    _peak += (targetPeak - _peak) * (maxVal > _peak ? 0.2 : 0.035);
    final invPeak = _peak > 1e-4 ? 1.0 / _peak : 1.0;
    for (var i = 0; i < pointCount; i++) {
      final v = (bands[i] * invPeak).clamp(0.0, 1.0);
      bands[i] = math.pow(v, 0.82).toDouble();
    }

    var onset = 0.0;
    final bass = frame.bass.clamp(0.0, 1.0);
    final frameBeat = frame.beat.clamp(0.0, 1.0);
    if ((idle - _lastOnsetAt) > 0.18) {
      if (frameBeat > 0.22) {
        onset = frameBeat;
        _lastOnsetAt = idle;
      } else if (bass > _bassAvg * 1.18 + 0.03) {
        onset = ((bass - _bassAvg) * 3.0).clamp(0.0, 1.0);
        _lastOnsetAt = idle;
      }
    }
    _bassAvg += (bass - _bassAvg) * 0.06;
    return onset;
  }

  double _crestYNormAt(double nx) {
    final idx = (nx * (pointCount - 1)).round().clamp(0, pointCount - 1);
    return crestNormY[idx];
  }

  void _emitSparks(int count, double power) {
    for (var k = 0; k < count && sparks.length < maxSparks; k++) {
      final px = 0.5 + (_rnd(sparks.length + t * 10.0 + k) - 0.5) * 0.8;
      final life = 0.9 + _rand.nextDouble() * 0.9;
      sparks.add(
        _CrestSpark(
          x: px.clamp(0.02, 0.98),
          y: _crestYNormAt(px),
          vx: (_rand.nextDouble() - 0.5) * 0.05,
          vy: -(0.12 + _rand.nextDouble() * 0.22) * power,
          life: life,
          maxLife: life,
          scale: 0.6 + _rand.nextDouble() * 1.1,
        ),
      );
    }
  }

  void step({
    required double dt,
    required bool playing,
    required double targetHue,
    required MusicSpectrumFrame? frame,
  }) {
    final dh = ((targetHue - h0 + 540.0) % 360.0) - 180.0;
    h0 = (h0 + dh * math.min(1.0, dt * 1.5) + 360.0) % 360.0;
    idle += dt;

    final realOnset = playing ? _readRealOnset(frame) : null;
    if (realOnset != null) {
      t += dt;
      if (realOnset > 0) {
        hit = math.max(hit, 0.65 + 0.35 * realOnset);
        pulse = math.max(pulse, 0.38 + 0.42 * realOnset);
        _emitSparks(2 + (realOnset * 2).round(), 0.7 + realOnset * 0.25);
      }
    } else if (playing) {
      t += dt;
      nextBeat -= dt;
      if (nextBeat <= 0) {
        hit = 1.0;
        pulse = 0.7;
        _emitSparks(3, 0.7);
        nextBeat =
            (60.0 / _bpm) *
            (_rnd((t * 3.0).floorToDouble()) < 0.22 ? 0.5 : 1.0);
      }
    }

    // 双级阻尼状态机（Wallpaper.tsx:126-127）。
    hit = math.max(0.0, hit - dt * 4.5);
    pulse = math.max(0.0, pulse - dt * 0.9);
    beat += (pulse - beat) * math.min(1.0, dt * (pulse > beat ? 3.2 : 1.3));
    glow += (beat - glow) * math.min(1.0, dt * 1.6);

    for (var i = 0; i < pointCount; i++) {
      final f = ((i / (pointCount - 1)) - 0.5).abs() * 2.0;
      final env = math.pow(1.0 - f, 0.8).toDouble() * 0.85 + 0.15;
      final tk = t * (7.0 + f * 9.0) + i * 3.1;
      final k0 = tk.floor();
      final frac = tk - k0;
      final n =
          _rnd(i * 17.0 + k0) * (1.0 - frac) + _rnd(i * 17.0 + k0 + 1.0) * frac;
      target[i] =
          realOnset != null
              ? math.min(1.0, 0.05 + bands[i] * (0.6 + 0.4 * env))
              : playing
              ? math.min(
                1.0,
                (0.1 + n * 0.6 + hit * math.pow(1.0 - f, 1.2) * 0.6) * env,
              )
              : 0.05 + 0.02 * math.sin(idle * 0.8 + i * 0.3);
    }

    // 更新 14 颗景深散景光斑。
    final orbFactor = playing ? 1.0 + beat * 0.4 : 0.35;
    for (final orb in orbs) {
      orb.y -= orb.v * dt * orbFactor;
      if (orb.y < -0.1) orb.y = 1.1;
    }

    // 更新峰顶火花。
    for (var i = sparks.length - 1; i >= 0; i--) {
      final s = sparks[i];
      s.life -= dt;
      if (s.life <= 0) {
        sparks.removeAt(i);
        continue;
      }
      s.vx *= 1.0 - dt * 0.8;
      s.vy *= 1.0 - dt * 1.1;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
    }

    // 更新 4 层频谱丝带值（上升 3.0×、回落 1.35×）并记录 L0 峰顶归一化 Y。
    for (var li = layers.length - 1; li >= 0; li--) {
      final cfg = layers[li];
      final v = vals[li];
      for (var i = 0; i < pointCount; i++) {
        final rising = target[i] > v[i];
        final alpha = math.min(1.0, dt * cfg.follow * (rising ? 3.0 : 1.35));
        v[i] += (target[i] - v[i]) * alpha;
      }
      if (li == 0) {
        for (var i = 0; i < pointCount; i++) {
          final left = v[math.max(0, i - 1)];
          final right = v[math.min(pointCount - 1, i + 1)];
          final smooth = v[i] * 0.5 + (left + right) * 0.25;
          crestNormY[i] = 0.96 - math.max(0.01, smooth) * 0.58 * cfg.amp;
        }
      }
    }

    notifyListeners();
  }

  void stepStill({
    required bool playing,
    required double targetHue,
    required MusicSpectrumFrame? frame,
  }) {
    h0 = targetHue;
    step(dt: 0.016, playing: playing, targetHue: targetHue, frame: frame);
  }

  @override
  void dispose() {
    sprite?.dispose();
    sprite = null;
    super.dispose();
  }
}

class _NpSpectrumPainter extends CustomPainter {
  _NpSpectrumPainter({required this.state}) : super(repaint: state);

  final _SpectrumState state;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final w = size.width;
    final h = size.height;
    final h0 = state.h0;
    final glow = state.glow;
    final beat = state.beat;
    final idle = state.idle;

    // Layer 1：深空底 #05070B → hsl(h0, 45%, 9 + glow * 0.8%) + 底部中心暖光晕。
    final bottomLight = ((9.0 + glow * 0.8) / 100.0).clamp(0.05, 0.22);
    final bottomColor = HSLColor.fromAHSL(1.0, h0, 0.45, bottomLight).toColor();
    final bgRect = Offset.zero & size;
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[const Color(0xFF05070B), bottomColor],
        ).createShader(bgRect),
    );

    final glowCenter = Offset(w * 0.5, h);
    final glowRadius = math.max(1.0, h * (0.38 + glow * 0.05));
    final glowBase = HSLColor.fromAHSL(1.0, h0, 0.80, 0.55).toColor();
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.4, w, h * 0.6),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: <Color>[
            glowBase.withValues(alpha: (0.20 + glow * 0.07).clamp(0.0, 1.0)),
            glowBase.withValues(alpha: (0.07 + glow * 0.03).clamp(0.0, 1.0)),
            glowBase.withValues(alpha: 0.0),
          ],
          stops: const <double>[0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );

    final sprite = state.sprite;
    final srcRect =
        sprite == null
            ? Rect.zero
            : Rect.fromLTWH(
              0,
              0,
              sprite.width.toDouble(),
              sprite.height.toDouble(),
            );

    // Layer 2：14 颗景深散景光斑（使用预烘焙 64×64 Sprite，零逐帧 Blur）。
    if (sprite != null) {
      final maxSpan = math.max(w, h * 1.6);
      final orbPaint =
          Paint()
            ..blendMode = BlendMode.plus
            ..filterQuality = FilterQuality.low;
      for (final orb in state.orbs) {
        final rr = orb.r * maxSpan * (1.0 + beat * 0.04 * orb.z);
        final cx = (orb.x + math.sin(idle * 0.4 + orb.p) * orb.sw) * w;
        final cy = orb.y * h;
        final alpha = ((0.06 + orb.z * 0.16) *
                (0.7 + 0.3 * math.sin(idle * 0.9 + orb.p)))
            .clamp(0.0, 1.0);
        orbPaint.color = Color.fromRGBO(255, 255, 255, alpha);
        canvas.drawImageRect(
          sprite,
          srcRect,
          Rect.fromLTWH(cx - rr, cy - rr, rr * 2, rr * 2),
          orbPaint,
        );
      }

      // Layer 3：最多 90 颗峰顶火花（Sprite 柔光 + 白色星核）。
      final sparkSpritePaint =
          Paint()
            ..blendMode = BlendMode.plus
            ..filterQuality = FilterQuality.low;
      final sparkCorePaint = Paint()..blendMode = BlendMode.plus;
      for (final s in state.sparks) {
        final k = (s.life / s.maxLife).clamp(0.0, 1.0);
        final sx = s.x * w;
        final sy = s.y * h;
        final r = (s.scale * (w / 480.0) + 0.8) * (0.4 + k);
        final haloAlpha = (k * k * 0.5).clamp(0.0, 1.0);
        sparkSpritePaint.color = Color.fromRGBO(255, 255, 255, haloAlpha);
        canvas.drawImageRect(
          sprite,
          srcRect,
          Rect.fromLTWH(sx - r * 3, sy - r * 3, r * 6, r * 6),
          sparkSpritePaint,
        );
        sparkCorePaint.color = Colors.white.withValues(
          alpha: (k * k * 0.25).clamp(0.0, 1.0),
        );
        canvas.drawRect(
          Rect.fromLTWH(sx - r * 0.25, sy - r * 0.25, r * 0.5, r * 0.5),
          sparkCorePaint,
        );
      }
    }

    // Layer 4：4 层半透明频谱丝带（后到前，0.96H 升起，maxH = 0.58H，3 点平滑 + 二次贝塞尔）。
    final base = h * 0.96;
    final maxH = h * 0.58;
    const n = _SpectrumState.pointCount;
    final step = w / (n - 1);

    for (var li = _SpectrumState.layers.length - 1; li >= 0; li--) {
      final cfg = _SpectrumState.layers[li];
      final v = state.vals[li];
      final hh = (h0 + cfg.dh + 360.0) % 360.0;

      double pt(int i) {
        final left = v[math.max(0, i - 1)];
        final right = v[math.min(n - 1, i + 1)];
        final smooth = v[i] * 0.5 + (left + right) * 0.25;
        return base - math.max(0.01, smooth) * maxH * cfg.amp;
      }

      final fillPath =
          Path()
            ..moveTo(0, h)
            ..lineTo(0, pt(0));
      for (var i = 1; i < n; i++) {
        final prevY = pt(i - 1);
        final currY = pt(i);
        final mx = (i - 0.5) * step;
        final my = (prevY + currY) * 0.5;
        fillPath.quadraticBezierTo((i - 1) * step, prevY, mx, my);
      }
      fillPath
        ..lineTo(w, pt(n - 1))
        ..lineTo(w, h)
        ..close();

      final topY = base - maxH * cfg.amp;
      final a = (cfg.alpha * (1.0 + glow * 0.1)).clamp(0.0, 1.0);
      final gradRect = Rect.fromLTRB(0, topY, w, h);
      final fillPaint =
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                HSLColor.fromAHSL(a, hh, 0.85, 0.66).toColor(),
                HSLColor.fromAHSL(
                  (a * 0.25).clamp(0.0, 1.0),
                  hh,
                  0.80,
                  0.50,
                ).toColor(),
                HSLColor.fromAHSL(0.0, hh, 0.80, 0.45).toColor(),
              ],
              stops: const <double>[0.0, 0.7, 1.0],
            ).createShader(gradRect);
      canvas.drawPath(fillPath, fillPaint);

      // L0 叠宽柔光描边与亮白细峰线（Wallpaper.tsx:170-177）。
      if (li == 0) {
        final crestPath = Path()..moveTo(0, pt(0));
        for (var i = 1; i < n; i++) {
          final prevY = pt(i - 1);
          final currY = pt(i);
          crestPath.quadraticBezierTo(
            (i - 1) * step,
            prevY,
            (i - 0.5) * step,
            (prevY + currY) * 0.5,
          );
        }
        crestPath.lineTo(w, pt(n - 1));

        canvas.drawPath(
          crestPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..blendMode = BlendMode.plus
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = math.max(5.0, w / 200.0)
            ..color =
                HSLColor.fromAHSL(
                  (0.10 + glow * 0.04).clamp(0.0, 1.0),
                  hh,
                  0.90,
                  0.70,
                ).toColor(),
        );
        canvas.drawPath(
          crestPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..blendMode = BlendMode.plus
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = math.max(1.5, w / 640.0)
            ..color = HSLColor.fromAHSL(0.70, hh, 0.90, 0.88).toColor(),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NpSpectrumPainter oldDelegate) =>
      oldDelegate.state != state;
}
