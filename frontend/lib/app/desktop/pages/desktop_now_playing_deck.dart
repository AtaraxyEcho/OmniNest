part of 'desktop_now_playing_page.dart';

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
                // 样例 `.deck-aura`：唱机后方一层曲目色相柔光，inset -14%/-10%，
                // blur(40px)、opacity .55 → 播放时 .85，颜色随 --hue 补间。
                // 局限在唱机这一块并单独保留层，不给整页叠全屏模糊。
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
                // 玻璃反光：只在左上角留一道，避免整盘发灰。
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
                    // 样例 `-8deg → 37deg`，播放时落下。
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
              // 唱片纹路：三圈细环 + 一道高光弧。
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
      // 固定伪随机波形：同一首歌每次进来形状一致，不随帧跳动。
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
/// 模糊封面 / 极光 / 频谱脉动 / 壁纸库 / 渐变 / 纯色，外加遮罩与模糊两层调节。
class _NpBackdrop extends ConsumerWidget {
  const _NpBackdrop({required this.style, required this.cover});

  final DesktopNpStyle style;
  final String? cover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final preset = DesktopNpPreset.all[style.preset];
    final top = style.preset == 0 ? skin.accent : preset.top;

    Widget base = switch (style.background) {
      DesktopNpBackground.cover =>
        cover == null
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
                    cover!,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
      DesktopNpBackground.aurora => Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF07090B)),
          Positioned(
            left: -220,
            top: -260,
            width: 620,
            height: 620,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    skin.accent.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -260,
            bottom: -300,
            width: 700,
            height: 700,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    skin.warm.withValues(alpha: 0.32),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 380,
            bottom: -220,
            width: 420,
            height: 420,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF5D6FA8).withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // 样例 `.aurora` 是四团（`extra.css:118`）：第四团是暖橙
          // `#d9a05a`，尺寸 40%、贴右下、opacity .3。缺了它整面只剩冷色。
          Positioned(
            right: -80,
            bottom: -180,
            width: 300,
            height: 300,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFD9A05A).withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      DesktopNpBackground.spectrum => AnimatedContainer(
        duration: MotionToken.reduced(context, DesktopMotion.colorFade),
        curve: DesktopMotion.ease,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, 0.7),
            radius: 1.1,
            colors: [top.withValues(alpha: 0.55), const Color(0xFF07090B)],
          ),
        ),
      ),
      // 样例 `.np-grad { transition: background 1s }`：换预设时渐变要
      // 缓缓过渡，不是硬切。
      DesktopNpBackground.gradient => AnimatedContainer(
        duration: MotionToken.reduced(context, DesktopMotion.colorFade),
        curve: DesktopMotion.ease,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, preset.bottom],
          ),
        ),
      ),
      DesktopNpBackground.plain => const ColoredBox(color: Color(0xFF07090B)),
      // 样例 `bg: "library"`：背景取自壁纸库当前选中的那一张。桌面壳的
      // 壁纸层被 NP 的不透明舞台盖住，所以这里自己铺一层，不产生双背景。
      DesktopNpBackground.library => _wallpaper(context, ref),
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
                const Color(0xFF07090B).withValues(alpha: 0.7),
                const Color(0xFF07090B).withValues(alpha: 0.86),
              ],
            ),
          ),
        ),
        if (style.mask > 0)
          ColoredBox(
            color: Colors.black.withValues(alpha: style.mask / 100 * 0.8),
          ),
      ],
    );
  }

  Widget _wallpaper(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appBackdropControllerProvider).asData?.value;
    final asset = state?.selectedBackdrop;
    if (state == null || asset == null) {
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
