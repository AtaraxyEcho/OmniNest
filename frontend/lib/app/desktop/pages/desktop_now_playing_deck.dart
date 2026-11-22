part of 'desktop_now_playing_page.dart';

/// 唱机（样例 `.plinth`）：560 上限、1.05 比例的外壳，内部 80% 转盘、
/// 右侧唱臂、底部 LED 与曲序号。播放时唱臂落下并微摆、唱片 33⅓ RPM 旋转、
/// 封面氛围光晕缓慢呼吸。
class _Deck extends StatefulWidget {
  const _Deck({
    required this.spin,
    required this.cover,
    required this.playing,
    required this.hueColor,
    required this.index,
    required this.total,
  });

  final Animation<double> spin;
  final String? cover;
  final bool playing;

  /// 曲目色相（样例 `.deck-aura` 的 `--hue`），未提取时回落强调色。
  final Color hueColor;
  final int index;
  final int total;

  @override
  State<_Deck> createState() => _DeckState();
}

class _DeckState extends State<_Deck> with TickerProviderStateMixin {
  /// 唱臂播放态微摆（3.4s 周期，±0.35°）。
  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: MotionToken.resolveForPlatform(DesktopMotion.tonearmSway),
  );

  /// 封面氛围光晕 `.deck-aura` 呼吸周期（4.2s，透明度与 1.06 缩放）。
  late final AnimationController _aura = AnimationController(
    vsync: this,
    duration: MotionToken.resolveForPlatform(DesktopMotion.deckAura),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAmbient();
  }

  @override
  void didUpdateWidget(_Deck oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAmbient();
  }

  void _syncAmbient() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final run = widget.playing && !reduceMotion;
    if (run) {
      if (!_sway.isAnimating) {
        _sway.repeat(reverse: true);
      }
      if (!_aura.isAnimating) {
        _aura.repeat(reverse: true);
      }
    } else {
      if (_sway.isAnimating) _sway.stop();
      if (_aura.isAnimating) _aura.stop();
    }
  }

  @override
  void dispose() {
    _sway.dispose();
    _aura.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final playing = widget.playing;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxByHeight =
            constraints.maxHeight.isFinite
                ? constraints.maxHeight * 1.05
                : 560.0;
        final size = math
            .min(math.min(constraints.maxWidth, maxByHeight), 560.0)
            .clamp(0.0, 560.0);
        final height = size / 1.05;
        final platter = size * 0.8;
        final platterTop = size * 0.12;
        final glareInset = platter * 0.008;
        return Center(
          child: SizedBox(
            width: size,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 封面氛围背光 `.deck-aura`：极柔圆形环境背光，消除外围波动光圈。
                Positioned(
                  left: -size * 0.10,
                  right: -size * 0.10,
                  top: -size * 0.14,
                  bottom: -size * 0.14,
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _aura,
                        builder: (context, child) {
                          final wave =
                              playing
                                  ? Curves.easeInOutSine.transform(_aura.value)
                                  : 0.0;
                          final auraOpacity =
                              playing ? (0.36 + 0.12 * wave) : 0.30;
                          final auraScale =
                              playing ? (1.00 + 0.025 * wave) : 1.00;
                          return Transform.scale(
                            scale: auraScale,
                            child: Opacity(opacity: auraOpacity, child: child),
                          );
                        },
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                radius: 0.50,
                                colors: [
                                  widget.hueColor.withValues(alpha: 0.28),
                                  widget.hueColor.withValues(alpha: 0.06),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.72, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 唱机底座 `.plinth`：金属拉丝纹 + 顶部 1px white 0.08 内高光 + 底部内暗影。
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1D2328), Color(0xFF0F1316)],
                      ),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.65),
                          blurRadius: 60,
                          offset: const Offset(0, 30),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: const CustomPaint(
                        painter: _PlinthMetalPainter(),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                // 黑胶转盘（对齐 top: size * 0.12）。
                Positioned(
                  left: size * 0.04,
                  top: platterTop,
                  width: platter,
                  height: platter,
                  child: _Platter(
                    spin: widget.spin,
                    cover: widget.cover,
                    playing: playing,
                    size: platter,
                  ),
                ),
                // 静态反光 `.glare`：内缩对齐黑胶盘面，双瓣 SweepGradient + BlendMode.screen。
                Positioned(
                  left: size * 0.04 + glareInset,
                  top: platterTop + glareInset,
                  width: platter - glareInset * 2,
                  height: platter - glareInset * 2,
                  child: const IgnorePointer(
                    child: CustomPaint(
                      painter: _PlatterGlarePainter(),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
                // 唱臂 `.tonearm`：播放态落臂 37° 并叠加 3.4s (±0.35°) 微摆。
                Positioned(
                  left: size * 0.9,
                  top: size * 0.11,
                  child: AnimatedBuilder(
                    animation: _sway,
                    builder: (context, child) {
                      final swayDeg =
                          playing
                              ? (Curves.easeInOutSine.transform(_sway.value) *
                                          2 -
                                      1) *
                                  0.35
                              : 0.0;
                      return Transform.rotate(
                        angle: swayDeg * math.pi / 180,
                        alignment: Alignment.topLeft,
                        child: child,
                      );
                    },
                    child: AnimatedRotation(
                      turns: (playing ? 37 : -8) / 360,
                      duration: DesktopMotion.of(
                        context,
                        DesktopMotion.tonearm,
                      ),
                      curve: DesktopMotion.spring,
                      alignment: Alignment.topLeft,
                      child: _Tonearm(size: size, accent: skin.accent),
                    ),
                  ),
                ),
                // 底部状态 LED（亮态使用 skin.accent 及发光阴影）与转速标签。
                Positioned(
                  left: size * 0.06,
                  bottom: size * 0.034,
                  child: Row(
                    children: [
                      Container(
                        width: size * 0.014,
                        height: size * 0.014,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              playing ? skin.accent : const Color(0xFF3A2A2A),
                          boxShadow:
                              playing
                                  ? [
                                    BoxShadow(
                                      color: skin.accent.withValues(
                                        alpha: 0.72,
                                      ),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        playing ? '33⅓ RPM' : 'STANDBY',
                        style: DesktopType.nano(
                          Colors.white.withValues(alpha: 0.5),
                        ).copyWith(letterSpacing: 1.4),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: size * 0.05,
                  bottom: size * 0.034,
                  child: Text(
                    '${widget.index.toString().padLeft(2, '0')} / '
                    '${widget.total.toString().padLeft(2, '0')}',
                    style: DesktopType.numeric(
                      Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 新版样例 120 柱呼吸波形进度条（对照 `ui.tsx:250-283` 与 `more.css:185-198`）：
/// - 120 柱确定性正弦包络波形；
/// - 已播区 `hueColor` 纵向双色渐变（底 mix 55% → 顶 mix 20%）+ `.wave-glow` 呼吸底光；
/// - 播放头高斯邻域隆起（`exp(-(dPlay/4)²)`）+ `0.9s` 亮度脉动 + 悬停透镜放大（`exp(-(dHov/5)²)`）；
/// - 上下外溢 `8px` 渐隐播放头线 + `12px` 发光白色圆点（hover/drag `1.35×`）；
/// - `700ms` 点击扩散涟漪 `.wave-rip`；
/// - 纯白底 `#FFFFFF` / 深黑字 `#0A0C0E` `8px` 圆角时间气泡。
class _WaveSeek extends StatefulWidget {
  const _WaveSeek({
    required this.trackId,
    required this.hueColor,
    required this.position,
    required this.duration,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onCommit,
    this.onDragCancel,
    this.playing = false,
  });

  final String trackId;
  final Color hueColor;
  final Duration position;
  final Duration duration;
  final VoidCallback onDragStart;
  final ValueChanged<Duration> onDragUpdate;
  final ValueChanged<Duration> onCommit;
  final VoidCallback? onDragCancel;
  final bool playing;

  @override
  State<_WaveSeek> createState() => _WaveSeekState();
}

class _WaveSeekState extends State<_WaveSeek> with TickerProviderStateMixin {
  static const int _barCount = 120;

  Duration? _pendingPosition;
  double? _hoverFraction;
  double? _dragFraction;
  bool _hovered = false;
  bool _dragging = false;
  double? _rippleFraction;
  String _cachedSeed = '';
  List<double> _heights = const <double>[];

  late final AnimationController _activeCtrl = AnimationController(
    vsync: this,
    duration: MotionToken.resolveForPlatform(const Duration(milliseconds: 200)),
  );

  /// `0.9s` 播放头邻域亮度脉动周期（对齐 `more.css:191` `wbeat .9s`）。
  late final AnimationController _beatCtrl = AnimationController(
    vsync: this,
    duration: MotionToken.resolveForPlatform(const Duration(milliseconds: 900)),
  );

  /// `2.4s` 呼吸底光周期（对齐 `more.css:190` `wglow 2.4s`）。
  late final AnimationController _glowCtrl = AnimationController(
    vsync: this,
    duration: MotionToken.resolveForPlatform(
      const Duration(milliseconds: 2400),
    ),
  );

  /// `700ms` 点击扩散涟漪（对齐 `more.css:197` `wrip .7s ease-out`）。
  late final AnimationController _rippleCtrl = AnimationController(
    vsync: this,
    duration: MotionToken.resolveForPlatform(const Duration(milliseconds: 700)),
  );

  @override
  void initState() {
    super.initState();
    _ensureHeights(widget.trackId);
    _rippleCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _rippleFraction = null);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBreath();
  }

  @override
  void didUpdateWidget(_WaveSeek oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackId != widget.trackId) {
      _ensureHeights(widget.trackId);
    }
    _syncBreath();
  }

  void _ensureHeights(String seed) {
    if (_heights.length == _barCount && _cachedSeed == seed) {
      return;
    }
    _cachedSeed = seed;
    // 严格对照 ui.tsx:255-259：
    var h = 7;
    for (final unit in seed.codeUnits) {
      h = (h * 31 + unit) & 0xFFFFFFFF;
    }
    final ph = (h % 100) / 10.0;
    _heights = List<double>.generate(_barCount, (i) {
      final e = math.pow(math.sin((i / _barCount) * math.pi), 0.5).toDouble();
      final harmonic =
          (math.sin(i * 0.37 + ph) * math.cos(i * 0.11 + ph * 2.0)).abs();
      final grain =
          ((math.sin(i * 12.9898 + ph) * 43758.5453).remainder(1.0) + 1.0) *
          0.5;
      final value = (0.28 + 0.5 * harmonic + 0.22 * grain) * (0.55 + 0.45 * e);
      return value.clamp(0.12, 1.0).toDouble();
    }, growable: false);
  }

  void _syncActive() {
    final active = _hovered || _dragging;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _activeCtrl.value = active ? 1.0 : 0.0;
      return;
    }
    if (active) {
      unawaited(_activeCtrl.forward());
    } else {
      unawaited(_activeCtrl.reverse());
    }
  }

  void _syncBreath() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.playing && !reduceMotion) {
      if (!_beatCtrl.isAnimating) {
        _beatCtrl.repeat();
      }
      if (!_glowCtrl.isAnimating) {
        _glowCtrl.repeat();
      }
    } else {
      if (_beatCtrl.isAnimating) _beatCtrl.stop();
      if (_glowCtrl.isAnimating) _glowCtrl.stop();
    }
  }

  void _triggerRipple(double frac) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return;
    setState(() => _rippleFraction = frac);
    unawaited(_rippleCtrl.forward(from: 0.0));
  }

  @override
  void dispose() {
    _activeCtrl.dispose();
    _beatCtrl.dispose();
    _glowCtrl.dispose();
    _rippleCtrl.dispose();
    super.dispose();
  }

  double _fractionAt(double dx, double width) {
    if (width <= 0) return 0.0;
    return (dx / width).clamp(0.0, 1.0);
  }

  Duration _positionAt(double dx, double width) {
    final total = widget.duration.inMilliseconds;
    if (total <= 0 || width <= 0) {
      return Duration.zero;
    }
    final fraction = _fractionAt(dx, width);
    return Duration(milliseconds: (total * fraction).round());
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds;
    final progress =
        total <= 0
            ? 0.0
            : (widget.position.inMilliseconds / total).clamp(0.0, 1.0);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final breathActive = widget.playing && !reduceMotion;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final bubbleFraction = _dragging ? _dragFraction : _hoverFraction;
        final showBubble = bubbleFraction != null && total > 0 && width > 0;
        final bubbleDuration =
            showBubble
                ? Duration(milliseconds: (total * bubbleFraction).round())
                : Duration.zero;
        const estimatedBubbleWidth = 48.0;
        final bubbleLeft =
            showBubble
                ? (width * bubbleFraction - estimatedBubbleWidth / 2)
                    .clamp(0.0, math.max(0.0, width - estimatedBubbleWidth))
                    .toDouble()
                : 0.0;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (event) {
            final next = _fractionAt(event.localPosition.dx, width);
            if (!_hovered ||
                _hoverFraction == null ||
                (next - _hoverFraction!).abs() > 0.001) {
              setState(() {
                _hovered = true;
                _hoverFraction = next;
              });
              _syncActive();
            }
          },
          onExit: (_) {
            setState(() {
              _hovered = false;
              _hoverFraction = null;
            });
            _syncActive();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              if (total <= 0 || width <= 0) return;
              final frac = _fractionAt(details.localPosition.dx, width);
              _triggerRipple(frac);
              final target = _positionAt(details.localPosition.dx, width);
              _pendingPosition = null;
              widget.onCommit(target);
            },
            onHorizontalDragStart: (details) {
              if (total <= 0 || width <= 0) return;
              final frac = _fractionAt(details.localPosition.dx, width);
              _triggerRipple(frac);
              final target = _positionAt(details.localPosition.dx, width);
              _pendingPosition = target;
              setState(() {
                _dragging = true;
                _dragFraction = frac;
              });
              _syncActive();
              widget.onDragStart();
              widget.onDragUpdate(target);
            },
            onHorizontalDragUpdate: (details) {
              if (total <= 0 || width <= 0) return;
              final frac = _fractionAt(details.localPosition.dx, width);
              final target = _positionAt(details.localPosition.dx, width);
              _pendingPosition = target;
              setState(() => _dragFraction = frac);
              widget.onDragUpdate(target);
            },
            onHorizontalDragEnd: (_) {
              final target = _pendingPosition ?? widget.position;
              _pendingPosition = null;
              setState(() {
                _dragging = false;
                _dragFraction = null;
              });
              _syncActive();
              if (total > 0) {
                widget.onCommit(target);
              } else {
                widget.onDragCancel?.call();
              }
            },
            onHorizontalDragCancel: () {
              _pendingPosition = null;
              setState(() {
                _dragging = false;
                _dragFraction = null;
              });
              _syncActive();
              widget.onDragCancel?.call();
            },
            child: SizedBox(
              height: 52,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _activeCtrl,
                        _beatCtrl,
                        _glowCtrl,
                        _rippleCtrl,
                      ]),
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _WavePainter(
                            heights: _heights,
                            progress: progress,
                            hueColor: widget.hueColor,
                            playing: widget.playing,
                            dragging: _dragging,
                            hoverFraction:
                                _dragging ? _dragFraction : _hoverFraction,
                            activeT: DesktopMotion.spring.transform(
                              _activeCtrl.value,
                            ),
                            beatPhase: _beatCtrl.value,
                            glowPhase: _glowCtrl.value,
                            breathActive: breathActive,
                            rippleFraction: _rippleFraction,
                            rippleT: Curves.easeOut.transform(
                              _rippleCtrl.value,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // 纯白底 #FFFFFF / 深黑字 #0A0C0E 8px 圆角时间气泡（more.css:196）。
                  if (showBubble)
                    Positioned(
                      left: bubbleLeft,
                      top: -30,
                      child: IgnorePointer(
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: estimatedBubbleWidth,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFFFF),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 18,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Text(
                            formatDesktopClock(bubbleDuration),
                            style: DesktopType.numeric(
                              const Color(0xFF0A0C0E),
                            ).copyWith(
                              fontSize: DesktopType.sizeCaption,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.heights,
    required this.progress,
    required this.hueColor,
    required this.playing,
    required this.dragging,
    required this.hoverFraction,
    required this.activeT,
    required this.beatPhase,
    required this.glowPhase,
    required this.breathActive,
    required this.rippleFraction,
    required this.rippleT,
  });

  final List<double> heights;
  final double progress;
  final Color hueColor;
  final bool playing;
  final bool dragging;
  final double? hoverFraction;
  final double activeT;
  final double beatPhase;
  final double glowPhase;
  final bool breathActive;
  final double? rippleFraction;
  final double rippleT;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || heights.isEmpty) return;
    final bars = heights.length;
    final step = size.width / bars;
    final barWidth = math.max(1.0, step - 2.0);
    final centerY = size.height * 0.5;
    final playX = (size.width * progress).clamp(0.0, size.width);

    // 1. `.wave-glow` 呼吸底光（more.css:189-190）：已播区域内由透明渐亮至 hueColor。
    if (playX > 2.0) {
      final glowPulse =
          breathActive
              ? 0.45 + 0.30 * (0.5 - 0.5 * math.cos(glowPhase * 2 * math.pi))
              : 0.45;
      final glowRect = Rect.fromLTWH(
        0,
        size.height * 0.10,
        playX,
        size.height * 0.80,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(glowRect, const Radius.circular(99)),
        Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[
              Colors.transparent,
              hueColor.withValues(alpha: (0.70 * glowPulse).clamp(0.0, 1.0)),
            ],
          ).createShader(glowRect),
      );
    }

    // 2. 120 柱波形（已播纵向双色渐变 + 播放头高斯邻域隆起 + 0.9s 亮度脉动 + 悬停透镜放大）。
    final playedBottom = Color.lerp(Colors.white, hueColor, 0.55)!;
    final playedTop = Color.lerp(Colors.white, hueColor, 0.20)!;
    final restColor = Colors.white.withValues(alpha: 0.22);
    final playedPaint = Paint()..style = PaintingStyle.fill;
    final restPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = restColor;

    for (var i = 0; i < bars; i++) {
      final c = (i + 0.5) / bars;
      final dPlay = (c - progress) * bars;
      final near = math.exp(-((dPlay / 4.0) * (dPlay / 4.0)));
      final lens =
          hoverFraction != null
              ? math.exp(-math.pow(((c - hoverFraction!) * bars) / 5.0, 2))
              : 0.0;
      final sc =
          1.0 +
          near * (playing ? 0.50 : 0.28) +
          lens * 0.45 +
          (dragging ? 0.08 : 0.0);

      final barH = (heights[i] * size.height * sc).clamp(
        3.0,
        size.height * 1.18,
      );
      final half = barH * 0.5;
      final cx = i * step + step * 0.5;
      final barRect = Rect.fromLTRB(
        cx - barWidth * 0.5,
        centerY - half,
        cx + barWidth * 0.5,
        centerY + half,
      );
      final barRRect = RRect.fromRectAndRadius(
        barRect,
        Radius.circular(barWidth * 0.5),
      );

      final isPlayed = c < progress;
      final isBeat = near > 0.5 && breathActive;
      var boost = 0.0;
      if (isBeat) {
        final delayFrac = ((i % 7) * 0.09) / 0.9;
        final phase = (beatPhase + delayFrac) % 1.0;
        boost = 0.35 * (0.5 - 0.5 * math.cos(phase * 2 * math.pi));
      }

      if (isPlayed) {
        final topCol =
            boost > 0 ? Color.lerp(playedTop, Colors.white, boost)! : playedTop;
        final botCol =
            boost > 0
                ? Color.lerp(playedBottom, Colors.white, boost)!
                : playedBottom;
        playedPaint.shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[botCol, topCol],
        ).createShader(barRect);
        canvas.drawRRect(barRRect, playedPaint);
      } else {
        restPaint.color =
            boost > 0
                ? Colors.white.withValues(
                  alpha: (0.22 + boost * 0.35).clamp(0.0, 1.0),
                )
                : restColor;
        canvas.drawRRect(barRRect, restPaint);
      }
    }

    // 3. 悬停 1px 细游标线 `.wave-hov`（more.css:195）。
    if (hoverFraction != null) {
      final hx = (size.width * hoverFraction!).clamp(0.0, size.width);
      canvas.drawLine(
        Offset(hx, 0),
        Offset(hx, size.height),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.40)
          ..strokeWidth = 1.0,
      );
    }

    // 4. `700ms` 点击扩散涟漪 `.wave-rip`（more.css:197）。
    if (rippleFraction != null && rippleT < 1.0) {
      final rx = (size.width * rippleFraction!).clamp(0.0, size.width);
      final radius = 7.0 * (1.0 + 6.0 * rippleT);
      final ripAlpha = (1.0 - rippleT).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(rx, centerY),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = Colors.white.withValues(alpha: ripAlpha),
      );
    }

    // 5. 上下外溢 8px 渐隐播放头线（more.css:192）。
    final lineRect = Rect.fromLTRB(
      playX - 1.0,
      -8.0,
      playX + 1.0,
      size.height + 8.0,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(lineRect, const Radius.circular(2.0)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: <double>[0.0, 0.20, 0.80, 1.0],
        ).createShader(lineRect),
    );

    // 6. 12px 发光白色圆点（hover/drag 时放大 1.35×，more.css:193-194）。
    final dotScale = (1.0 + 0.35 * activeT).clamp(1.0, 1.5);
    final dotRadius = 6.0 * dotScale;
    final dotCenter = Offset(playX, centerY);
    // 外环 4px 半透 hueColor 晕环。
    canvas.drawCircle(
      dotCenter,
      dotRadius + 4.0 * dotScale,
      Paint()..color = hueColor.withValues(alpha: 0.50),
    );
    // 柔白辉光 + 实体白点。
    canvas.drawCircle(
      dotCenter,
      dotRadius + 2.0,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawCircle(dotCenter, dotRadius, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.heights != heights ||
      oldDelegate.progress != progress ||
      oldDelegate.hueColor != hueColor ||
      oldDelegate.playing != playing ||
      oldDelegate.dragging != dragging ||
      oldDelegate.hoverFraction != hoverFraction ||
      oldDelegate.activeT != activeT ||
      oldDelegate.beatPhase != beatPhase ||
      oldDelegate.glowPhase != glowPhase ||
      oldDelegate.breathActive != breathActive ||
      oldDelegate.rippleFraction != rippleFraction ||
      oldDelegate.rippleT != rippleT;
}
