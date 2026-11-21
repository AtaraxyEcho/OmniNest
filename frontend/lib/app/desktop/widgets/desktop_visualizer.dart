import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import 'package:omninest/app/theme/desktop/desktop_motion.dart';

/// 样例 `ui.tsx` 的 `Visualizer`：弹簧阻尼的频谱柱。
///
/// 逐帧推进的不是正弦而是「目标值 + 速度阻尼」：柱高会互相追不上，
/// 停止播放时自然回落而不是整体归零。参数照抄样例（0.22 追速、0.62 阻尼、
/// 每帧 0.016s），换算法会让观感与样例明显不同。
class DesktopVisualizer extends StatefulWidget {
  const DesktopVisualizer({
    required this.playing,
    required this.color,
    this.bars = 14,
    this.seed = 1,
    super.key,
  });

  final bool playing;
  final Color color;
  final int bars;
  final double seed;

  @override
  State<DesktopVisualizer> createState() => _DesktopVisualizerState();
}

class _DesktopVisualizerState extends State<DesktopVisualizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late List<double> _value = List<double>.filled(widget.bars, 0.05);
  late List<double> _velocity = List<double>.filled(widget.bars, 0);
  final math.Random _random = math.Random(7);
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(DesktopVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bars != widget.bars) {
      _value = List<double>.filled(widget.bars, 0.05);
      _velocity = List<double>.filled(widget.bars, 0);
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// 只有「正在播放」才值得逐帧推进。
  ///
  /// 此前 ticker 在 initState 里无条件启动，且永不停止：没有音乐时也以
  /// 60fps 空跑弹簧公式并每帧 setState，播放条所在的毛玻璃子树跟着每帧
  /// 重建。停止播放后柱子会自然回落到静止高度，回落完成即可停表——静止
  /// 后的画面与继续空转逐像素一致。
  void _syncTicker() {
    final animated =
        widget.playing &&
        !WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    if (animated && !_ticker.isActive) {
      _ticker.start();
    } else if (!animated && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration _) {
    _time += 0.016;
    final playing = widget.playing;
    final bars = widget.bars;
    var settled = !playing;
    for (var i = 0; i < bars; i++) {
      final f = i / bars;
      final target =
          playing
              ? (0.18 +
                      0.55 *
                          ((math.sin(_time * 2.1 + i * 0.5 + widget.seed) *
                                  math.cos(_time * 0.9 + i * 0.21))
                              .abs()) +
                      0.25 * _random.nextDouble() * (1 - f * 0.6)) *
                  (1 - f * 0.45)
              : 0.05;
      _velocity[i] += (target - _value[i]) * 0.22;
      _velocity[i] *= 0.62;
      _value[i] += _velocity[i];
      if (!playing &&
          ((_value[i] - 0.05).abs() > 0.0005 || _velocity[i].abs() > 0.0005)) {
        settled = false;
      }
    }
    if (settled) {
      // 停在静止态并关表：与继续空转的输出一致，但不再产生任何一帧。
      for (var i = 0; i < bars; i++) {
        _value[i] = 0.05;
        _velocity[i] = 0;
      }
      _ticker.stop();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // 每帧 setState 的是这根频谱自己：单独成层后重绘只发生在这里，
    // 不会把父级（播放条玻璃、NP 面板）一起拖进每帧重录。
    return RepaintBoundary(
      child: CustomPaint(
        painter: _VisualizerPainter(
          // `_tick` 原地改 `_value`，列表引用始终不变；若直接传引用，
          // `shouldRepaint` 的 `old.values != values` 永远为 false，柱高
          // 每帧算了却不会画出来——表现就是播放时频谱完全静止。
          values: List<double>.of(_value),
          color: widget.color,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  const _VisualizerPainter({
    required this.values,
    required this.color,
    required this.devicePixelRatio,
  });

  final List<double> values;
  final Color color;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = values.length;
    if (bars == 0 || size.height <= 0) {
      return;
    }
    final dpr = math.min(2.0, devicePixelRatio);
    final barWidth = size.width / bars;
    final paint = Paint();
    for (var i = 0; i < bars; i++) {
      final h = math.max(2 * dpr, values[i] * size.height);
      paint.color = color.withValues(
        alpha: (0.35 + values[i] * 0.65).clamp(0.0, 1.0),
      );
      final x = i * barWidth + barWidth * 0.2;
      final w = barWidth * 0.6;
      final rect = Rect.fromLTWH(x, size.height - h, w, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(w / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_VisualizerPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.devicePixelRatio != devicePixelRatio;
  }
}

/// 样例 `.eq`：三根 1s 循环的柱，相位分别延迟 -0.4s / -0.8s。
///
/// 用在「正在播放」的队列行上；播放暂停时按 CSS 的做法停在动画上
/// （高度不动），不在暂停瞬间归零。
class DesktopEqualizer extends StatefulWidget {
  const DesktopEqualizer({required this.color, this.size = 14, super.key});

  final Color color;
  final double size;

  @override
  State<DesktopEqualizer> createState() => _DesktopEqualizerState();
}

class _DesktopEqualizerState extends State<DesktopEqualizer>
    with SingleTickerProviderStateMixin {
  /// 三根 3px 柱 + 两道 2px 间隙 = 13px，即样例 `.eq` 的实占宽度。
  /// 盒子宽度曾按 `size * 0.55` 推算（`size=13` 时只有 7.15px），三根柱连同
  /// 间隙要 13px，每帧都抛一次 `RenderFlex overflowed`。
  static const double _barWidth = 3;
  static const double _gapWidth = 2;
  static const double _boxWidth = _barWidth * 3 + _gapWidth * 2;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesktopMotion.beat,
  );

  @override
  void initState() {
    super.initState();
    if (!(WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations)) {
      _controller.repeat();
    } else {
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _boxWidth,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  // 末根不带尾隙：三根柱加两道间隙正好等于盒子宽度。
                  padding: EdgeInsets.only(right: i < 2 ? _gapWidth : 0),
                  child: Container(
                    width: _barWidth,
                    height: _heightAt(_controller.value, i),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// `@keyframes eq { 0%,100% { height: 3px } 50% { height: 14px } }`
  double _heightAt(double t, int index) {
    final phase = (t + index * 0.4) % 1.0;
    final wave = 0.5 - 0.5 * math.cos(phase * math.pi * 2);
    return 3 + (widget.size - 3) * wave;
  }
}
