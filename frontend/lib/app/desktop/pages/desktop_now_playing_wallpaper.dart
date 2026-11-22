part of 'desktop_now_playing_page.dart';

/// Now Playing 背景平滑阻尼动画状态（复刻样例 `Wallpaper.tsx`）：
/// - `phase`：播放 `1.0×` ↔ 暂停 `0.15×` 指数平滑阻尼（`dt * 2.0`）；
/// - `wallClock`：恒速时钟，供 `cover` 30s 推镜与 `np-orb` 恒速流动；
/// - `level`：节拍包络 `0.5 + 0.5*sin(7.3t)*sin(2.9t+1)`（`dt * 6.0` 阻尼）；
/// - `energy`：频谱展开系数 `0.10 ↔ 1.0`（`dt * 4.0` 阻尼）；
/// - `hueDeg`：切歌色相最短弧丝滑插值（`dt * 1.5`）。
class _NpAnimState extends ChangeNotifier {
  _NpAnimState({required Color initialHue, required bool playing})
    : _speed = playing ? 1.0 : 0.15,
      energy = playing ? 1.0 : 0.10 {
    final hsl = HSLColor.fromColor(initialHue);
    hueDeg = hsl.hue;
    sat = hsl.saturation.clamp(0.45, 0.80);
    lit = hsl.lightness.clamp(0.38, 0.58);
  }

  double phase = 0.0;
  double wallClock = 0.0;
  double level = 0.0;
  double energy;
  double hueDeg = 200.0;
  double sat = 0.60;
  double lit = 0.48;
  double _speed;

  Color get hueColor => HSLColor.fromAHSL(1.0, hueDeg, sat, lit).toColor();

  void step({
    required double dt,
    required bool playing,
    required Color targetColor,
  }) {
    final clampedDt = dt.clamp(0.0, 0.05);
    if (clampedDt <= 0) return;

    final hsl = HSLColor.fromColor(targetColor);
    final targetHue = hsl.hue;
    final targetSat = hsl.saturation.clamp(0.45, 0.80);
    final targetLit = hsl.lightness.clamp(0.38, 0.58);

    // 切歌色相最短弧平滑插值（dt * 1.5）。
    final hueAlpha = math.min(1.0, clampedDt * 1.5);
    final dh = ((targetHue - hueDeg + 540.0) % 360.0) - 180.0;
    hueDeg = (hueDeg + dh * hueAlpha + 360.0) % 360.0;
    sat += (targetSat - sat) * hueAlpha;
    lit += (targetLit - lit) * hueAlpha;

    // 播放 1.0× ↔ 暂停 0.15× 指数平滑阻尼（dt * 2.0）。
    final targetSpeed = playing ? 1.0 : 0.15;
    _speed += (targetSpeed - _speed) * math.min(1.0, clampedDt * 2.0);
    phase = (phase + clampedDt * _speed) % 3600.0;

    // 恒速时钟，驱动 cover 30s 推镜与 np-orb。
    wallClock = (wallClock + clampedDt) % 3600.0;

    // 节拍包络（dt * 6.0 阻尼）。
    final targetLevel =
        playing
            ? (0.5 + 0.5 * math.sin(phase * 7.3) * math.sin(phase * 2.9 + 1.0))
            : 0.0;
    level += (targetLevel - level) * math.min(1.0, clampedDt * 6.0);

    // 频谱展开系数 0.10 ↔ 1.0（dt * 4.0 阻尼）。
    final targetEnergy = playing ? 1.0 : 0.10;
    energy += (targetEnergy - energy) * math.min(1.0, clampedDt * 4.0);

    notifyListeners();
  }

  /// 减弱动效静态帧同步：直接对齐目标色相与状态，不推进时间。
  void syncStatic({required bool playing, required Color targetColor}) {
    final hsl = HSLColor.fromColor(targetColor);
    final nextHue = hsl.hue;
    final nextSat = hsl.saturation.clamp(0.45, 0.80);
    final nextLit = hsl.lightness.clamp(0.38, 0.58);
    final nextEnergy = playing ? 1.0 : 0.10;
    if (nextHue != hueDeg ||
        nextSat != sat ||
        nextLit != lit ||
        nextEnergy != energy) {
      hueDeg = nextHue;
      sat = nextSat;
      lit = nextLit;
      energy = nextEnergy;
      level = 0.0;
      notifyListeners();
    }
  }
}

/// Now Playing 背景（样例 `.np-bg` 的六档）：
/// 完整复刻 `Wallpaper.tsx` 平滑阻尼状态机与 6 种动态预设：
/// `aurora` / `spectrum`（新版 5 层频谱脉动，无 np-orb）/
/// `library`（隔离全局 dim/blur 并支持内置 live 极光）/
/// `cover`（blur 20 + 30s 轻缓推镜）/ `gradient` / `plain`（1s 切歌缓动径向微光）。
class _NpBackdrop extends ConsumerStatefulWidget {
  const _NpBackdrop({
    required this.style,
    required this.cover,
    required this.playing,
    required this.hueColor,
    this.seed = '',
  });

  final DesktopNpStyle style;
  final String? cover;
  final bool playing;
  final Color hueColor;
  final String seed;

  @override
  ConsumerState<_NpBackdrop> createState() => _NpBackdropState();
}

class _NpBackdropState extends ConsumerState<_NpBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final _NpAnimState _anim;
  Duration? _lastElapsed;

  bool get _isLibraryLive =>
      widget.style.background == DesktopNpBackground.library &&
      (widget.style.wallId == 'b-aurora' || widget.style.wallId == 'live');

  bool get _needsTicker =>
      widget.style.background != DesktopNpBackground.gradient &&
      widget.style.background != DesktopNpBackground.spectrum &&
      (widget.style.background != DesktopNpBackground.library ||
          _isLibraryLive);

  @override
  void initState() {
    super.initState();
    _anim = _NpAnimState(initialHue: widget.hueColor, playing: widget.playing);
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_NpBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _anim.syncStatic(playing: widget.playing, targetColor: widget.hueColor);
    }
  }

  void _onTick(Duration elapsed) {
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (previous == null) return;
    final dt = (elapsed - previous).inMicroseconds / 1000000.0;
    if (dt <= 0 || dt > 0.25) return;
    _anim.step(dt: dt, playing: widget.playing, targetColor: widget.hueColor);
  }

  void _syncTicker() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final shouldRun = _needsTicker && !reduceMotion;
    if (shouldRun && !_ticker.isActive) {
      _lastElapsed = null;
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
      _lastElapsed = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _anim.dispose();
    super.dispose();
  }

  Widget _buildLiveAurora() {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _NpLiveWallpaperPainter(anim: _anim),
        child: const SizedBox.expand(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final hue = widget.hueColor;
    // 对齐 polish.css:652 `.np.bg-spectrum .np-orb { display: none; }`。
    final showOrbs =
        style.background != DesktopNpBackground.gradient &&
        style.background != DesktopNpBackground.library &&
        style.background != DesktopNpBackground.spectrum;

    Widget base = switch (style.background) {
      DesktopNpBackground.cover =>
        widget.cover == null
            ? const ColoredBox(color: Color(0xFF07090B))
            : ClipRect(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, child) {
                  // 恒速 wallClock 驱动 30s 轻缓推镜（scale: 1.04..1.08, ±1%）。
                  final theta = (_anim.wallClock / 30.0) * 2 * math.pi;
                  final wave = 0.5 + 0.5 * math.sin(theta);
                  final driftScale = 1.04 + 0.04 * wave;
                  final fx = math.sin(theta * 0.7) * 0.01;
                  final fy = math.cos(theta * 0.5) * 0.01;
                  return FractionalTranslation(
                    translation: Offset(fx, fy),
                    child: Transform.scale(scale: driftScale, child: child),
                  );
                },
                child: ImageFiltered(
                  imageFilter: desktopGlassFilter(
                    blur: 20,
                    saturation: 1.5,
                    brightness: 0.55,
                  ),
                  child: Image.network(
                    widget.cover!,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
      DesktopNpBackground.aurora => _buildLiveAurora(),
      DesktopNpBackground.spectrum => NpSpectrumBackdrop(
        hueColor: hue,
        playing: widget.playing,
        seed: widget.seed,
      ),
      DesktopNpBackground.gradient => _angleGradient(context, style, hue),
      DesktopNpBackground.plain => AnimatedContainer(
        duration: MotionToken.reduced(context, DesktopMotion.colorFade),
        curve: DesktopMotion.ease,
        decoration: BoxDecoration(
          color: const Color(0xFF07090B),
          gradient: RadialGradient(
            center: const Alignment(-0.4, -0.6),
            radius: 1.15,
            colors: [
              Color.lerp(const Color(0xFF0B0E11), hue, 0.28)!,
              const Color(0xFF07090B),
            ],
            stops: const [0.0, 0.70],
          ),
        ),
      ),
      DesktopNpBackground.library => _wallpaper(context, ref, style.wallId),
    };

    if (style.blur > 0) {
      base = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: style.blur, sigmaY: style.blur),
        child: base,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        base,
        // 遮罩层叠顺序：base → style.mask → np-orb → np-veil。
        if (style.mask > 0)
          IgnorePointer(
            child: ColoredBox(
              color: const Color(
                0xFF040608,
              ).withValues(alpha: (style.mask / 100.0).clamp(0.0, 1.0)),
            ),
          ),
        if (showOrbs)
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _NpOrbsPainter(anim: _anim),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        // `np-veil`：Alignment(0, -0.2) 径向暗角 + 底部 55% → 100% 线性暗幕。
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 0.95,
                colors: [
                  Colors.transparent,
                  const Color(0xFF040608).withValues(alpha: 0.70),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Color(0x8C040608),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
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
    // 内置 live 极光壁纸直接接入播放状态与曲目色相。
    if (wallId == 'b-aurora' || wallId == 'live') {
      return _buildLiveAurora();
    }
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
    // 隔离全局壁纸 dim/blur 泄漏：播放页由自身 style.mask / style.blur 接管。
    final isolatedSettings = state.settings.copyWith(
      dimAmount: 0.0,
      blurAmount: 0.0,
    );
    return AppBackdropSurface(
      asset: asset,
      settings: isolatedSettings,
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

/// 动态极光壁纸绘制器（复刻样例 `Wallpaper.tsx` `Aurora`）：
/// 5 球同色系 `(hueDeg + (i - 2) * 22°)` 大半径全屏流动轨道 + 柔焦效果，受 `level` 驱动呼吸。
class _NpLiveWallpaperPainter extends CustomPainter {
  _NpLiveWallpaperPainter({required this.anim}) : super(repaint: anim);

  final _NpAnimState anim;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF06080A));

    final t = anim.phase;
    final level = anim.level;
    final h0 = anim.hueDeg;
    final sat = anim.sat;
    final lit = anim.lit;

    // 5 球同色系大半径全屏流动极光 + 柔焦效果（受 level 驱动呼吸）。
    const auroraOpacity = 0.55;
    for (var i = 0; i < 5; i++) {
      final k = i * 1.7 + 0.6;
      final cx = size.width * (0.5 + 0.42 * math.sin(t * (0.5 + i * 0.13) + k));
      final cy =
          size.height * (0.5 + 0.38 * math.cos(t * (0.4 + i * 0.11) + k * 1.3));
      final r =
          size.height * (0.75 + 0.25 * math.sin(t * 0.7 + i) + level * 0.12);
      final orbHue = (h0 + (i - 2) * 22.0 + 360.0) % 360.0;
      final orbColor = HSLColor.fromAHSL(1.0, orbHue, sat, lit).toColor();
      final center = Offset(cx, cy);
      final orbRect = Rect.fromCircle(center: center, radius: r);
      final paint =
          Paint()
            ..blendMode = BlendMode.plus
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28)
            ..shader = RadialGradient(
              colors: [
                orbColor.withValues(alpha: auroraOpacity),
                orbColor.withValues(alpha: auroraOpacity * 0.34),
                Colors.transparent,
              ],
              stops: const [0.0, 0.52, 1.0],
            ).createShader(orbRect);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_NpLiveWallpaperPainter oldDelegate) =>
      oldDelegate.anim != anim;
}

/// 2 枚 `BlendMode.screen` 恒速慢漂移柔光球 `np-orb`（用于非 `gradient`/`library`/`spectrum` 模式）：
/// `o1` 位于左上画外 `(-0.08w, -0.10h)`、`o2` 位于右下画外 `(1.06w, 1.08h)`，
/// 双球均取平滑 `hueDeg` 并在 `wallClock` 上恒速流动。
class _NpOrbsPainter extends CustomPainter {
  _NpOrbsPainter({required this.anim}) : super(repaint: anim);

  final _NpAnimState anim;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final t = anim.wallClock;
    final vmax = math.max(size.width, size.height);
    final hueColor = anim.hueColor;

    // o1：左上画外 (-0.08w, -0.10h)，26s 周期轻缓漂移。
    final t1 = (t / 26.0) * 2 * math.pi;
    final c1 = Offset(
      size.width * -0.08 + math.sin(t1) * size.width * 0.05,
      size.height * -0.10 + math.cos(t1 * 0.85) * size.height * 0.05,
    );
    final r1 = vmax * 0.44;
    canvas.drawCircle(
      c1,
      r1,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: [
            hueColor.withValues(alpha: 0.42),
            hueColor.withValues(alpha: 0.14),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c1, radius: r1)),
    );

    // o2：右下画外 (1.06w, 1.08h)，32s 周期反向漂移。
    final t2 = ((t + 9.0) / 32.0) * 2 * math.pi;
    final c2 = Offset(
      size.width * 1.06 + math.cos(t2) * size.width * 0.05,
      size.height * 1.08 + math.sin(t2 * 0.9) * size.height * 0.05,
    );
    final r2 = vmax * 0.44;
    canvas.drawCircle(
      c2,
      r2,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: [
            hueColor.withValues(alpha: 0.28),
            hueColor.withValues(alpha: 0.09),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c2, radius: r2)),
    );
  }

  @override
  bool shouldRepaint(_NpOrbsPainter oldDelegate) => oldDelegate.anim != anim;
}
