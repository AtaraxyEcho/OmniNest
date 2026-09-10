import 'package:flutter/material.dart';
import 'package:omninest/app/theme/control_tokens.dart';

/// 全局统一下拉选项描述。
class AppDropdownItem<T> {
  const AppDropdownItem({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;

  /// 禁用项在菜单中置灰且不可选择。
  final bool enabled;
}

/// 全局统一下拉选择：闭合态与 [TextField] 同风格的描边填充式
///（静态 outlineVariant 描边、hover 加深、聚焦主色描边 + 旋转箭头），
/// 展开菜单基于 Material 3 的 [MenuAnchor]——锚点定位、自动上下翻转、
/// 外部点击关闭与键盘导航均由框架保证；视觉上为圆角投影面板、选项
/// hover 高亮、选中项主色加粗并打勾。全局所有表单型下拉统一使用本控件。
///
/// 筛选栏等与按钮并排的场景应传 [dense] 为 true：不使用浮动标签，
/// 字段高度与按钮对齐，避免下拉比相邻按钮更高。
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.width,
    this.suffixText,
    this.helperText,
    this.dense = false,
    super.key,
  });

  final T value;
  final List<AppDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;

  /// 浮动标签；为空时不显示。
  ///
  /// [dense] 为 true 时作为字段内前缀文案，不抬升字段高度。
  final String? label;

  /// 固定宽度；为空时由父级约束决定。
  final double? width;
  final String? suffixText;

  /// 字段下方的辅助说明。
  final String? helperText;

  /// 紧凑模式：高度与按钮对齐，[label] 以内嵌前缀展示。
  final bool dense;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final MenuController _menu = MenuController();
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  int _indexOfValue() {
    final index = widget.items.indexWhere((item) => item.value == widget.value);
    return index < 0 ? 0 : index;
  }

  String get _currentLabel {
    final index = _indexOfValue();
    return index >= 0 && index < widget.items.length
        ? widget.items[index].label
        : '';
  }

  void _select(int index) {
    final item = widget.items[index];
    _menu.close();
    if (item.value != widget.value) {
      widget.onChanged?.call(item.value);
    }
  }

  EdgeInsetsGeometry get _contentPadding {
    if (widget.dense) {
      return EdgeInsets.symmetric(
        horizontal: AppControlTokens.denseFieldHorizontalPadding,
        vertical: AppControlTokens.denseFieldVerticalPadding,
      );
    }
    return Theme.of(context).inputDecorationTheme.contentPadding ??
        EdgeInsets.symmetric(
          horizontal: AppControlTokens.fieldHorizontalPadding,
          vertical: AppControlTokens.fieldVerticalPadding,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dense = widget.dense;
    final labelStyle = textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final valueStyle = textTheme.bodyMedium?.copyWith(color: colors.onSurface);

    Widget field = Focus(
      focusNode: _focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      child: MenuAnchor(
        controller: _menu,
        useRootOverlay: true,
        alignmentOffset: const Offset(0, 6),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppControlTokens.menuRadius),
              side: BorderSide(color: colors.outlineVariant),
            ),
          ),
          elevation: const WidgetStatePropertyAll(8),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(120, 0)),
          maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 320)),
        ),
        builder: (context, controller, child) {
          final isOpen = controller.isOpen;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: (_) {
              if (!_hovered) {
                setState(() => _hovered = true);
              }
            },
            onExit: (_) {
              if (_hovered) {
                setState(() => _hovered = false);
              }
            },
            child: GestureDetector(
              onTap: () => isOpen ? controller.close() : controller.open(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: AppControlTokens.fieldHeight,
                ),
                child: InputDecorator(
                  isFocused: _focused || isOpen,
                  isEmpty: false,
                  expands: false,
                  decoration: InputDecoration(
                    labelText: dense ? null : widget.label,
                    floatingLabelBehavior:
                        dense ? FloatingLabelBehavior.never : null,
                    helperText: widget.helperText,
                    isDense: true,
                    suffixText:
                        widget.suffixText == null || widget.suffixText!.isEmpty
                            ? null
                            : widget.suffixText,
                    filled: true,
                    fillColor: colors.surfaceContainerLowest,
                    contentPadding: _contentPadding,
                    // 闭合态与主题输入框同风格描边：hover 加深，聚焦/展开
                    // 用主色，保证与相邻 TextField 的视觉重量一致。
                    border: _fieldBorder(colors.outlineVariant),
                    enabledBorder: _fieldBorder(
                      _focused || isOpen
                          ? colors.primary
                          : _hovered
                          ? colors.onSurfaceVariant
                          : colors.outlineVariant,
                    ),
                    focusedBorder: _fieldBorder(colors.primary, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      if (dense && widget.label != null) ...[
                        Flexible(
                          child: Text(
                            widget.label!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle,
                          ),
                        ),
                        Text(' · ', style: labelStyle),
                      ],
                      Expanded(
                        child: Text(
                          _currentLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: valueStyle,
                        ),
                      ),
                      AnimatedRotation(
                        turns: isOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        menuChildren: [
          for (var i = 0; i < widget.items.length; i++)
            MenuItemButton(
              onPressed: widget.items[i].enabled ? () => _select(i) : null,
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12),
                ),
                minimumSize: WidgetStatePropertyAll(
                  Size.fromHeight(AppControlTokens.menuItemHeight),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppControlTokens.controlRadius,
                    ),
                  ),
                ),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      states.contains(WidgetState.hovered)
                          ? colors.onSurface.withValues(alpha: 0.06)
                          : Colors.transparent,
                ),
                foregroundColor: WidgetStatePropertyAll(colors.onSurface),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.items[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            widget.items[i].value == widget.value
                                ? colors.primary
                                : colors.onSurface,
                        fontWeight:
                            widget.items[i].value == widget.value
                                ? FontWeight.w600
                                : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (widget.items[i].value == widget.value)
                    Icon(Icons.check_rounded, size: 16, color: colors.primary),
                ],
              ),
            ),
        ],
      ),
    );
    if (widget.width != null) {
      field = SizedBox(width: widget.width, child: field);
    }
    return field;
  }

  OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppControlTokens.controlRadius),
        borderSide: BorderSide(color: color, width: width),
      );
}
