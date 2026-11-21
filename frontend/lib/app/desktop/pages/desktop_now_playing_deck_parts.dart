part of 'desktop_now_playing_page.dart';

class _PlinthMetalPainter extends CustomPainter {
  const _PlinthMetalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 横向 1px / 3px 微妙金属拉丝纹。
    final brushPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.018)
          ..strokeWidth = 1.0;
    for (double y = 1.0; y < size.height; y += 4.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), brushPaint);
    }
    // 顶部 1px white 0.08 内高光。
    canvas.drawLine(
      const Offset(0, 0.5),
      Offset(size.width, 0.5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 1.0,
    );
    // 底部内暗影。
    final bottomRect = Rect.fromLTWH(0, size.height - 14, size.width, 14);
    canvas.drawRect(
      bottomRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.36)],
        ).createShader(bottomRect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 静态反光 `.glare`：双瓣 SweepGradient + BlendMode.screen（12 点钟起点）。
class _PlatterGlarePainter extends CustomPainter {
  const _PlatterGlarePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()..addOval(rect);
    canvas.save();
    canvas.clipPath(path);
    final shader = SweepGradient(
      transform: const GradientRotation(-math.pi / 2),
      colors: [
        Colors.transparent,
        Colors.transparent,
        Colors.white.withValues(alpha: 0.10),
        Colors.white.withValues(alpha: 0.10),
        Colors.transparent,
        Colors.transparent,
        Colors.white.withValues(alpha: 0.08),
        Colors.white.withValues(alpha: 0.08),
        Colors.transparent,
        Colors.transparent,
      ],
      stops: const [0.0, 0.06, 0.08, 0.12, 0.15, 0.56, 0.58, 0.62, 0.65, 1.0],
    ).createShader(rect);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.screen,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 黑胶盘面绘制：约 40 道高频同心纹路 + 两层旋转锥形高光。
class _VinylDiscPainter extends CustomPainter {
  const _VinylDiscPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1. 盘面底色。
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF0A0A0B));

    // 2. 高频同心纹路（约 40 道，模仿 repeating-radial-gradient(#0a0a0b 0 .35cqw, #18181a .35cqw .5cqw)）。
    final innerR = radius * 0.30;
    final outerR = radius * 0.965;
    const grooveCount = 40;
    final step = (outerR - innerR) / grooveCount;
    final grooveStroke = (step * 0.34).clamp(0.65, 1.6);
    final groovePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = grooveStroke
          ..color = const Color(0xFF18181A);
    final sheenPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (grooveStroke * 0.55).clamp(0.45, 1.0)
          ..color = Colors.white.withValues(alpha: 0.032);

    for (var i = 0; i < grooveCount; i++) {
      final r = innerR + i * step + step * 0.5;
      canvas.drawCircle(center, r, groovePaint);
      if (i % 4 == 0) {
        canvas.drawCircle(center, r + grooveStroke * 0.45, sheenPaint);
      }
    }

    // 3. 旋转锥形高光层 1（0.07）。
    final sweep1 = SweepGradient(
      colors: [
        Colors.transparent,
        Colors.white.withValues(alpha: 0.07),
        Colors.transparent,
        Colors.white.withValues(alpha: 0.07),
        Colors.transparent,
      ],
      stops: const [0.0, 0.22, 0.48, 0.72, 1.0],
    ).createShader(rect);
    canvas.drawCircle(center, radius, Paint()..shader = sweep1);

    // 4. 旋转锥形高光层 2（0.12 / 0.10）。
    final sweep2 = SweepGradient(
      transform: const GradientRotation(math.pi * 0.18),
      colors: [
        Colors.transparent,
        Colors.white.withValues(alpha: 0.12),
        Colors.transparent,
        Colors.white.withValues(alpha: 0.10),
        Colors.transparent,
      ],
      stops: const [0.0, 0.14, 0.32, 0.64, 0.84],
    ).createShader(rect);
    canvas.drawCircle(center, radius, Paint()..shader = sweep2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
      padding: EdgeInsets.all(size * 0.008),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF1A1F24), Color(0xFF0C0F12)],
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
        child: ClipOval(
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _VinylDiscPainter()),
                ),
              ),
              // 中心标签 `.label`：0.5cqw 深黑外环阴影 + 内侧径向暗角。
              Container(
                width: labelSize,
                height: labelSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black,
                      spreadRadius: size * 0.00625,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      cover == null
                          ? const ColoredBox(color: Color(0xFF1A2026))
                          : Image.network(
                            cover!,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, _, _) =>
                                    const ColoredBox(color: Color(0xFF1A2026)),
                          ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.20),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.60],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 中心金属轴心。
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
  const _Tonearm({required this.size, required this.accent});

  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final pivotInset = size * 0.032;
    return SizedBox(
      width: 1,
      height: 1,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 唱臂轴心底座 + 金属内盖（inset 3.2cqw）。
          Positioned(
            left: -size * 0.05,
            top: -size * 0.05,
            width: size * 0.10,
            height: size * 0.10,
            child: Container(
              padding: EdgeInsets.all(pivotInset),
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.3, -0.35),
                    colors: [Color(0xFFD5DCE0), Color(0xFF6B747B)],
                  ),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                ),
              ),
            ),
          ),
          // 唱臂金属管。
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
          // 唱头：8° 倾角 + 底部 skin.accent 强调色唱针。
          Positioned(
            left: -size * 0.02,
            top: size * 0.445,
            width: size * 0.04,
            height: size * 0.068,
            child: Transform.rotate(
              angle: 8 * math.pi / 180,
              alignment: Alignment.topCenter,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    width: size * 0.04,
                    height: size * 0.06,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(size * 0.007),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2A3036), Color(0xFF0E1114)],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 0.6,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: size * 0.009,
                      height: size * 0.013,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(size * 0.004),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.65),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 波形进度条（样例 `.wave`）：52 高、白色播放头，按 `trackId` 生成专属波形，
/// 拖动仅更新预览位置，松手或点击时通过 `onCommit` 触发一次 `seek`。
