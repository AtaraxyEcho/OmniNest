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
/// `aurora` / `spectrum`（四层景深声场）/ `library`（隔离全局 dim/blur 并支持内置 live 极光）/
/// `cover`（blur 20 + 30s 轻缓推镜）/ `gradient` / `plain`（1s 切歌缓动径向微光）。
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
  late final Ticker _ticker;
  late final _NpAnimState _anim;
  Duration? _lastElapsed;

  bool get _isLibraryLive =>
      widget.style.background == DesktopNpBackground.library &&
      (widget.style.wallId == 'b-aurora' || widget.style.wallId == 'live');

  bool get _needsTicker =>
      widget.style.background != DesktopNpBackground.gradient &&
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

  Widget _buildLiveAurora({required bool spectrum}) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _NpLiveWallpaperPainter(anim: _anim, spectrum: spectrum),
        child: const SizedBox.expand(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final hue = widget.hueColor;
    final showOrbs =
        style.background != DesktopNpBackground.gradient &&
        style.background != DesktopNpBackground.library;

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
      DesktopNpBackground.aurora => _buildLiveAurora(spectrum: false),
      DesktopNpBackground.spectrum => _buildLiveAurora(spectrum: true),
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
      return _buildLiveAurora(spectrum: false);
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

/// 动态预设壁纸绘制器（复刻样例 `Wallpaper.tsx` 并升级四层景深声场）：
/// - `aurora`：5 球同色系 `(hueDeg + (i - 2) * 22°)` 大半径全屏流动轨道 + 柔焦效果，受 `level` 驱动呼吸；
/// - `spectrum`：
///   - Layer 1 极光柔焦底；
///   - Layer 2 `MaskFilter.blur(24)` 低频弥散脉冲环；
///   - Layer 3 64 根连续色相径向主频谱（圆形非退化渐变，右侧歌词区 `cosA > 0.25` 柔和衰减）；
///   - Layer 4 `1.0px` 基线细环与峰顶星点。
class _NpLiveWallpaperPainter extends CustomPainter {
  _NpLiveWallpaperPainter({required this.anim, required this.spectrum})
    : super(repaint: anim);

  final _NpAnimState anim;
  final bool spectrum;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF06080A));

    final t = anim.phase;
    final level = anim.level;
    final energy = anim.energy;
    final h0 = anim.hueDeg;
    final sat = anim.sat;
    final lit = anim.lit;

    // Layer 1：5 球同色系大半径全屏流动极光 + 柔焦效果（受 level 驱动呼吸）。
    final auroraOpacity = spectrum ? 0.42 : 0.55;
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

    if (!spectrum) return;

    // spectrum 模式：圆心居中至 (0.50w, 0.46h) 彻底离开唱机边缘。
    final center = Offset(size.width * 0.50, size.height * 0.46);
    final minDim = math.min(size.width, size.height);
    final baseR = minDim * 0.21;
    final maxLen = minDim * 0.20;

    // Layer 2：`MaskFilter.blur(24)` 低频弥散脉冲环。
    final pulseR = baseR * (1.0 + 0.055 * level * energy);
    final pulseStroke = minDim * (0.040 + 0.024 * level * energy);
    final pulseColor = HSLColor.fromAHSL(1.0, h0, sat, lit).toColor();
    canvas.drawCircle(
      center,
      pulseR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pulseStroke
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24)
        ..color = pulseColor.withValues(
          alpha: ((0.18 + 0.24 * level) * energy).clamp(0.0, 1.0),
        ),
    );

    // Layer 3：64 根连续色相径向主频谱（右侧歌词区 cosA > 0.25 柔和衰减护眼）。
    const rays = 64;
    final spinAngle = t * 0.15;
    final starPaint = Paint()..blendMode = BlendMode.plus;

    for (var i = 0; i < rays; i++) {
      final a = spinAngle + (i / rays) * 2 * math.pi;
      final cosA = math.cos(a);
      final sinA = math.sin(a);

      // 对右侧歌词区自动柔和衰减护眼。
      final rightFade =
          cosA > 0.25
              ? (1.0 - ((cosA - 0.25) / 0.75) * 0.65).clamp(0.35, 1.0)
              : 1.0;

      final wave =
          (math.sin(t * 6.0 + i * 0.9) * math.cos(t * 3.1 + i * 0.37)).abs();
      final e = (0.18 + 0.82 * wave * (0.55 + level * 0.55)) * energy;
      final innerR = baseR;
      final outerR = baseR + maxLen * (0.08 + 0.92 * e);

      final p1 = Offset(center.dx + cosA * innerR, center.dy + sinA * innerR);
      final p2 = Offset(center.dx + cosA * outerR, center.dy + sinA * outerR);
      final mid = Offset((p1.dx + p2.dx) * 0.5, (p1.dy + p2.dy) * 0.5);
      final halfLen = math.max(1.0, (outerR - innerR) * 0.5);

      final rayHue = (h0 + (i / rays) * 140.0) % 360.0;
      final baseColor = HSLColor.fromAHSL(1.0, rayHue, 0.82, 0.60).toColor();
      final tipColor =
          HSLColor.fromAHSL(1.0, (rayHue + 20.0) % 360.0, 0.88, 0.78).toColor();
      final rayAlpha = ((0.20 + 0.54 * e) * rightFade).clamp(0.0, 1.0);

      // 使用沿射线方向对齐的圆形非退化包围盒生成精确 p1 -> p2 线性渐变，
      // 彻底修复水平/垂直射线下 Rect.fromPoints 退化为零宽/零高的 Bug。
      final rayPaint =
          Paint()
            ..blendMode = BlendMode.plus
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2.4
            ..shader = LinearGradient(
              begin: Alignment(-cosA, -sinA),
              end: Alignment(cosA, sinA),
              colors: [
                baseColor.withValues(alpha: rayAlpha * 0.42),
                tipColor.withValues(alpha: rayAlpha),
              ],
            ).createShader(Rect.fromCircle(center: mid, radius: halfLen));
      canvas.drawLine(p1, p2, rayPaint);

      // Layer 4b：峰顶星点（随能量与右侧护眼衰减平滑显现）。
      if (e > 0.28) {
        final starR = outerR + 3.5;
        final starPos = Offset(
          center.dx + cosA * starR,
          center.dy + sinA * starR,
        );
        final starAlpha = (((e - 0.28) / 0.72) * 0.72 * rightFade).clamp(
          0.0,
          1.0,
        );
        starPaint.color = Colors.white.withValues(alpha: starAlpha);
        canvas.drawCircle(starPos, 1.3 + 0.8 * e, starPaint);
      }
    }

    // Layer 4a：1.0px 基线细环。
    final ringColor = HSLColor.fromAHSL(1.0, h0, 0.65, 0.78).toColor();
    canvas.drawCircle(
      center,
      baseR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..blendMode = BlendMode.plus
        ..color = ringColor.withValues(
          alpha: (0.14 + 0.14 * energy).clamp(0.0, 1.0),
        ),
    );
  }

  @override
  bool shouldRepaint(_NpLiveWallpaperPainter oldDelegate) =>
      oldDelegate.anim != anim || oldDelegate.spectrum != spectrum;
}

/// 2 枚 `BlendMode.screen` 恒速慢漂移柔光球 `np-orb`（用于非 `gradient`/`library` 模式）：
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
