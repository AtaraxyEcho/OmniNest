part of 'desktop_ambient.dart';

/// 纯净模式（Plain）背景：用于非五大媒体路由或用户关闭「随封面变色的背景」时。
///
/// 由 `skin.bg` 底色 + 右上角强调色径向光晕（深色 9% / 浅色 7%）+ 顶部纵向微渐变 +
/// 极轻静态噪点组成，整体外包 `RepaintBoundary`，稳态 0fps、零动画回调。
class DesktopAmbientPlain extends StatelessWidget {
  const DesktopAmbientPlain({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          key: const ValueKey('ambient-plain'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: skin.bg),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.92, -0.88),
                    radius: 1.05,
                    colors: <Color>[
                      skin.accent.withValues(alpha: skin.isDark ? 0.09 : 0.07),
                      skin.accent.withValues(alpha: 0.0),
                    ],
                    stops: const <double>[0.0, 0.72],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      (skin.isDark ? Colors.white : Colors.black).withValues(
                        alpha: skin.isDark ? 0.03 : 0.025,
                      ),
                      Colors.transparent,
                    ],
                    stops: const <double>[0.0, 0.36],
                  ),
                ),
              ),
              CustomPaint(
                painter: _PlainGrainPainter(isDark: skin.isDark),
                child: const SizedBox.expand(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 深色非 Reader 5% overlay 细噪点绘制器（轻量无外部资源依赖）。
class _DarkAmbientGrainPainter extends CustomPainter {
  const _DarkAmbientGrainPainter();

  static const double _tileSize = 96.0;
  static const List<Offset> _dots = <Offset>[
    Offset(7, 11),
    Offset(23, 5),
    Offset(41, 19),
    Offset(63, 9),
    Offset(82, 17),
    Offset(14, 34),
    Offset(35, 29),
    Offset(57, 42),
    Offset(76, 36),
    Offset(91, 48),
    Offset(9, 59),
    Offset(28, 66),
    Offset(49, 58),
    Offset(71, 69),
    Offset(88, 63),
    Offset(19, 82),
    Offset(44, 78),
    Offset(65, 89),
    Offset(84, 85),
    Offset(5, 91),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..blendMode = BlendMode.overlay;
    final cols = math.min((size.width / _tileSize).ceil(), 36);
    final rows = math.min((size.height / _tileSize).ceil(), 24);
    for (var r = 0; r < rows; r++) {
      final baseY = r * _tileSize;
      for (var c = 0; c < cols; c++) {
        final baseX = c * _tileSize;
        for (final dot in _dots) {
          final x = baseX + dot.dx;
          final y = baseY + dot.dy;
          if (x < size.width && y < size.height) {
            canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DarkAmbientGrainPainter oldDelegate) => false;
}

/// Plain 模式极轻静态噪点绘制器（仅在外层 `RepaintBoundary` 首次光栅化一次）。
class _PlainGrainPainter extends CustomPainter {
  const _PlainGrainPainter({required this.isDark});

  final bool isDark;

  static const double _tileSize = 128.0;
  static const List<Offset> _dots = <Offset>[
    Offset(12, 19),
    Offset(47, 8),
    Offset(89, 27),
    Offset(115, 14),
    Offset(26, 54),
    Offset(68, 46),
    Offset(103, 61),
    Offset(18, 92),
    Offset(55, 84),
    Offset(94, 98),
    Offset(38, 118),
    Offset(79, 112),
    Offset(121, 107),
    Offset(7, 73),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint =
        Paint()
          ..color = (isDark ? Colors.white : Colors.black).withValues(
            alpha: isDark ? 0.025 : 0.020,
          );
    final cols = math.min((size.width / _tileSize).ceil(), 32);
    final rows = math.min((size.height / _tileSize).ceil(), 20);
    for (var r = 0; r < rows; r++) {
      final baseY = r * _tileSize;
      for (var c = 0; c < cols; c++) {
        final baseX = c * _tileSize;
        for (final dot in _dots) {
          final x = baseX + dot.dx;
          final y = baseY + dot.dy;
          if (x < size.width && y < size.height) {
            canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PlainGrainPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
