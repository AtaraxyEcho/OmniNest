part of 'desktop_now_playing_page.dart';

/// 极光 / 频谱背景的流动周期（样例 `amb-flow` 的 18s 循环）。
const _flowCycle = Duration(seconds: 18);

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
        final platterTop = size * 0.14;
        return Center(
          child: SizedBox(
            width: size,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 封面氛围光晕 `.deck-aura`：播放态 4.2s 呼吸透明度与 1.06 缩放。
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
                              playing ? (0.72 + 0.22 * wave) : 0.55;
                          final auraScale = playing ? (1.0 + 0.06 * wave) : 1.0;
                          return Transform.scale(
                            scale: auraScale,
                            child: Opacity(opacity: auraOpacity, child: child),
                          );
                        },
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                radius: 0.72,
                                colors: [
                                  widget.hueColor.withValues(alpha: 0.58),
                                  Colors.transparent,
                                ],
                                stops: const [0, 0.72],
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
                // 黑胶转盘（对齐 top: size * 0.14）。
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
                // 静态反光 `.glare`：双瓣 SweepGradient（8%→12% 0.10、58%→62% 0.08）+ BlendMode.screen。
                Positioned(
                  left: size * 0.04,
                  top: platterTop,
                  width: platter,
                  height: platter,
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

/// 唱机底座金属拉丝纹理与上下边缘内高光/内暗影。
class _WaveSeek extends StatefulWidget {
  const _WaveSeek({
    required this.trackId,
    required this.position,
    required this.duration,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onCommit,
    this.onDragCancel,
  });

  final String trackId;
  final Duration position;
  final Duration duration;
  final VoidCallback onDragStart;
  final ValueChanged<Duration> onDragUpdate;
  final ValueChanged<Duration> onCommit;
  final VoidCallback? onDragCancel;

  @override
  State<_WaveSeek> createState() => _WaveSeekState();
}

class _WaveSeekState extends State<_WaveSeek> {
  Duration? _pendingPosition;

  Duration _positionAt(double dx, double width) {
    final total = widget.duration.inMilliseconds;
    if (total <= 0 || width <= 0) {
      return Duration.zero;
    }
    final fraction = (dx / width).clamp(0.0, 1.0);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
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
              final target = _positionAt(details.localPosition.dx, width);
              _pendingPosition = target;
              widget.onDragStart();
              widget.onDragUpdate(target);
            },
            onHorizontalDragUpdate: (details) {
              if (total <= 0 || width <= 0) return;
              final target = _positionAt(details.localPosition.dx, width);
              _pendingPosition = target;
              widget.onDragUpdate(target);
            },
            onHorizontalDragEnd: (_) {
              final target = _pendingPosition ?? widget.position;
              _pendingPosition = null;
              if (total > 0) {
                widget.onCommit(target);
              } else {
                widget.onDragCancel?.call();
              }
            },
            onHorizontalDragCancel: () {
              _pendingPosition = null;
              widget.onDragCancel?.call();
            },
            child: SizedBox(
              height: 52,
              width: double.infinity,
              child: CustomPaint(
                painter: _WavePainter(
                  progress: progress,
                  seed: seed,
                  played: Color.lerp(Colors.white, skin.accent, 0.35)!,
                  rest: Colors.white.withValues(alpha: 0.22),
                ),
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
  });

  final double progress;
  final int seed;
  final Color played;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 64;
    final step = size.width / bars;
    final barWidth = math.max(1.0, step - 2);
    final paint = Paint()..strokeCap = StrokeCap.round;
    final seedPhase = (seed % 997) * 0.317;
    for (var i = 0; i < bars; i++) {
      final noise =
          (math.sin((i + 1) * 12.9898 + seedPhase * 78.233) * 43758.5453)
              .abs() %
          1;
      final envelope = 0.72 + 0.28 * math.sin((i / bars) * math.pi);
      final magnitude = (0.24 + noise * 0.76) * envelope;
      final left = i * step;
      final centerY = size.height / 2;
      final half = size.height / 2 * magnitude;
      paint.color = (left / size.width) <= progress ? played : rest;
      canvas.drawLine(
        Offset(left + barWidth / 2, centerY - half),
        Offset(left + barWidth / 2, centerY + half),
        paint..strokeWidth = barWidth,
      );
    }
    final x = size.width * progress;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.seed != seed ||
      oldDelegate.played != played ||
      oldDelegate.rest != rest;
}

/// Now Playing 背景（样例 `.np-bg` 的六档）：
/// 支持 `style.wallId` 独立渲染不污染全局壁纸、自定义角度渐变、播放态
/// `aurora` / `spectrum` 流动动画，外加遮罩与模糊两层调节。
class _NpBackdrop extends ConsumerStatefulWidget {
  const _NpBackdrop({
    required this.style,
    required this.cover,
    required this.playing,
    required this.hueColor,
  });

  final DesktopNpStyle style;
  final String? cover;
  final bool playing;
  final Color hueColor;

  @override
  ConsumerState<_NpBackdrop> createState() => _NpBackdropState();
}

class _NpBackdropState extends ConsumerState<_NpBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: _flowCycle,
  );

  bool get _needsFlow =>
      widget.playing &&
      (widget.style.background == DesktopNpBackground.aurora ||
          widget.style.background == DesktopNpBackground.spectrum);

  void _syncFlow(bool reduceMotion) {
    final shouldRun = _needsFlow && !reduceMotion;
    if (shouldRun && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!shouldRun && _flow.isAnimating) {
      _flow.stop();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final style = widget.style;
    final hue = widget.hueColor;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncFlow(reduceMotion);

    Widget base = switch (style.background) {
      DesktopNpBackground.cover =>
        widget.cover == null
            ? const ColoredBox(color: Color(0xFF07090B))
            : Opacity(
              opacity: 0.45,
              child: ImageFiltered(
                imageFilter: desktopGlassFilter(
                  blur: 60,
                  saturation: 1.7,
                  brightness: 0.55,
                ),
                child: Transform.scale(
                  scale: 1.2,
                  child: Image.network(
                    widget.cover!,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
      DesktopNpBackground.aurora => AnimatedBuilder(
        animation: _flow,
        builder: (context, _) {
          final theta = _flow.value * 2 * math.pi;
          final dx1 = math.sin(theta) * 65;
          final dy1 = math.cos(theta) * 45;
          final dx2 = math.cos(theta * 1.1) * 70;
          final dy2 = math.sin(theta * 0.9) * 55;
          final dx3 = math.sin(theta * 0.7 + 1.2) * 55;
          final dy3 = math.cos(theta * 0.8 + 0.6) * 40;
          final dx4 = math.cos(theta * 1.3 + 2.0) * 50;
          final dy4 = math.sin(theta * 1.2 + 1.0) * 38;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF07090B)),
              Positioned(
                left: -220 + dx1,
                top: -260 + dy1,
                width: 660,
                height: 660,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [hue.withValues(alpha: 0.54), Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -260 + dx2,
                bottom: -300 + dy2,
                width: 720,
                height: 720,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        skin.warm.withValues(alpha: 0.34),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 340 + dx3,
                bottom: -220 + dy3,
                width: 460,
                height: 460,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF5D6FA8).withValues(alpha: 0.32),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -80 + dx4,
                bottom: -180 + dy4,
                width: 340,
                height: 340,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFD9A05A).withValues(alpha: 0.32),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      DesktopNpBackground.spectrum => AnimatedBuilder(
        animation: _flow,
        builder: (context, _) {
          final theta = _flow.value * 2 * math.pi;
          final pulse = 0.5 + 0.5 * math.sin(theta * 3);
          final radius = 0.95 + pulse * 0.28;
          final alpha = 0.42 + pulse * 0.22;
          final shiftX = math.sin(theta) * 0.14;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(shiftX, 0.68),
                radius: radius,
                colors: [
                  hue.withValues(alpha: alpha),
                  Color.lerp(const Color(0xFF07090B), hue, 0.16)!,
                  const Color(0xFF07090B),
                ],
                stops: const [0.0, 0.52, 1.0],
              ),
            ),
          );
        },
      ),
      DesktopNpBackground.gradient => _angleGradient(context, style, hue),
      DesktopNpBackground.plain => const ColoredBox(color: Color(0xFF07090B)),
      DesktopNpBackground.library => _wallpaper(context, ref, style.wallId),
    };

    if (style.blur > 0) {
      base = ImageFiltered(
        imageFilter: desktopGlassFilter(
          blur: style.blur,
          saturation: 1.5,
          brightness: 0.85,
        ),
        child: base,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        base,
        // 固定压暗层：保证曲名与歌词在任何背景上都可读。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF07090B).withValues(alpha: 0.62),
                const Color(0xFF07090B).withValues(alpha: 0.80),
              ],
            ),
          ),
        ),
        if (style.mask > 0)
          ColoredBox(
            color: Colors.black.withValues(alpha: style.mask / 100 * 0.85),
          ),
      ],
    );
  }

  Widget _angleGradient(BuildContext context, DesktopNpStyle style, Color hue) {
    // CSS linear-gradient(angle deg): 0deg 向上、90deg 向右、180deg 向下。
    final rad = style.gradAngle * math.pi / 180.0;
    final dx = math.sin(rad);
    final dy = -math.cos(rad);
    return AnimatedContainer(
      duration: MotionToken.reduced(context, DesktopMotion.colorFade),
      curve: DesktopMotion.ease,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-dx, -dy),
          end: Alignment(dx, dy),
          colors: <Color>[
            style.effectiveGradStart(hue),
            style.effectiveGradEnd(hue),
          ],
        ),
      ),
    );
  }

  Widget _wallpaper(BuildContext context, WidgetRef ref, String wallId) {
    final state = ref.watch(appBackdropControllerProvider).asData?.value;
    if (state == null) {
      return const ColoredBox(color: Color(0xFF07090B));
    }
    // 严格按播放页自身的 `style.wallId` 查找，绝不改动全局壁纸选择。
    final asset =
        state.backdrops.where((item) => item.id == wallId).firstOrNull ??
        state.selectedBackdrop ??
        state.backdrops.firstOrNull;
    if (asset == null) {
      return const ColoredBox(color: Color(0xFF07090B));
    }
    final motionAllowed =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return AppBackdropSurface(
      asset: asset,
      settings: state.settings,
      policy: AppBackdropPolicy(
        scene: AppBackdropScene.work,
        visible: true,
        playbackMode: AppBackdropPlaybackMode.continuous,
        readabilityMode: AppBackdropReadabilityMode.content,
        motionAllowed: motionAllowed,
      ),
      environmentBlurSigma: 0,
      active: motionAllowed,
    );
  }
}
