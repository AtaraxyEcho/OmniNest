// 工位控件的键盘可达性回归：PRODUCT.md 要求桌面端有可预期的 Tab 顺序与
// 可见 focus ring，而这些控件全是自绘的 MouseRegion + GestureDetector，
// 不包 FocusableActionDetector 就整条落在 Tab 链之外。
import 'dart:ui' show PointerDeviceKind;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_focus_target.dart';

void main() {
  testWidgets('按下时以 2% 缩放给出点击确认，松开后回弹', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: WorkstationFocusTarget(
              enabled: true,
              onActivate: () {},
              builder:
                  (context, focused) => const SizedBox(
                    width: 48,
                    height: 48,
                    child: ColoredBox(color: Colors.black),
                  ),
            ),
          ),
        ),
      ),
    );

    AnimatedScale scaleWidget() => tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(WorkstationFocusTarget),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(scaleWidget().scale, 1.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(WorkstationFocusTarget)),
    );
    await tester.pump();
    expect(scaleWidget().scale, 0.98);

    await gesture.up();
    await tester.pump();
    expect(scaleWidget().scale, 1.0);
  });

  testWidgets('六个工位控件按声明顺序进入 Tab 链，Enter 各自触发', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Focus(
              autofocus: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WorkstationIconButton(
                    tooltip: '刷新',
                    icon: Icons.refresh,
                    onPressed: () => log.add('icon-button'),
                  ),
                  WorkstationSegmented<String>(
                    segments: const [
                      WorkstationSegment(
                        value: 'a',
                        tooltip: '视图 A',
                        icon: Icons.grid_view,
                      ),
                      WorkstationSegment(
                        value: 'b',
                        tooltip: '视图 B',
                        icon: Icons.view_agenda,
                      ),
                    ],
                    selected: 'a',
                    onSelected: (value) => log.add('segment:$value'),
                  ),
                  WorkstationActionButton(
                    label: '上传',
                    onPressed: () => log.add('action-button'),
                  ),
                  WorkstationCheckMark(
                    value: false,
                    onChanged: (_) => log.add('check'),
                  ),
                  WorkstationToggle(
                    value: false,
                    onChanged: (_) => log.add('toggle'),
                  ),
                  WorkstationSwitch(
                    value: false,
                    onChanged: (_) => log.add('switch'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 7 个可聚焦站点：图标按钮、两个分段、动作按钮、复选、开关、切换行。
    for (var step = 0; step < 7; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.hasFocus,
        isTrue,
        reason: '第 $step 次 Tab 后焦点应落在下一个工位控件上',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }

    expect(log, [
      'icon-button',
      // 已选中的分段仍会回调同一值：语义是"确认当前段"，不是跳过。
      'segment:a',
      'segment:b',
      'action-button',
      'check',
      'toggle',
      'switch',
    ]);
  });

  testWidgets('禁用控件不进 Tab 链，Space 与 Enter 一样触发', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Focus(
              autofocus: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const WorkstationIconButton(
                    tooltip: '禁用按钮',
                    icon: Icons.close,
                    onPressed: null,
                  ),
                  WorkstationCheckMark(
                    value: false,
                    onChanged: (_) => log.add('check'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(log, ['check']);
  });

  /// 按钮的描边容器：三种状态只换颜色，不换几何尺寸。
  Widget hostButton(ValueKey<String> key) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Focus(
          autofocus: true,
          child: WorkstationIconButton(
            key: key,
            tooltip: '刷新',
            icon: Icons.refresh,
            onPressed: () {},
          ),
        ),
      ),
    ),
  );

  BoxDecoration outlineOf(WidgetTester tester, ValueKey<String> key) {
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(AnimatedContainer),
        matchRoot: true,
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('静止是 hairline，聚焦升为主色环', (tester) async {
    const key = ValueKey('kbd-icon-button');
    await tester.pumpWidget(hostButton(key));

    final scheme = Theme.of(tester.element(find.byKey(key))).colorScheme;
    // 静止态是 hairline，避免呈现「伪选中态」。
    expect(outlineOf(tester, key).border!.top.color, scheme.outlineVariant);

    // Tab 走到控件本身（外层 Focus 只是把焦点带进子树）。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    // 焦点环用主色：深色主题的 onSurface 近白，拿它当焦点描边会在点击后
    // 被读成一圈白框，所以焦点不与悬停同档。
    expect(outlineOf(tester, key).border!.top.color, scheme.primary);
  });

  testWidgets('悬停升到中性描边，不触发主色焦点环', (tester) async {
    const key = ValueKey('kbd-icon-button');
    await tester.pumpWidget(hostButton(key));

    final scheme = Theme.of(tester.element(find.byKey(key))).colorScheme;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(key)));
    await tester.pumpAndSettle();

    expect(outlineOf(tester, key).border!.top.color, scheme.outline);

    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(outlineOf(tester, key).border!.top.color, scheme.outlineVariant);
  });
}
