import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart'
    show LengthLimitingTextInputFormatter, TextInputFormatter;

import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';

/// 输入框表面：面板里用 `raise`，页面（首启向导）里用页面底色。
enum DesktopFieldTone { panel, page }

/// 桌面输入框（样例 `.field` / `.sf`）。
///
/// 不复用 `OmniTextField`：那套的边框、填充与焦点环都取自
/// `AppThemePalette`，放进桌面皮肤会出现另一套底色与 1px 焦点内描边。
/// 这里只保留桌面需要的视觉：常规、聚焦（accent 描边 + 4px / 18% 外环 +
/// raise2 底色）、出错（`#e57a74` 描边 + `.sf-err` 文案），以及样例
/// `.sf` 的装饰族（label 12/500、helper/err 11.5、必填、计数）。
class DesktopTextField extends StatefulWidget {
  const DesktopTextField({
    required this.controller,
    this.label,
    this.hint,
    this.helper,
    this.error,
    this.required = false,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.counterBuilder,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.prefixIcon,
    this.labelIcon,
    this.trailing,
    this.width,
    this.height = 40,
    this.tone = DesktopFieldTone.panel,
    this.maxLines = 1,
    this.enabled = true,
    this.selectAllOnFocus = false,
    this.obscure = false,
    this.focusNode,
    this.keyName,
    this.focusRing = true,
    super.key,
  });

  final TextEditingController controller;

  /// 样例 `.sf > label` / `.field > label`：字段上方的 12/500 标签。
  final String? label;

  /// 空值占位（样例 `placeholder`，如 `2024` / `2h 14m` / `8.0`）。
  final String? hint;

  /// 样例 `.sf-hint`：常态辅助行 11.5。
  final String? helper;

  /// 样例 `.sf.bad` + `.sf-err`：出错时描边转 `#e57a74` 并显示该文案。
  final String? error;

  /// 必填标记，跟在 [label] 之后。
  final bool required;

  /// 样例 `maxLength={4}`：只截断输入，不画 Material 字数计数器。
  final int? maxLength;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;

  /// 自带计数的自定义文案（样例 `· {n} lines`），入参是当前文本。
  final String Function(String text)? counterBuilder;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final IconData? prefixIcon;

  /// 字段标签前的图标（首启表单样例 `.sf > label svg`）。
  final IconData? labelIcon;

  /// 尾部控件（密码可见性开关等），与 [prefixIcon] 互不影响。
  final Widget? trailing;
  final double? width;

  /// 样例 `.field` 默认 40；`.sf`（Setup）是 36，调用方自己传。
  final double height;

  /// 面板里底色抬一档（`raise` / 聚焦 `raise2`）；页面上用 `bg`。
  final DesktopFieldTone tone;

  /// 大于 1 时按多行输入排版：内容顶对齐、占满 [height] 并在内部滚动。
  final int maxLines;

  final bool enabled;

  /// 重命名时选中原名，避免用户先要手动全选。
  final bool selectAllOnFocus;

  /// 密码输入：隐藏字符并禁用自动纠错/联想。
  final bool obscure;

  /// 外部焦点节点：表单需要在校验失败时把焦点送到第一个出错字段。
  final FocusNode? focusNode;

  /// 供测试定位（`find.byKey(ValueKey('...'))`）。
  final String? keyName;

  /// 是否在聚焦时于边框外侧绘制镂空聚焦光环；工具栏紧凑筛选框可传 false。
  final bool focusRing;

  @override
  State<DesktopTextField> createState() => _DesktopTextFieldState();
}

class _DesktopTextFieldState extends State<DesktopTextField> {
  FocusNode? _internalFocus;

  FocusNode get _focus => widget.focusNode ?? (_internalFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(DesktopTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _internalFocus)?.removeListener(_onFocusChanged);
      _focus.addListener(_onFocusChanged);
      setState(() {});
    }
  }

  void _onFocusChanged() {
    if (_focus.hasFocus && widget.selectAllOnFocus) {
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    (widget.focusNode ?? _internalFocus)?.removeListener(_onFocusChanged);
    _internalFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final decorated = _decorate(skin, _field(skin));
    if (widget.width == null) {
      return decorated;
    }
    return SizedBox(width: widget.width, child: decorated);
  }

  Widget _field(DesktopSkin skin) {
    final focused = _focus.hasFocus;
    final multiline = widget.maxLines > 1;
    final page = widget.tone == DesktopFieldTone.page;
    final radius = BorderRadius.circular(
      page ? DesktopMetrics.radiusIconButton : DesktopMetrics.radiusButton,
    );
    final fill = page ? skin.bg : skin.raise;
    final fillFocused = page ? skin.bg2 : skin.raise2;
    final bad = widget.error != null;
    final lineColor = bad ? DesktopPalette.bad : skin.line2;
    // 仅在边框外侧绘制镂空聚焦光环（0% 内部渗色、0px 布局抖动），
    // focusRing == false 时只保留 1px 强调色边框。
    final field = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: (widget.focusRing && focused) ? 1.0 : 0.0),
      duration: MotionToken.reduced(context, const Duration(milliseconds: 200)),
      curve: Curves.easeOut,
      builder: (context, t, child) {
        final shadows =
            t <= 0.001
                ? const <BoxShadow>[]
                : [
                  BoxShadow(
                    color:
                        bad
                            ? const Color(
                              0xFFE0655F,
                            ).withValues(alpha: 0.18 * t)
                            : skin.accent.withValues(alpha: 0.16 * t),
                    blurRadius: 0,
                    spreadRadius: 3,
                  ),
                ];
        return DesktopOutsetShadow(
          borderRadius: radius,
          shadows: shadows,
          child: child!,
        );
      },
      child: SizedBox(
        height: widget.height,
        child: TextField(
          key:
              widget.keyName == null ? null : ValueKey<String>(widget.keyName!),
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          obscureText: widget.obscure,
          autocorrect: !widget.obscure,
          enableSuggestions: !widget.obscure,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: DesktopType.field(skin.text),
          cursorColor: skin.accent,
          maxLines: multiline ? null : 1,
          minLines: multiline ? null : 1,
          expands: multiline,
          textAlignVertical: multiline ? TextAlignVertical.top : null,
          maxLength: widget.maxLength,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          // Material 自带计数器会挤进 34 高的小框；计数由 [counterBuilder]
          // 画在 label 行右侧（样例 `· {n} lines`）。
          buildCounter:
              (
                _, {
                required int currentLength,
                required bool isFocused,
                required int? maxLength,
              }) => null,
          inputFormatters: [
            ...?widget.inputFormatters,
            if (widget.maxLength != null)
              LengthLimitingTextInputFormatter(widget.maxLength),
          ],
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: focused ? fillFocused : fill,
            hintText: widget.hint,
            hintStyle: DesktopType.field(skin.text3),
            prefixIcon:
                widget.prefixIcon == null
                    ? null
                    : Icon(widget.prefixIcon, size: 15, color: skin.text3),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 30,
            ),
            suffixIcon: widget.trailing,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 30,
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: multiline ? 12 : (widget.prefixIcon == null ? 12 : 0),
              vertical: multiline ? 10 : 8,
            ),
            border: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: lineColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: lineColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: bad ? lineColor : skin.accent),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: skin.line),
            ),
          ),
        ),
      ),
    );
    return field;
  }

  /// 样例 `.field` / `.sf` 的竖排装饰：label（含必填/计数）+ 输入 + 辅助行。
  /// 三个槽都为空时保持原有单框布局，工具栏里的紧凑输入不受影响。
  Widget _decorate(DesktopSkin skin, Widget field) {
    final counter = widget.counterBuilder;
    final message = widget.error ?? widget.helper;
    final hasLabelRow = widget.label != null || counter != null;
    if (!hasLabelRow && message == null) {
      return field;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasLabelRow) ...[
          Row(
            children: [
              Expanded(
                child:
                    widget.label == null
                        ? const SizedBox.shrink()
                        : Row(
                          children: [
                            if (widget.labelIcon != null) ...[
                              Icon(
                                widget.labelIcon,
                                size: 14,
                                color: skin.text2,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                widget.label!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.fieldLabel(skin.text2),
                              ),
                            ),
                            if (widget.required) ...[
                              const SizedBox(width: 2),
                              Text(
                                '*',
                                style: DesktopType.fieldLabel(
                                  DesktopPalette.bad,
                                ),
                              ),
                            ],
                          ],
                        ),
              ),
              if (counter != null)
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder:
                      (context, value, _) => Text(
                        counter(value.text),
                        style: DesktopType.fieldHint(skin.text3),
                      ),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        field,
        if (message != null) ...[
          const SizedBox(height: 5),
          Text(
            message,
            style: DesktopType.fieldHint(
              widget.error != null ? DesktopPalette.bad : skin.text3,
            ),
          ),
        ],
      ],
    );
  }
}
