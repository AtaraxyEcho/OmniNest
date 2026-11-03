import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 工位控件的键盘可达与语义单一入口闸门。
///
/// 工位控件是自绘的 `MouseRegion + GestureDetector`，不包焦点外壳就会被
/// Tab 顺序整个跳过（PRODUCT.md：桌面端要有可预期的键盘导航与可见 focus ring）。
/// 现在统一由 `WorkstationFocusTarget` 承担外壳：一个外壳一个
/// `FocusableActionDetector` + 一份 `Semantics`；控件内部的 GestureDetector
/// 必须 `excludeFromSemantics`，否则读屏会听到两个可点节点。
///
/// 判定按计数配对：新增一个裸点击站点而不配外壳、或在控件文件里另起焦点
/// 探测器与语义节点，计数立刻错位。
void main() {
  const controls = 'lib/core/widgets/workstation_controls.dart';
  const wrapper = 'lib/core/widgets/workstation_focus_target.dart';

  int occurrences(String path, String needle) =>
      File(path).readAsStringSync().split(needle).length - 1;

  test('焦点外壳与语义节点各只有一处入口', () {
    expect(
      occurrences(wrapper, 'FocusableActionDetector('),
      1,
      reason: '$wrapper 只允许外壳内部创建一个焦点探测器',
    );
    expect(occurrences(wrapper, 'Semantics('), 1, reason: '语义节点由外壳统一声明');
    expect(
      occurrences(controls, 'FocusableActionDetector('),
      0,
      reason: '控件文件不得再自建焦点探测器',
    );
    expect(
      occurrences(controls, 'Semantics('),
      0,
      reason: '控件文件不得再各写一份 Semantics',
    );
  });

  test('工位控件的每个点击站点都必须排除自身语义', () {
    final tapSites = occurrences(controls, 'GestureDetector(');
    final excluded = occurrences(controls, 'excludeFromSemantics: true');

    expect(
      excluded,
      tapSites,
      reason: '有 $tapSites 个点击站点，但只有 $excluded 个排除了自身语义',
    );
    expect(
      tapSites,
      greaterThanOrEqualTo(6),
      reason: '六个工位控件都应保留点击站点，数量骤降说明外壳被绕过',
    );
  });

  test('工位控件的动画时长必须经 MotionToken 归零', () {
    expect(
      occurrences(controls, 'duration: const Duration('),
      0,
      reason: '工位控件的状态过渡必须写 MotionToken.reduced(context, ...)',
    );
  });
}
