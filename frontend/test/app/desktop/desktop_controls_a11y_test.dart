import 'dart:ui' show Tristate;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('分段控件的每段都带头按钮、选中与互斥组语义', (tester) async {
    final handle = tester.ensureSemantics();
    var value = 'day';
    await tester.pumpWidget(
      wrapDesktop(
        StatefulBuilder(
          builder:
              (context, setState) => Center(
                child: DesktopSeg<String>(
                  options: const ['day', 'week', 'month'],
                  value: value,
                  labelOf: (option) => option,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
        ),
      ),
    );
    await tester.pump();

    final day = tester.getSemantics(find.text('day')).getSemanticsData();
    expect(day.flagsCollection.isButton, isTrue);
    expect(day.flagsCollection.isSelected, Tristate.isTrue);
    expect(day.flagsCollection.isInMutuallyExclusiveGroup, isTrue);

    final week = tester.getSemantics(find.text('week')).getSemanticsData();
    expect(week.flagsCollection.isSelected, Tristate.isFalse);
    expect(week.flagsCollection.isInMutuallyExclusiveGroup, isTrue);

    await tester.tap(find.text('week'));
    await tester.pump();

    expect(
      tester
          .getSemantics(find.text('week'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(find.text('day'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );
    handle.dispose();
  });

  testWidgets('滑块能用方向键按 max/20 步进，并暴露增减动作', (tester) async {
    final handle = tester.ensureSemantics();
    var value = 50.0;
    await tester.pumpWidget(
      wrapDesktop(
        StatefulBuilder(
          builder:
              (context, setState) => Center(
                child: SizedBox(
                  width: 200,
                  child: DesktopSlider(
                    value: value,
                    max: 100,
                    onChanged: (next) => setState(() => value = next),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.pump();

    final semantics =
        tester.getSemantics(find.byType(DesktopSlider)).getSemanticsData();
    expect(semantics.flagsCollection.isSlider, isTrue);
    expect(semantics.value, '50');
    expect(semantics.increasedValue, '55');
    expect(semantics.decreasedValue, '45');

    // 无指针交互的裸场景里 Tab 落到唯一可聚焦节点。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(value, 55);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(value, 45);

    // 到边界后不再越界。
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }
    expect(value, 0);
    handle.dispose();
  });
}
