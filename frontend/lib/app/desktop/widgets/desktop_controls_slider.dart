part of 'desktop_controls.dart';

/// 样例 `.slider`：4px 轨道，悬停抬到 6px 并露出白色滑柄。
class DesktopSlider extends StatefulWidget {
  const DesktopSlider({
    required this.value,
    required this.max,
    required this.onChanged,
    this.min = 0,
    this.onCommit,
    this.width,
    this.height = 16,
    this.trackColor,
    this.fillColor,
    this.thumbColor,
    this.trackFill = true,
    this.thumbAlwaysVisible = false,
    this.thumbGlow = false,
    this.growTrackOnActive = true,
    this.thumbRadius = 6,
    this.thumbInset = 0,
    this.keyboardStep,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onCommit;
  final double? width;
  final double height;
  final Color? trackColor;
  final Color? fillColor;
  final Color? thumbColor;
  final bool trackFill;
  final bool thumbAlwaysVisible;
  final bool thumbGlow;
  final bool growTrackOnActive;
  final double thumbRadius;
  final double thumbInset;
  final double? keyboardStep;

  @override
  State<DesktopSlider> createState() => _DesktopSliderState();
}

class _DesktopSliderState extends State<DesktopSlider> {
  bool _dragging = false;
  bool _hovered = false;
  bool _focused = false;

  double _valueOf(double dx, double width) {
    if (width <= 0 || widget.max <= widget.min) {
      return widget.min;
    }
    final trackWidth =
        (width - widget.thumbInset * 2).clamp(1.0, width).toDouble();
    return widget.min +
        ((dx - widget.thumbInset) / trackWidth).clamp(0.0, 1.0) *
            (widget.max - widget.min);
  }

  /// 样例 `ui.tsx:51-52`：方向键步进可选范围的二十分之一。
  double get _step =>
      widget.keyboardStep ??
      (widget.max - widget.min).clamp(0.0, double.infinity) / 20;

  void _nudge(double delta) {
    final next = (widget.value + delta).clamp(widget.min, widget.max);
    if (next != widget.value) {
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final active = _dragging || _hovered || _focused;
    final fraction =
        widget.max <= widget.min
            ? 0.0
            : ((widget.value - widget.min) / (widget.max - widget.min)).clamp(
              0.0,
              1.0,
            );
    final thumbColor = widget.thumbColor ?? skin.onStage;
    final thumbSize = widget.thumbRadius * 2;
    return Focus(
      canRequestFocus: true,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowDown) {
          _nudge(-_step);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp) {
          _nudge(_step);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        slider: true,
        value: widget.value.round().toString(),
        increasedValue:
            (widget.value + _step)
                .clamp(widget.min, widget.max)
                .round()
                .toString(),
        decreasedValue:
            (widget.value - _step)
                .clamp(widget.min, widget.max)
                .round()
                .toString(),
        onIncrease: () => _nudge(_step),
        onDecrease: () => _nudge(-_step),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final next = _valueOf(details.localPosition.dx, width);
                    widget.onChanged(next);
                    widget.onCommit?.call(next);
                  },
                  onHorizontalDragStart: (details) {
                    setState(() => _dragging = true);
                    widget.onChanged(_valueOf(details.localPosition.dx, width));
                  },
                  onHorizontalDragUpdate:
                      (details) => widget.onChanged(
                        _valueOf(details.localPosition.dx, width),
                      ),
                  onHorizontalDragEnd: (_) {
                    setState(() => _dragging = false);
                    widget.onCommit?.call(widget.value);
                  },
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        // 样例 `.slider .track { transition: height .2s }`。
                        duration: MotionToken.reduced(
                          context,
                          DesktopMotion.fast,
                        ),
                        curve: MotionToken.curve,
                        height: widget.growTrackOnActive && active ? 6 : 4,
                        decoration: BoxDecoration(
                          color: widget.trackColor ?? skin.raise3,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child:
                              widget.trackFill
                                  ? FractionallySizedBox(
                                    widthFactor: fraction,
                                    child: ColoredBox(
                                      color: widget.fillColor ?? skin.accent,
                                    ),
                                  )
                                  : const SizedBox.shrink(),
                        ),
                      ),
                      Positioned(
                        left:
                            widget.thumbInset +
                            (width - widget.thumbInset * 2) * fraction -
                            widget.thumbRadius,
                        child: AnimatedScale(
                          duration: MotionToken.reduced(
                            context,
                            DesktopMotion.fast,
                          ),
                          curve: MotionToken.curve,
                          scale: active || widget.thumbAlwaysVisible ? 1 : 0,
                          child: Container(
                            width: thumbSize,
                            height: thumbSize,
                            decoration: BoxDecoration(
                              color: thumbColor,
                              shape: BoxShape.circle,
                              boxShadow: <BoxShadow>[
                                if (widget.thumbGlow)
                                  BoxShadow(
                                    color: thumbColor.withValues(alpha: 0.22),
                                    spreadRadius: active ? 7 : 4,
                                  ),
                                BoxShadow(
                                  color: skin.shadow.last.color,
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
