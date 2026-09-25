import 'package:flutter/material.dart';

/// 曲目行「正在播放」动态指示：三根竖条错峰跳动。
///
/// 播放中持续动画，暂停后停在基准高度；系统禁用动画时同样静止。
/// 纯装饰组件，整体排除出语义树，避免 Windows 辅助功能桥每帧重建。
class MusicPlayingBars extends StatefulWidget {
  const MusicPlayingBars({
    this.color,
    this.size = 16,
    this.barWidth = 2.5,
    this.active = true,
    super.key,
  });

  /// 竖条颜色；空则取主题 primary。
  final Color? color;

  /// 指示器占位边长（含跳动摆幅）。
  final double size;

  final double barWidth;

  /// 是否处于播放中；false 时停在基准高度。
  final bool active;

  @override
  State<MusicPlayingBars> createState() => _MusicPlayingBarsState();
}

class _MusicPlayingBarsState extends State<MusicPlayingBars>
    with TickerProviderStateMixin {
  static const List<double> _baseHeights = <double>[0.38, 0.72, 0.52];
  static const List<double> _periodMs = <double>[620, 480, 760];

  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;
  bool _motionDisabled = false;

  @override
  void initState() {
    super.initState();
    _controllers = <AnimationController>[
      for (final periodMs in _periodMs)
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: periodMs.round()),
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
  void didUpdateWidget(covariant MusicPlayingBars oldWidget) {
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
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final size = widget.size;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < _controllers.length; i++) ...[
                AnimatedBuilder(
                  animation: _animations[i],
                  builder: (context, _) {
                    final swing = 1 + 0.55 * _animations[i].value;
                    final height = size * _baseHeights[i] * swing;
                    return Container(
                      width: widget.barWidth,
                      height: height.clamp(widget.barWidth, size),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  },
                ),
                if (i != _controllers.length - 1)
                  SizedBox(width: widget.barWidth * 0.7),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
