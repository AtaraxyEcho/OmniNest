import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 工位自绘控件的键盘可达外壳。
///
/// 工位控件全部是裸 `MouseRegion + GestureDetector`，不包这层就落在 Tab
/// 顺序之外（PRODUCT.md 要求桌面端有可预期的键盘导航与可见 focus ring）。
/// 焦点高亮沿用悬停同一档的边框提升：`FocusableActionDetector` 只上报高亮
/// 意图、自己不画任何东西，边框由调用方的 builder 按 [builder] 收到的
/// `focused` 自绘，既保证「可见」，也不改变控件几何尺寸。
///
/// 语义也集中在这一层声明：内部 GestureDetector 必须 `excludeFromSemantics`，
/// 否则读屏会听到两个可点节点。
class WorkstationFocusTarget extends StatefulWidget {
  const WorkstationFocusTarget({
    required this.enabled,
    required this.onActivate,
    required this.builder,
    this.semanticLabel,
    this.checked,
    this.toggled,
    this.selected = false,
    super.key,
  });

  final bool enabled;
  final VoidCallback onActivate;

  /// 由调用方按焦点态自绘：[focused] 与悬停共享同一档视觉提升。
  final Widget Function(BuildContext context, bool focused) builder;

  final String? semanticLabel;

  /// 复选语义（✔ 控件）；为 null 时不声明 checked。
  final bool? checked;

  /// 开关语义；为 null 时不声明 toggled。
  final bool? toggled;

  /// 单选/分段选中语义。
  final bool selected;

  @override
  State<WorkstationFocusTarget> createState() => _WorkstationFocusTargetState();
}

class _WorkstationFocusTargetState extends State<WorkstationFocusTarget> {
  bool _focused = false;
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed != pressed) {
      setState(() => _pressed = pressed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Semantics(
      button: true,
      enabled: enabled,
      checked: widget.checked,
      toggled: widget.toggled,
      selected: widget.selected,
      label: widget.semanticLabel,
      onTap: enabled ? widget.onActivate : null,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (focused) {
          if (_focused != focused) {
            setState(() => _focused = focused);
          }
        },
        shortcuts: const <SingleActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onActivate();
              return null;
            },
          ),
        },
        child: Listener(
          onPointerDown: enabled ? (_) => _setPressed(true) : null,
          onPointerUp: enabled ? (_) => _setPressed(false) : null,
          onPointerCancel: enabled ? (_) => _setPressed(false) : null,
          // 仅绘制期缩放，不参与布局；焦点环仍不改变控件几何尺寸。
          child: AnimatedScale(
            scale: _pressed ? 0.98 : 1.0,
            duration: MotionToken.reduced(context, MotionToken.fast),
            curve: MotionToken.curve,
            child: Builder(
              builder: (context) => widget.builder(context, _focused),
            ),
          ),
        ),
      ),
    );
  }
}
