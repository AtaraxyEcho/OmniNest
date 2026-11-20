part of 'reader_page_view.dart';

/// 跨页中缝悬浮宽度（样例 `reader.css:4`，不占用纸页宽度）。
const double _spreadGutterWidth = 70.0;

/// 双页跨页单元（样例 `.bookview .spread`）：
/// 左右严格 50% / 50% 贴合，70px 中缝阴影悬浮叠在接缝之上，
/// 左右动态厚度纸叠外挂于书框外缘，静动纸面共用同一份预烘焙噪点 Shader。
class ReaderPageSpread extends StatelessWidget {
  const ReaderPageSpread({
    required this.left,
    required this.right,
    required this.surfaceColor,
    this.paperEdgeColor,
    this.leftBoundaryKey,
    this.rightBoundaryKey,
    this.progress = 0,
    this.curlOverlay,
    this.bookmarked = false,
    super.key,
  });

  final Widget left;
  final Widget? right;
  final Color surfaceColor;
  final Color? paperEdgeColor;

  /// 仅在静止态传入，卷页底层 underlay 必须传 null，杜绝 GlobalKey 冲突。
  final GlobalKey? leftBoundaryKey;
  final GlobalKey? rightBoundaryKey;

  /// 全书/章内进度（0..1）：两侧纸叠厚度随进度动态变化。
  final double progress;

  /// 整幅双页卷曲层（.curl-clip），覆盖左右两页允许纸页扫过书脊。
  final Widget? curlOverlay;
  final bool bookmarked;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final leftStackW = 3.0 + p * 13.0;
    final rightStackW = 3.0 + (1.0 - p) * 13.0;
    final edgeColor =
        paperEdgeColor ?? Color.lerp(surfaceColor, Colors.black, 0.08)!;

    Widget wrapBoundary(GlobalKey? key, Widget child) =>
        key == null ? child : RepaintBoundary(key: key, child: child);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 左侧外挂纸叠（.spread .stack.l）
        Positioned(
          left: -leftStackW + 2,
          top: 3,
          bottom: 3,
          width: leftStackW,
          child: _PaperStack(
            edgeColor: edgeColor,
            paperColor: surfaceColor,
            side: _SpreadSide.left,
          ),
        ),
        // 右侧外挂纸叠（.spread .stack.r）
        Positioned(
          right: -rightStackW + 2,
          top: 3,
          bottom: 3,
          width: rightStackW,
          child: _PaperStack(
            edgeColor: edgeColor,
            paperColor: surfaceColor,
            side: _SpreadSide.right,
          ),
        ),
        // 书本主体（6px 圆角 + 双层桌面阴影）
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 44,
                spreadRadius: -26,
                offset: const Offset(0, 22),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 12,
                spreadRadius: -6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: wrapBoundary(
                        leftBoundaryKey,
                        _SpreadPage(
                          color: surfaceColor,
                          side: _SpreadSide.left,
                          child: left,
                        ),
                      ),
                    ),
                    Expanded(
                      child: wrapBoundary(
                        rightBoundaryKey,
                        _SpreadPage(
                          color: surfaceColor,
                          side: _SpreadSide.right,
                          child: right,
                        ),
                      ),
                    ),
                  ],
                ),
                // 70px 中缝阴影悬浮叠在 50% 接缝之上（不占宽、不拦截选区）
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: _spreadGutterWidth,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.05),
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.05),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.30, 0.495, 0.505, 0.70, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (curlOverlay != null)
                  Positioned.fill(child: IgnorePointer(child: curlOverlay!)),
                if (bookmarked)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: LayoutBuilder(
                        builder:
                            (context, c) => Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  top: -2,
                                  right: c.maxWidth * 0.08,
                                  child: ClipPath(
                                    clipper: const _SpreadRibbonClipper(),
                                    child: Container(
                                      width: 16,
                                      height: 40,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _SpreadSide { left, right }

class _SpreadPage extends StatelessWidget {
  const _SpreadPage({
    required this.color,
    required this.side,
    required this.child,
  });

  final Color color;
  final _SpreadSide side;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final spineTint = Color.lerp(color, Colors.black, 0.08)!;
    final gradient =
        side == _SpreadSide.left
            ? LinearGradient(
              colors: [color, color, spineTint],
              stops: const [0.0, 0.90, 1.0],
            )
            : LinearGradient(
              colors: [spineTint, color, color],
              stops: const [0.0, 0.10, 1.0],
            );
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(gradient: gradient),
          child: child ?? SizedBox.expand(child: ColoredBox(color: color)),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _PaperGrainOverlayPainter()),
          ),
        ),
      ],
    );
  }
}

class _PaperGrainOverlayPainter extends CustomPainter {
  _PaperGrainOverlayPainter()
    : super(repaint: PaperGrainCache.shaderListenable);

  @override
  void paint(Canvas canvas, Size size) {
    final shader = PaperGrainCache.shader;
    if (shader == null) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.multiply,
    );
  }

  @override
  bool shouldRepaint(_PaperGrainOverlayPainter oldDelegate) => false;
}

class _PaperStack extends StatelessWidget {
  const _PaperStack({
    required this.edgeColor,
    required this.paperColor,
    required this.side,
  });

  final Color edgeColor;
  final Color paperColor;
  final _SpreadSide side;

  @override
  Widget build(BuildContext context) {
    final gapColor = Color.lerp(paperColor, Colors.black, 0.12)!;
    final radius =
        side == _SpreadSide.left
            ? const BorderRadius.horizontal(left: Radius.circular(4))
            : const BorderRadius.horizontal(right: Radius.circular(4));
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          painter: _PaperStackPainter(
            edge: edgeColor,
            gap: gapColor,
            side: side,
          ),
        ),
      ),
    );
  }
}

class _PaperStackPainter extends CustomPainter {
  const _PaperStackPainter({
    required this.edge,
    required this.gap,
    required this.side,
  });

  final Color edge;
  final Color gap;
  final _SpreadSide side;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var x = 0.0; x < size.width; x += 2.5) {
      paint.color = edge;
      canvas.drawRect(Rect.fromLTWH(x, 0, 1.0, size.height), paint);
      paint.color = gap;
      canvas.drawRect(Rect.fromLTWH(x + 1.0, 0, 1.5, size.height), paint);
    }
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin:
              side == _SpreadSide.left
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
          end:
              side == _SpreadSide.left
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.22)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_PaperStackPainter oldDelegate) =>
      oldDelegate.edge != edge ||
      oldDelegate.gap != gap ||
      oldDelegate.side != side;
}

class _SpreadRibbonClipper extends CustomClipper<Path> {
  const _SpreadRibbonClipper();

  @override
  Path getClip(Size size) =>
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width / 2, size.height * 0.8)
        ..lineTo(0, size.height)
        ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
