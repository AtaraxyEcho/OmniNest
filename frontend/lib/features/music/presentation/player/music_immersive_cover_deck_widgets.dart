part of 'music_immersive_player.dart';

/// 卡面右上的频谱均衡器条（样例五根白色竖条，高低错落且**播放时各自跳动**）。
class _DeckEqualizerMeter extends StatefulWidget {
  const _DeckEqualizerMeter({required this.active, required this.scale});

  /// 是否正在播放：样例的频谱只在播放时跳动，暂停后停在基准高度。
  final bool active;
  final double scale;

  /// 样例五根竖条的高度（`h-3 / h-5 / h-2 / h-4 / h-2.5` → px）。
  static const List<double> baseHeights = <double>[12, 20, 8, 16, 10];

  /// 样例五根竖条各自的跳动周期（`animate-[bounce_1.2s_infinite]` 等，秒）。
  static const List<double> periodSeconds = <double>[1.2, 0.8, 1.5, 1.0, 0.9];

  @override
  State<_DeckEqualizerMeter> createState() => _DeckEqualizerMeterState();
}

class _DeckEqualizerMeterState extends State<_DeckEqualizerMeter>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;
  bool _motionDisabled = false;

  @override
  void initState() {
    super.initState();
    _controllers = <AnimationController>[
      for (final period in _DeckEqualizerMeter.periodSeconds)
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: (period * 1000).round()),
          value: 0.5,
        ),
    ];
    _animations = <Animation<double>>[
      for (final controller in _controllers)
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    ];
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionDisabled = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant _DeckEqualizerMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _sync();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 播放时每根竖条各自错峰跳动；暂停或系统禁用动画时停在基准高度。
  void _sync() {
    if (!widget.active || _motionDisabled) {
      for (final controller in _controllers) {
        controller.stop();
      }
      return;
    }
    for (final controller in _controllers) {
      if (!controller.isAnimating) {
        controller.repeat(reverse: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kMusicDeckCardSurfaceColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: kMusicDeckCardBorderWidth * scale,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12 * scale,
          vertical: 6 * scale,
        ),
        // 纯装饰动效：竖条每帧改高度，若进入语义树，Windows 辅助功能桥会
        // 每帧重建 AXTree（error: 154），因此整体排除出语义树。
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < _controllers.length; i++) ...[
                AnimatedBuilder(
                  animation: _animations[i],
                  builder: (context, _) {
                    // bounce 的摆幅取基准高度的 60%，与样例的视觉幅度接近。
                    final swing = 1 + 0.6 * _animations[i].value;
                    return Container(
                      width: 2 * scale,
                      height:
                          _DeckEqualizerMeter.baseHeights[i] * swing * scale,
                      decoration: const BoxDecoration(color: Colors.white),
                    );
                  },
                ),
                SizedBox(width: 4 * scale),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 白色呼吸圆点（样例 `animate-pulse`）：角标播放态指示，尊重减少动态效果。
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.size});

  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.6;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 纯装饰的逐帧透明度动画：排除出语义树，避免辅助功能桥逐帧重建。
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Opacity(
            // pulse 的呼吸区间：满亮到 0.4，与 Tailwind pulse 的幅度一致。
            opacity: 0.4 + 0.6 * _controller.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DeckCardPressFeedback extends StatefulWidget {
  const _DeckCardPressFeedback({
    required this.cursor,
    required this.onTap,
    required this.onHoverChanged,
    required this.child,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
  });

  final MouseCursor cursor;
  final VoidCallback onTap;
  final ValueChanged<bool> onHoverChanged;
  final Widget child;
  final PointerDownEventListener? onPointerDown;
  final PointerMoveEventListener? onPointerMove;
  final PointerUpEventListener? onPointerUp;
  final PointerCancelEventListener? onPointerCancel;

  @override
  State<_DeckCardPressFeedback> createState() => _DeckCardPressFeedbackState();
}

class _DeckCardPressFeedbackState extends State<_DeckCardPressFeedback> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => widget.onHoverChanged(true),
      onExit: (_) => widget.onHoverChanged(false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.kind != PointerDeviceKind.mouse ||
              event.buttons != kSecondaryMouseButton) {
            setState(() => _pressed = true);
          }
          widget.onPointerDown?.call(event);
        },
        onPointerMove: widget.onPointerMove,
        onPointerUp: (event) {
          if (_pressed) {
            setState(() => _pressed = false);
          }
          widget.onPointerUp?.call(event);
        },
        onPointerCancel: (event) {
          if (_pressed) {
            setState(() => _pressed = false);
          }
          widget.onPointerCancel?.call(event);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.965 : 1,
            duration: MusicImmersiveMotion.duration(
              context,
              Duration(milliseconds: _pressed ? 90 : 180),
            ),
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
