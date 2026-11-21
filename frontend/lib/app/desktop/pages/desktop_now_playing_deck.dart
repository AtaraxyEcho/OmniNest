part of 'desktop_now_playing_page.dart';

/// 极光 / 频谱背景的流动周期（样例 `amb-flow` 的 18s 循环）。
const _flowCycle = Duration(seconds: 18);

/// 唱机（样例 `.plinth`）：560 上限、1.05 比例的外壳，内部 80% 转盘、
/// 右侧唱臂、底部 LED 与曲序号。播放时唱臂落下、唱片旋转、轴心浮现。
class _Deck extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 560.0);
        final height = size / 1.05;
        final platter = size * 0.8;
        return Center(
          child: SizedBox(
            width: size,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -size * 0.10,
                  right: -size * 0.10,
                  top: -size * 0.14,
                  bottom: -size * 0.14,
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                        child: AnimatedOpacity(
                          opacity: playing ? 0.85 : 0.55,
                          duration: DesktopMotion.colorFade,
                          curve: DesktopMotion.ease,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                radius: 0.72,
                                colors: [
                                  hueColor.withValues(alpha: 0.55),
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
                  ),
                ),
                Positioned(
                  left: size * 0.04,
                  top: size * 0.133,
                  width: platter,
                  height: platter,
                  child: _Platter(
                    spin: spin,
                    cover: cover,
                    playing: playing,
                    size: platter,
                  ),
                ),
                Positioned(
                  left: size * 0.04,
                  top: size * 0.133,
                  width: platter,
                  height: platter,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.07),
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.03),
                          ],
                          stops: const [0, 0.45, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: size * 0.9,
                  top: size * 0.11,
                  child: AnimatedRotation(
                    turns: (playing ? 37 : -8) / 360,
                    duration: DesktopMotion.of(context, DesktopMotion.tonearm),
                    curve: DesktopMotion.spring,
                    alignment: Alignment.topLeft,
                    child: _Tonearm(size: size),
                  ),
                ),
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
                              playing
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : const Color(0xFF3A2A2A),
                          boxShadow:
                              playing
                                  ? [
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: 0.45,
                                      ),
                                      blurRadius: 10,
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
                    '${index.toString().padLeft(2, '0')} / '
                    '${total.toString().padLeft(2, '0')}',
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

class _Platter extends StatelessWidget {
  const _Platter({
    required this.spin,
    required this.cover,
    required this.playing,
    required this.size,
  });

  final Animation<double> spin;
  final String? cover;
  final bool playing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final labelSize = size * 0.28;
    return Container(
      padding: EdgeInsets.all(size * 0.012),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF2A3036), Color(0xFF14181C)],
        ),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0A0D0F), spreadRadius: size * 0.014),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: spin,
        builder:
            (context, child) =>
                Transform.rotate(angle: spin.value * 2 * math.pi, child: child),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF0B0B0C),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final inset in const [0.08, 0.16, 0.24])
                Container(
                  width: size * (0.9 - inset * 2),
                  height: size * (0.9 - inset * 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
              ClipOval(
                child: SizedBox(
                  width: labelSize,
                  height: labelSize,
                  child:
                      cover == null
                          ? const ColoredBox(color: Color(0xFF1A2026))
                          : Image.network(
                            cover!,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, _, _) =>
                                    const ColoredBox(color: Color(0xFF1A2026)),
                          ),
                ),
              ),
              Container(
                width: size * 0.024,
                height: size * 0.024,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.3, -0.4),
                    colors: [Color(0xFFEEEEEE), Color(0xFF888888)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tonearm extends StatelessWidget {
  const _Tonearm({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 1,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -size * 0.05,
            top: -size * 0.05,
            width: size * 0.10,
            height: size * 0.10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  colors: [Color(0xFF4A535A), Color(0xFF1A1F23)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: -size * 0.0055,
            top: 0,
            width: size * 0.011,
            height: size * 0.46,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.01),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF8A949A),
                    Color(0xFFD9DFE2),
                    Color(0xFF7A848A),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 6,
                    offset: const Offset(3, 6),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: -size * 0.02,
            top: size * 0.445,
            width: size * 0.04,
            height: size * 0.06,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.007),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A3036), Color(0xFF0E1114)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 波形进度条（样例 `.wave`）：52 高、白色播放头，点击/拖动定位。
class _WaveSeek extends StatelessWidget {
  const _WaveSeek({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    final progress =
        total <= 0 ? 0.0 : (position.inMilliseconds / total).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        void seekAt(double dx) {
          if (total <= 0 || constraints.maxWidth <= 0) {
            return;
          }
          final fraction = (dx / constraints.maxWidth).clamp(0.0, 1.0);
          onSeek(Duration(milliseconds: (total * fraction).round()));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seekAt(details.localPosition.dx),
          onHorizontalDragUpdate: (details) => seekAt(details.localPosition.dx),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: CustomPaint(
              painter: _WavePainter(
                progress: progress,
                played:
                    Color.lerp(
                      Colors.white,
                      Theme.of(context).colorScheme.primary,
                      0.35,
                    )!,
                rest: Colors.white.withValues(alpha: 0.22),
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
    required this.played,
    required this.rest,
  });

  final double progress;
  final Color played;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 64;
    final step = size.width / bars;
    final barWidth = math.max(1.0, step - 2);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < bars; i++) {
      final noise = (math.sin(i * 12.9898) * 43758.5453).abs() % 1;
      final magnitude = 0.28 + noise * 0.72;
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
