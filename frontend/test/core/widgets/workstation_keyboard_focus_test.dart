// 工位控件的键盘可达性回归：PRODUCT.md 要求桌面端有可预期的 Tab 顺序与
// 可见 focus ring，而这些控件全是自绘的 MouseRegion + GestureDetector，
// 不包 FocusableActionDetector 就整条落在 Tab 链之外。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';

void main() {
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

  testWidgets('聚焦把边框抬到与悬停同一档，形成可见 focus ring', (tester) async {
    const key = ValueKey('kbd-icon-button');
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );

    BoxDecoration outlineOf() {
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(AnimatedContainer),
          matchRoot: true,
        ),
      );
      return container.decoration! as BoxDecoration;
    }

    final scheme = Theme.of(tester.element(find.byKey(key))).colorScheme;
    expect(outlineOf().border!.top.color, scheme.outline);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    // 焦点高亮与悬停共用 onSurface：不改变几何尺寸，只抬边框，
    // 与 workstationInputDecoration 的聚焦口径一致。
    expect(outlineOf().border!.top.color, scheme.onSurface);
  });
}
