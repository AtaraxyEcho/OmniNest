import 'package:flutter/material.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';

/// 设置页里的等分选项组，对应样例 `.appearance-options`。
///
/// 与 [MobileSegmentedControl]（样例 `.segmented`）是两个组件，不是同一件的
/// 两种尺寸：分段导航是 `width: max-content` 的贴合胶囊，段宽由文字决定；
/// 选项组是 `repeat(3, 1fr)` 的等分网格，末行不满也按三列留空。
/// 把它们混用会让设置页的三行控件宽度互相对不齐。
class MobileAppearanceOptions<T> extends StatelessWidget {
  const MobileAppearanceOptions({
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
    this.semanticLabel,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  /// 整组的读屏标签，对应样例 `radiogroup` 的 `aria-label`。
  final String? semanticLabel;

  /// 样例 `grid-template-columns: repeat(3, 1fr)`。
  static const int _columns = 3;
  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < values.length; start += _columns) {
      final end =
          start + _columns > values.length ? values.length : start + _columns;
      rows.add(
        Row(
          children: [
            for (var column = 0; column < _columns; column++) ...[
              if (column > 0) const SizedBox(width: _gap),
              Expanded(
                child:
                    start + column < end
                        ? _AppearanceOption(
                          label: labelBuilder(values[start + column]),
                          selected: values[start + column] == selected,
                          onTap: () => onSelected(values[start + column]),
                        )
                        : const SizedBox(height: 36),
              ),
            ],
          ],
        ),
      );
      if (start + _columns < values.length) {
        rows.add(const SizedBox(height: _gap));
      }
    }

    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.env.appearanceOptionBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.env.appearanceOptionBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_gap),
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ),
    );
  }
}

class _AppearanceOption extends StatelessWidget {
  const _AppearanceOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // 样例这一组是 `role="radio"` + `aria-checked`，不是 tab 的选中态。
      // 之前 selected 与 checked 同时置位，读屏会把"已选择"和"已勾选"播两遍；
      // Flutter 里互斥单选对应的是 checked + inMutuallyExclusiveGroup。
      checked: selected,
      inMutuallyExclusiveGroup: true,
      // 不另写 label：子级 Text 已经提供名称，这里再写一次会让读屏把标签播两遍
      // （合并后的节点 label 变成 "b\nb"）。
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: MobileLayoutTokens.stateDuration,
            curve: MobileLayoutTokens.motionCurve,
            alignment: Alignment.center,
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: selected ? context.env.actionFill : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color:
                    selected
                        ? context.env.actionFillInk
                        : context.env.appearanceOptionInk,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
