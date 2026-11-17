import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 跨平台滑杆，在 Windows 上避开 Flutter Slider 的 AXTree 更新缺陷。
class AppSlider extends StatelessWidget {
  const AppSlider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.semanticLabel,
    this.semanticFormatterCallback,
    this.onChangeStart,
    this.onChangeEnd,
    this.activeColor,
    this.inactiveColor,
    super.key,
  }) : assert(min <= max),
       assert(value >= min && value <= max),
       assert(divisions == null || divisions > 0);

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final String? semanticLabel;
  final SemanticFormatterCallback? semanticFormatterCallback;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Theme.of(context).platform == TargetPlatform.windows) {
      return _WindowsSafeSlider(
        value: value,
        onChanged: onChanged,
        min: min,
        max: max,
        divisions: divisions,
        semanticLabel: semanticLabel,
        semanticValue: _formatSemanticValue(value),
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        activeColor: activeColor,
        inactiveColor: inactiveColor,
      );
    }
    return Slider(
      value: value,
      onChanged: onChanged,
      min: min,
      max: max,
      divisions: divisions,
      label: label,
      semanticFormatterCallback: semanticFormatterCallback,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
    );
  }

  String _formatSemanticValue(double current) {
    if (semanticFormatterCallback != null) {
      return semanticFormatterCallback!(current);
    }
    if (label != null && label!.isNotEmpty) {
      return label!;
    }
    if (divisions != null || current == current.roundToDouble()) {
      return current.toStringAsFixed(0);
    }
    return current.toStringAsFixed(2);
  }
}

class _WindowsSafeSlider extends StatefulWidget {
  const _WindowsSafeSlider({
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.semanticValue,
    this.divisions,
    this.semanticLabel,
    this.onChangeStart,
    this.onChangeEnd,
    this.activeColor,
    this.inactiveColor,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final String? semanticLabel;
  final String semanticValue;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  State<_WindowsSafeSlider> createState() => _WindowsSafeSliderState();
}

class _WindowsSafeSliderState extends State<_WindowsSafeSlider> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;
  bool _hovered = false;
  bool _dragging = false;
  double? _interactionValue;

  bool get _enabled => widget.onChanged != null && widget.max > widget.min;

  double get _normalizedValue {
    if (widget.max <= widget.min) {
      return 0;
    }
    return ((widget.value - widget.min) / (widget.max - widget.min)).clamp(
      0.0,
      1.0,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sliderTheme = SliderTheme.of(context);
    final activeColor =
        widget.activeColor ??
        (_enabled
            ? sliderTheme.activeTrackColor
            : sliderTheme.disabledActiveTrackColor) ??
        theme.colorScheme.primary;
    final inactiveColor =
        widget.inactiveColor ??
        (_enabled
            ? sliderTheme.inactiveTrackColor
            : sliderTheme.disabledInactiveTrackColor) ??
        theme.colorScheme.surfaceContainerHighest;
    final thumbColor =
        (_enabled ? sliderTheme.thumbColor : sliderTheme.disabledThumbColor) ??
        activeColor;
    final thumbShape = sliderTheme.thumbShape;
    final thumbRadius =
        thumbShape is RoundSliderThumbShape
            ? (_enabled
                ? thumbShape.enabledThumbRadius
                : thumbShape.disabledThumbRadius ??
                    thumbShape.enabledThumbRadius)
            : 8.0;
    final trackHeight = sliderTheme.trackHeight ?? 4;
    final stepValue = _stepValue;
    final decreased = _quantize(widget.value - stepValue);
    final increased = _quantize(widget.value + stepValue);

    return Semantics(
      slider: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      decreasedValue: _formatValue(decreased),
      increasedValue: _formatValue(increased),
      onDecrease: _enabled ? () => _commitKeyboardValue(decreased) : null,
      onIncrease: _enabled ? () => _commitKeyboardValue(increased) : null,
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: _enabled,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: _handleKeyEvent,
        child: MouseRegion(
          cursor:
              _enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.forbidden,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: SizedBox(
              height: 48,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width =
                      constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : 0.0;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp:
                        _enabled
                            ? (details) => _commitTap(
                              details.localPosition.dx,
                              width,
                              thumbRadius,
                              Directionality.of(context),
                            )
                            : null,
                    onHorizontalDragStart:
                        _enabled
                            ? (details) => _beginDrag(
                              details.localPosition.dx,
                              width,
                              thumbRadius,
                              Directionality.of(context),
                            )
                            : null,
                    onHorizontalDragUpdate:
                        _enabled
                            ? (details) => _updateFromPosition(
                              details.localPosition.dx,
                              width,
                              thumbRadius,
                              Directionality.of(context),
                            )
                            : null,
                    onHorizontalDragEnd: _enabled ? (_) => _endDrag() : null,
                    onHorizontalDragCancel: _enabled ? _cancelDrag : null,
                    child: CustomPaint(
                      size: Size(width, constraints.maxHeight),
                      painter: _WindowsSafeSliderPainter(
                        progress: _normalizedValue,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        thumbColor: thumbColor,
                        focusColor: sliderTheme.overlayColor ?? activeColor,
                        trackHeight: trackHeight,
                        thumbRadius: thumbRadius,
                        highlighted: _focused || _hovered || _dragging,
                        textDirection: Directionality.of(context),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  double get _stepValue {
    final range = widget.max - widget.min;
    if (range <= 0) {
      return 0;
    }
    return widget.divisions != null ? range / widget.divisions! : range / 20;
  }

  String _formatValue(double current) {
    if (widget.divisions != null || current == current.roundToDouble()) {
      return current.toStringAsFixed(0);
    }
    return current.toStringAsFixed(2);
  }

  double _quantize(double rawValue) {
    final clamped = rawValue.clamp(widget.min, widget.max).toDouble();
    final divisions = widget.divisions;
    if (divisions == null || divisions <= 0 || widget.max <= widget.min) {
      return clamped;
    }
    final step = (widget.max - widget.min) / divisions;
    final stepIndex = ((clamped - widget.min) / step).round();
    return (widget.min + stepIndex * step)
        .clamp(widget.min, widget.max)
        .toDouble();
  }

  double _valueForPosition(
    double dx,
    double width,
    double thumbRadius,
    TextDirection textDirection,
  ) {
    final trackWidth = math.max(1.0, width - thumbRadius * 2);
    var fraction = ((dx - thumbRadius) / trackWidth).clamp(0.0, 1.0);
    if (textDirection == TextDirection.rtl) {
      fraction = 1 - fraction;
    }
    return _quantize(widget.min + fraction * (widget.max - widget.min));
  }

  void _commitTap(
    double dx,
    double width,
    double thumbRadius,
    TextDirection textDirection,
  ) {
    _focusNode.requestFocus();
    final next = _valueForPosition(dx, width, thumbRadius, textDirection);
    widget.onChangeStart?.call(widget.value);
    widget.onChanged?.call(next);
    widget.onChangeEnd?.call(next);
  }

  void _beginDrag(
    double dx,
    double width,
    double thumbRadius,
    TextDirection textDirection,
  ) {
    _focusNode.requestFocus();
    setState(() => _dragging = true);
    widget.onChangeStart?.call(widget.value);
    _updateFromPosition(dx, width, thumbRadius, textDirection);
  }

  void _updateFromPosition(
    double dx,
    double width,
    double thumbRadius,
    TextDirection textDirection,
  ) {
    final next = _valueForPosition(dx, width, thumbRadius, textDirection);
    _interactionValue = next;
    widget.onChanged?.call(next);
  }

  void _endDrag() {
    final next = _interactionValue ?? widget.value;
    setState(() => _dragging = false);
    _interactionValue = null;
    widget.onChangeEnd?.call(next);
  }

  void _cancelDrag() {
    setState(() => _dragging = false);
    _interactionValue = null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_enabled || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp) {
      _commitKeyboardValue(_quantize(widget.value + _stepValue));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowDown) {
      _commitKeyboardValue(_quantize(widget.value - _stepValue));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _commitKeyboardValue(widget.min);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _commitKeyboardValue(widget.max);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _commitKeyboardValue(double next) {
    if (next == widget.value) {
      return;
    }
    widget.onChangeStart?.call(widget.value);
    widget.onChanged?.call(next);
    widget.onChangeEnd?.call(next);
  }
}

class _WindowsSafeSliderPainter extends CustomPainter {
  const _WindowsSafeSliderPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.focusColor,
    required this.trackHeight,
    required this.thumbRadius,
    required this.highlighted,
    required this.textDirection,
  });

  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final Color focusColor;
  final double trackHeight;
  final double thumbRadius;
  final bool highlighted;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final left = thumbRadius;
    final right = math.max(left, size.width - thumbRadius);
    final centerY = size.height / 2;
    final trackRadius = Radius.circular(trackHeight / 2);
    final track = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        left,
        centerY - trackHeight / 2,
        right,
        centerY + trackHeight / 2,
      ),
      trackRadius,
    );
    canvas.drawRRect(track, Paint()..color = inactiveColor);

    final fraction =
        textDirection == TextDirection.rtl ? 1 - progress : progress;
    final thumbX = left + (right - left) * fraction;
    final activeRect =
        textDirection == TextDirection.rtl
            ? Rect.fromLTRB(
              thumbX,
              centerY - trackHeight / 2,
              right,
              centerY + trackHeight / 2,
            )
            : Rect.fromLTRB(
              left,
              centerY - trackHeight / 2,
              thumbX,
              centerY + trackHeight / 2,
            );
    canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, trackRadius),
      Paint()..color = activeColor,
    );
    if (highlighted) {
      canvas.drawCircle(
        Offset(thumbX, centerY),
        thumbRadius + 5,
        Paint()..color = focusColor.withValues(alpha: 0.18),
      );
    }
    canvas.drawCircle(
      Offset(thumbX, centerY + 1),
      thumbRadius + 1,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      Offset(thumbX, centerY),
      thumbRadius,
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(_WindowsSafeSliderPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        activeColor != oldDelegate.activeColor ||
        inactiveColor != oldDelegate.inactiveColor ||
        thumbColor != oldDelegate.thumbColor ||
        focusColor != oldDelegate.focusColor ||
        trackHeight != oldDelegate.trackHeight ||
        thumbRadius != oldDelegate.thumbRadius ||
        highlighted != oldDelegate.highlighted ||
        textDirection != oldDelegate.textDirection;
  }
}
