import 'package:flutter/material.dart';

import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';

/// 模块内的分区切换条（样例 `.page-head` 里的 `.seg`）。
///
/// 桌面统一壳的侧栏负责「空间之间」，模块内部「分区之间」按样例收敛成
/// 页内分段控件，而不是再立一条侧栏——两条竖轨并排正是「每个模块都是
/// 一个子系统」的观感来源。
class DesktopSectionBar<T> extends StatelessWidget {
  const DesktopSectionBar({
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.title,
    this.eyebrow,
    this.trailing = const <Widget>[],
    super.key,
  });

  final List<T> options;
  final T value;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final String? title;
  final String? eyebrow;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20,
        runSpacing: 12,
        children: [
          if (title != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null) DesktopEyebrow(eyebrow!),
                Text(title!, style: DesktopType.display(skin.text)),
              ],
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DesktopSeg<T>(
              options: options,
              value: value,
              labelOf: labelOf,
              onChanged: onChanged,
            ),
          ),
          if (trailing.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: trailing),
        ],
      ),
    );
  }
}
