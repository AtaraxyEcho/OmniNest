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

/// 波形进度条（样例 `.wave`）：52 高、96 柱自适应波形，悬停胶囊时间气泡与预览高亮，
/// 播放头发光底线 + 波形 1.0→1.08 纵伸，播放时播放头邻域高斯微幅呼吸。
class _WaveSeek extends StatefulWidget {
  const _WaveSeek({
    required this.trackId,
    required this.position,
    required this.duration,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onCommit,
    this.onDragCancel,
    this.playing = false,
  });

  final String trackId;
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
  Duration? _pendingPosition;
  double? _hoverFraction;
  double? _dragFraction;
  bool _hovered = false;
  bool _dragging = false;

  late final AnimationController _activeCtrl = AnimationController(
    vsync: this,
    duration: MotionToken.resolveForPlatform(const Duration(milliseconds: 180)),
  );

  late final AnimationController _breathCtrl = AnimationController(
    vsync: this,
    duration: MotionToken.resolveForPlatform(
      const Duration(milliseconds: 1400),
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBreath();
  }

  @override
  void didUpdateWidget(_WaveSeek oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBreath();
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
      if (!_breathCtrl.isAnimating) {
        _breathCtrl.repeat();
      }
    } else if (_breathCtrl.isAnimating) {
      _breathCtrl.stop();
    }
  }

  @override
  void dispose() {
    _activeCtrl.dispose();
    _breathCtrl.dispose();
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

  static int _stableSeed(String id) {
    var hash = 2166136261;
    for (final unit in id.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds;
    final progress =
        total <= 0
            ? 0.0
            : (widget.position.inMilliseconds / total).clamp(0.0, 1.0);
    final seed = _stableSeed(widget.trackId);
    final skin = DesktopSkin.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final breathActive = widget.playing && !reduceMotion;
    final playedColor = Color.lerp(Colors.white, skin.accent, 0.35)!;
    final restColor = Colors.white.withValues(alpha: 0.22);
    final previewColor = Color.lerp(restColor, playedColor, 0.52)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final bubbleFraction = _dragging ? _dragFraction : _hoverFraction;
        final showBubble = bubbleFraction != null && total > 0 && width > 0;
        final bubbleDuration =
            showBubble
                ? Duration(milliseconds: (total * bubbleFraction).round())
                : Duration.zero;
        const estimatedBubbleWidth = 54.0;
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
              final target = _positionAt(details.localPosition.dx, width);
              _pendingPosition = null;
              widget.onCommit(target);
            },
            onHorizontalDragStart: (details) {
              if (total <= 0 || width <= 0) return;
              final frac = _fractionAt(details.localPosition.dx, width);
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
                      animation: Listenable.merge([_activeCtrl, _breathCtrl]),
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _WavePainter(
                            progress: progress,
                            seed: seed,
                            played: playedColor,
                            rest: restColor,
                            preview: previewColor,
                            hoverFraction: _dragging ? null : _hoverFraction,
                            activeT: Curves.easeOutCubic.transform(
                              _activeCtrl.value,
                            ),
                            breathPhase: _breathCtrl.value,
                            breathActive: breathActive,
                          ),
                        );
                      },
                    ),
                  ),
                  if (showBubble)
                    Positioned(
                      left: bubbleLeft,
                      top: -28,
                      child: IgnorePointer(
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: estimatedBubbleWidth,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xEB0A0D10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Text(
                            formatDesktopClock(bubbleDuration),
                            style: DesktopType.numeric(
                              Colors.white.withValues(alpha: 0.94),
                            ).copyWith(
                              fontSize: DesktopType.sizeCaption,
                              height: 1.15,
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
    required this.progress,
    required this.seed,
    required this.played,
    required this.rest,
    required this.preview,
    required this.hoverFraction,
    required this.activeT,
    required this.breathPhase,
    required this.breathActive,
  });

  final double progress;
  final int seed;
  final Color played;
  final Color rest;
  final Color preview;
  final double? hoverFraction;
  final double activeT;
  final double breathPhase;
  final bool breathActive;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final bars = (size.width / 5.5).round().clamp(56, 96);
    final step = size.width / bars;
    final barWidth = math.max(1.2, step * 0.56);
    final paint = Paint()..strokeCap = StrokeCap.round;
    final seedPhase = (seed % 997) * 0.317;
    final centerY = size.height / 2;
    final verticalScale = 1.0 + 0.08 * activeT;
    final currentIdx = (progress * (bars - 1)).round();

    for (var i = 0; i < bars; i++) {
      final noise =
          (math.sin((i + 1) * 12.9898 + seedPhase * 78.233) * 43758.5453)
              .abs() %
          1;
      final envelope = 0.72 + 0.28 * math.sin((i / bars) * math.pi);
      final magnitude = (0.24 + noise * 0.76) * envelope;
      var breathFactor = 1.0;
      if (breathActive) {
        final dist = (i - currentIdx).abs();
        if (dist <= 3) {
          final gauss = math.exp(-(dist * dist) / 4.5);
          final wave = math.sin(breathPhase * 2 * math.pi + i * 0.85);
          breathFactor = 1.0 + 0.05 * gauss * wave;
        }
      }
      final left = i * step;
      final barCenterX = left + step / 2;
      final barFraction = barCenterX / size.width;
      final half = (size.height *
              0.44 *
              magnitude *
              verticalScale *
              breathFactor)
          .clamp(1.5, size.height * 0.49);

      if (barFraction <= progress) {
        paint.color = played;
      } else if (hoverFraction != null && barFraction <= hoverFraction!) {
        paint.color = preview;
      } else {
        paint.color = rest;
      }

      canvas.drawLine(
        Offset(barCenterX, centerY - half),
        Offset(barCenterX, centerY + half),
        paint..strokeWidth = barWidth,
      );
    }

    // 悬停 1px 细游标线。
    if (hoverFraction != null) {
      final hx = (size.width * hoverFraction!).clamp(0.0, size.width);
      canvas.drawLine(
        Offset(hx, 3),
        Offset(hx, size.height - 3),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.48)
          ..strokeWidth = 1.0,
      );
    }

    // 播放头：MaskFilter.blur(6) 发光底线（hover/drag 时平滑淡入增强）+ 2px 白色主线。
    final x = (size.width * progress).clamp(0.0, size.width);
    final glowAlpha = 0.28 + 0.56 * activeT;
    canvas.drawLine(
      Offset(x, 1),
      Offset(x, size.height - 1),
      Paint()
        ..color = played.withValues(alpha: glowAlpha)
        ..strokeWidth = 4.0 + 2.0 * activeT
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.seed != seed ||
      oldDelegate.played != played ||
      oldDelegate.rest != rest ||
      oldDelegate.preview != preview ||
      oldDelegate.hoverFraction != hoverFraction ||
      oldDelegate.activeT != activeT ||
      oldDelegate.breathPhase != breathPhase ||
      oldDelegate.breathActive != breathActive;
}
