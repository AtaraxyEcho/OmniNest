part of 'reader_page_view.dart';

/// 跨页中缝悬浮宽度（样例 `reader.css:4`，不占用纸页宽度）。
const double _spreadGutterWidth = 70.0;

/// 双页跨页单元（样例 `.bookview .spread`）：
/// 硬壳封底底座（由桌面色动态派生）+ 可选悬停展平透视（默认关闭，保持平稳阅读）+
/// 左右严格 50% / 50% 贴合，单层柔和暖暗 70px 中缝阴影悬浮叠在接缝之上，
/// 左右动态厚度纸叠外挂于书框外缘，静动纸面共用同一份预烘焙噪点 Shader。
class ReaderPageSpread extends StatefulWidget {
  const ReaderPageSpread({
    required this.left,
    required this.right,
    required this.surfaceColor,
    this.paperEdgeColor,
    this.deskColor,
    this.leftBoundaryKey,
    this.rightBoundaryKey,
    this.progress = 0,
    this.curlOverlay,
    this.bookmarked = false,
    this.bookmarkOnLeft = false,
    this.showPaperGrain = true,
    this.enableHoverTilt = false,
    this.seamlessSpine = false,
    super.key,
  });

  final Widget left;
  final Widget? right;
  final Color surfaceColor;
  final Color? paperEdgeColor;

  /// 书桌底色；用于动态派生硬壳封底色，缺省由 `surfaceColor` 压暗派生。
  final Color? deskColor;

  /// 静止态与翻页态保持同一 RepaintBoundary 挂载槽，杜绝进入翻页第 1 帧整棵书页子树销毁重建。
  final GlobalKey? leftBoundaryKey;
  final GlobalKey? rightBoundaryKey;

  /// 全书/章内进度（0..1）：两侧纸叠厚度随进度动态变化。
  final double progress;

  /// 整幅双页卷曲层（.curl-clip），覆盖左右两页允许纸页扫过书脊。
  final Widget? curlOverlay;
  final bool bookmarked;

  /// 书签缎带挂在左叶外缘（RTL 日漫模式使用；默认 false 挂右叶外缘）。
  final bool bookmarkOnLeft;

  /// 是否叠加纸纹噪点；漫画深色页可关闭避免 `multiply` 混合使画面发灰。
  final bool showPaperGrain;

  /// 是否开启静息 `rotateX(6deg)` / hover 展平透视；默认关闭防止鼠标移入移出梯形翻转异动。
  final bool enableHoverTilt;

  /// 无缝跨页模式：书脊内侧圆角归零且仅保留外侧三边纸缘，适配漫画 0px 无缝拼合。
  final bool seamlessSpine;

  @override
  State<ReaderPageSpread> createState() => _ReaderPageSpreadState();
}

class _ReaderPageSpreadState extends State<ReaderPageSpread> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.progress.clamp(0.0, 1.0);
    final leftStackW = 3.0 + p * 13.0;
    final rightStackW = 3.0 + (1.0 - p) * 13.0;
    final edgeColor =
        widget.paperEdgeColor ??
        Color.lerp(widget.surfaceColor, Colors.black, 0.08)!;
    final isDarkPaper =
        ThemeData.estimateBrightnessForColor(widget.surfaceColor) ==
        Brightness.dark;
    // 单层柔和暖暗中缝阴影（强端 0.10–0.13）
    final gutterWeak = isDarkPaper ? 0.045 : 0.03;
    final gutterStrong = isDarkPaper ? 0.13 : 0.10;
    const warmSpineShadow = ReaderReadingPalette.bookSpineShadow;
    final effectiveDesk =
        widget.deskColor ??
        Color.lerp(widget.surfaceColor, Colors.black, 0.72)!;
    final coverTop =
        Color.lerp(effectiveDesk, ReaderReadingPalette.bookShellLeather, 0.45)!;
    final coverBottom =
        Color.lerp(effectiveDesk, ReaderReadingPalette.bookShellLeather, 0.38)!;
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final Matrix4 perspectiveTransform;
    if (widget.enableHoverTilt) {
      final tiltRadians = _hovered ? 0.0 : (6.0 * math.pi / 180.0);
      perspectiveTransform =
          Matrix4.identity()
            ..setEntry(3, 2, 0.00042)
            ..rotateX(tiltRadians);
    } else {
      perspectiveTransform = Matrix4.identity();
    }

    // 关键修复：始终保持 RepaintBoundary 挂载在同一节点位置，不因 key 为空或状态切换拆卸边界节点。
    Widget wrapBoundary(GlobalKey? key, Widget child) =>
        RepaintBoundary(key: key, child: child);

    return MouseRegion(
      onEnter:
          widget.enableHoverTilt
              ? (_) {
                if (!_hovered) setState(() => _hovered = true);
              }
              : null,
      onExit:
          widget.enableHoverTilt
              ? (_) {
                if (_hovered) setState(() => _hovered = false);
              }
              : null,
      child: AnimatedContainer(
        duration:
            animationsDisabled || !widget.enableHoverTilt
                ? Duration.zero
                : const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        transformAlignment: Alignment.center,
        transform: perspectiveTransform,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 硬壳封底底座（由 deskColor 动态派生）
            Positioned(
              left: -leftStackW - 4,
              right: -rightStackW - 4,
              top: -4,
              bottom: -6,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [coverTop, coverBottom],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.65),
                        blurRadius: 56,
                        spreadRadius: -14,
                        offset: const Offset(0, 32),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 左侧外挂纸叠（.spread .stack.l）
            Positioned(
              left: -leftStackW + 2,
              top: 3,
              bottom: 3,
              width: leftStackW,
              child: _PaperStack(
                edgeColor: edgeColor,
                paperColor: widget.surfaceColor,
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
                paperColor: widget.surfaceColor,
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
                            widget.leftBoundaryKey,
                            _SpreadPage(
                              color: widget.surfaceColor,
                              side: _SpreadSide.left,
                              showPaperGrain: widget.showPaperGrain,
                              seamlessSpine: widget.seamlessSpine,
                              child: widget.left,
                            ),
                          ),
                        ),
                        Expanded(
                          child: wrapBoundary(
                            widget.rightBoundaryKey,
                            _SpreadPage(
                              color: widget.surfaceColor,
                              side: _SpreadSide.right,
                              showPaperGrain: widget.showPaperGrain,
                              seamlessSpine: widget.seamlessSpine,
                              child: widget.right,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 70px 单层柔和暖暗中缝阴影悬浮叠在 50% 接缝之上（不占宽、不拦截选区）
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            width: _spreadGutterWidth,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  warmSpineShadow.withValues(alpha: gutterWeak),
                                  warmSpineShadow.withValues(
                                    alpha: gutterStrong,
                                  ),
                                  warmSpineShadow.withValues(
                                    alpha: gutterStrong,
                                  ),
                                  warmSpineShadow.withValues(alpha: gutterWeak),
                                  Colors.transparent,
                                ],
                                stops: const [
                                  0.0,
                                  0.30,
                                  0.495,
                                  0.505,
                                  0.70,
                                  1.0,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 固定占位槽：静止态与翻页态保持 Stack 子节点结构完全一致，零槽位抖动。
                    Positioned.fill(
                      child: IgnorePointer(
                        child: widget.curlOverlay ?? const SizedBox.shrink(),
                      ),
                    ),
                    if (widget.bookmarked)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: LayoutBuilder(
                            builder:
                                (context, c) => Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      top: -2,
                                      left:
                                          widget.bookmarkOnLeft
                                              ? c.maxWidth * 0.08
                                              : null,
                                      right:
                                          widget.bookmarkOnLeft
                                              ? null
                                              : c.maxWidth * 0.08,
                                      child: ClipPath(
                                        clipper: const _SpreadRibbonClipper(),
                                        child: Container(
                                          width: 16,
                                          height: 40,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
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
        ),
      ),
    );
  }
}

/// 单页精装书壳组件：复用 [ReaderPageSpread] 同源硬壳封底、单侧动态纸叠、
/// 双层桌面投影与书签缎带，供漫画单页 Book 模式呈现精装实体书质感。
class ReaderSinglePageBookShell extends StatelessWidget {
  const ReaderSinglePageBookShell({
    required this.child,
    required this.surfaceColor,
    this.paperEdgeColor,
    this.deskColor,
    this.progress = 0,
    this.bookmarked = false,
    this.bookmarkOnLeft = false,
    this.stackOnLeft = false,
    this.showPaperGrain = false,
    super.key,
  });

  final Widget child;
  final Color surfaceColor;
  final Color? paperEdgeColor;
  final Color? deskColor;
  final double progress;
  final bool bookmarked;
  final bool bookmarkOnLeft;
  final bool stackOnLeft;
  final bool showPaperGrain;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final stackW = 3.0 + (1.0 - p) * 11.0;
    final edgeColor =
        paperEdgeColor ?? Color.lerp(surfaceColor, Colors.black, 0.08)!;
    final isDarkPaper =
        ThemeData.estimateBrightnessForColor(surfaceColor) == Brightness.dark;
    final effectiveDesk =
        deskColor ?? Color.lerp(surfaceColor, Colors.black, 0.72)!;
    final coverTop =
        Color.lerp(effectiveDesk, ReaderReadingPalette.bookShellLeather, 0.45)!;
    final coverBottom =
        Color.lerp(effectiveDesk, ReaderReadingPalette.bookShellLeather, 0.38)!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 同源硬壳封底底座
        Positioned(
          left: stackOnLeft ? -stackW - 4 : -4,
          right: stackOnLeft ? -4 : -stackW - 4,
          top: -4,
          bottom: -6,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [coverTop, coverBottom],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 56,
                    spreadRadius: -14,
                    offset: const Offset(0, 32),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 单侧外挂纸叠
        Positioned(
          left: stackOnLeft ? -stackW + 2 : null,
          right: stackOnLeft ? null : -stackW + 2,
          top: 3,
          bottom: 3,
          width: stackW,
          child: _PaperStack(
            edgeColor: edgeColor,
            paperColor: surfaceColor,
            side: stackOnLeft ? _SpreadSide.left : _SpreadSide.right,
          ),
        ),
        // 书本主体（6px 圆角 + 双层桌面投影）
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
                ColoredBox(color: surfaceColor, child: child),
                if (showPaperGrain)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _PaperGrainOverlayPainter()),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 7,
                  bottom: 7,
                  width: 2,
                  left: stackOnLeft ? 0 : null,
                  right: stackOnLeft ? null : 0,
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.white.withValues(
                        alpha: isDarkPaper ? 0.09 : 0.40,
                      ),
                    ),
                  ),
                ),
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
                                  left:
                                      bookmarkOnLeft ? c.maxWidth * 0.08 : null,
                                  right:
                                      bookmarkOnLeft ? null : c.maxWidth * 0.08,
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
    this.showPaperGrain = true,
    this.seamlessSpine = false,
  });

  final Color color;
  final _SpreadSide side;
  final Widget? child;
  final bool showPaperGrain;
  final bool seamlessSpine;

  @override
  Widget build(BuildContext context) {
    final isDark =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
    // 无缝跨页时内侧书脊圆角归零；常规书页保持外缘 9px / 内侧 2px 圆角。
    final innerRadius = seamlessSpine ? Radius.zero : const Radius.circular(2);
    final leafRadius =
        side == _SpreadSide.left
            ? BorderRadius.only(
              topLeft: const Radius.circular(9),
              bottomLeft: const Radius.circular(9),
              topRight: innerRadius,
              bottomRight: innerRadius,
            )
            : BorderRadius.only(
              topRight: const Radius.circular(9),
              bottomRight: const Radius.circular(9),
              topLeft: innerRadius,
              bottomLeft: innerRadius,
            );
    final edgeBorderSide = BorderSide(
      color: Colors.black.withValues(alpha: 0.12),
    );
    return ClipRRect(
      borderRadius: leafRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: color,
            child: child ?? SizedBox.expand(child: ColoredBox(color: color)),
          ),
          if (showPaperGrain)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _PaperGrainOverlayPainter()),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration:
                    seamlessSpine
                        // 无缝跨页仅保留外侧三边纸缘，避免中缝叠加黑线。
                        ? BoxDecoration(
                          border: Border(
                            top: edgeBorderSide,
                            bottom: edgeBorderSide,
                            left:
                                side == _SpreadSide.left
                                    ? edgeBorderSide
                                    : BorderSide.none,
                            right:
                                side == _SpreadSide.right
                                    ? edgeBorderSide
                                    : BorderSide.none,
                          ),
                        )
                        // Flutter 不允许「圆角 + 非均匀边框色」，常规页走均一细边。
                        : BoxDecoration(
                          borderRadius: leafRadius,
                          border: Border.fromBorderSide(edgeBorderSide),
                        ),
              ),
            ),
          ),
          Positioned(
            top: 7,
            bottom: 7,
            width: 2,
            left: side == _SpreadSide.left ? 0 : null,
            right: side == _SpreadSide.right ? 0 : null,
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.white.withValues(alpha: isDark ? 0.09 : 0.40),
              ),
            ),
          ),
        ],
      ),
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
