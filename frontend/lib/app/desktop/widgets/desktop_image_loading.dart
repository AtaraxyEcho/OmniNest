part of 'desktop_surfaces.dart';

class _ImageShimmer extends StatefulWidget {
  const _ImageShimmer({required this.borderRadius});

  final BorderRadius? borderRadius;

  @override
  State<_ImageShimmer> createState() => _ImageShimmerState();
}

class _ImageShimmerState extends State<_ImageShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesktopMotion.imageShimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final base = skin.raise2;
    final highlight = Color.lerp(base, skin.text, 0.06)!;
    final radius = widget.borderRadius ?? BorderRadius.zero;
    return AnimatedBuilder(
      animation: _controller,
      builder:
          (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment(-1.6 + _controller.value * 3.2, 0),
                end: Alignment(-0.6 + _controller.value * 3.2, 0),
                colors: [base, highlight, base],
              ),
            ),
          ),
    );
  }
}

/// 解码完成后的 600ms 淡入；首帧渲染时才把透明度推到 1。
class _ImageFadeIn extends StatefulWidget {
  const _ImageFadeIn({required this.child});

  final Widget child;

  @override
  State<_ImageFadeIn> createState() => _ImageFadeInState();
}

class _ImageFadeInState extends State<_ImageFadeIn> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _shown = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: DesktopMotion.of(context, DesktopMotion.imageFade),
      curve: DesktopMotion.ease,
      alwaysIncludeSemantics: true,
      child: widget.child,
    );
  }
}

/// 卡片 hover 抬升 + 轻微放大，对应样例 `.tilt` / `.album:hover`。
