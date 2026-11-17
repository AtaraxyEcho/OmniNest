part of 'reader_page_view.dart';

/// 跨页中缝宽度（`reader.css:4` 的 `.bookview .spread .gutter` 三选择器
/// 胜出 `more.css` 的两选择器；70px / margin-left -35px）。卷页按半页计算
/// 宽度时也读它。
const double _spreadGutterWidth = 70;

/// 双页跨页单元（样例 `.bookview .spread`）：左右各一张纸，中缝是一条
/// 70px 的渐变阴影。页码口径不变——左页是 `index`，右页是 `index + 1`，
/// 章节页数为奇数时右页留白，避免把下一章的内容借过来。
class ReaderPageSpread extends StatelessWidget {
  const ReaderPageSpread({
    required this.left,
    required this.right,
    required this.surfaceColor,
    this.progress = 0,
    super.key,
  });

  final Widget left;
  final Widget? right;
  final Color surfaceColor;

  /// 全书进度（0..1）：两侧纸边的厚度随剩余页数变化，像真书一样越读越薄。
  final double progress;

  @override
  Widget build(BuildContext context) {
    // 样例 `.spread`：外层 6px 圆角 + 两层投影，纸面朝书脊一侧压暗。
    return DecoratedBox(
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
                  child: _SpreadPage(
                    color: surfaceColor,
                    side: _SpreadSide.left,
                    child: left,
                  ),
                ),
                const _SpreadGutter(),
                Expanded(
                  child: _SpreadPage(
                    color: surfaceColor,
                    side: _SpreadSide.right,
                    child: right,
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3 + progress.clamp(0.0, 1.0) * 13,
              child: _PaperStack(color: surfaceColor, side: _SpreadSide.left),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 3 + (1 - progress.clamp(0.0, 1.0)) * 13,
              child: _PaperStack(color: surfaceColor, side: _SpreadSide.right),
            ),
          ],
        ),
      ),
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
    // 样例 `.bpage.left/right`：90% 之后开始向 #000 混（92%/74% 两档叠加），
    // 让靠近书脊的一端自然压暗，读起来像纸张弯进装订线。
    final edge = Color.lerp(color, Colors.black, 0.18)!;
    final gradient =
        side == _SpreadSide.left
            ? LinearGradient(
              colors: [color, color, edge],
              stops: const [0, 0.86, 1],
            )
            : LinearGradient(
              colors: [edge, color, color],
              stops: const [0, 0.14, 1],
            );
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: child ?? const SizedBox.expand(),
    );
  }
}

/// 中缝：中间最深，向两侧散开，读起来像两张纸贴在一起。
class _SpreadGutter extends StatelessWidget {
  const _SpreadGutter();

  @override
  Widget build(BuildContext context) {
    // 终值由 reader.css 的三选择器决定：峰值 .15，侧档按同比例降至 .06。
    return Container(
      width: _spreadGutterWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.06),
            Colors.black.withValues(alpha: 0.15),
            Colors.black.withValues(alpha: 0.15),
            Colors.black.withValues(alpha: 0.06),
            Colors.transparent,
          ],
          stops: const [0, 0.34, 0.496, 0.504, 0.66, 1],
        ),
      ),
    );
  }
}

/// 纸边堆叠（样例 `.spread .stack`）：一条 2.5px 周期的明暗条纹，
/// 宽度随阅读进度收缩，读起来像压在下面的一叠纸。
class _PaperStack extends StatelessWidget {
  const _PaperStack({required this.color, required this.side});

  final Color color;
  final _SpreadSide side;

  @override
  Widget build(BuildContext context) {
    final edge = Color.lerp(color, Colors.black, 0.07)!;
    final gap = Color.lerp(color, Colors.black, 0.12)!;
    return IgnorePointer(
      child: CustomPaint(
        painter: _PaperStackPainter(edge: edge, gap: gap, side: side),
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
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
      paint.color = gap;
      canvas.drawRect(Rect.fromLTWH(x + 1, 0, 1.5, size.height), paint);
    }
    // 靠外侧压深一点，纸叠才有厚度。
    final shade = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      shade,
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
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.18)],
        ).createShader(shade),
    );
  }

  @override
  bool shouldRepaint(_PaperStackPainter oldDelegate) =>
      oldDelegate.edge != edge ||
      oldDelegate.gap != gap ||
      oldDelegate.side != side;
}
