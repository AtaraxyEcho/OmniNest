import 'dart:ui' show Tristate;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_press.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DesktopSkin skinAt(WidgetTester tester, Finder finder) =>
      DesktopSkin.of(tester.element(finder));

  testWidgets('筛选胶囊选中是 18% 淡底 + 45% 描边 + 600 字重', (tester) async {
    await tester.pumpWidget(
      wrapDesktop(
        Center(
          child: DesktopChipButton(
            label: 'Documents',
            selected: true,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final skin = skinAt(tester, find.byType(DesktopChipButton));
    final box = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(DesktopChipButton),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, skin.accentWash(0.18));
    expect((decoration.border! as Border).top.color, skin.accentWash(0.45));

    final text = tester.widget<Text>(find.text('Documents'));
    expect(text.style!.fontWeight, FontWeight.w600);
    // 淡底配正文色，不再反白。
    expect(text.style!.color, skin.text);
  });

  testWidgets('按钮按下缩到 0.96，图标按钮仍是 0.88', (tester) async {
    await tester.pumpWidget(
      wrapDesktop(
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DesktopButton(label: 'Save', onPressed: () {}),
              DesktopIconButton(
                icon: Icons.close,
                onPressed: () {},
                tooltip: 'Close',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final scales =
        tester
            .widgetList<DesktopPressScale>(find.byType(DesktopPressScale))
            .map((widget) => widget.scale)
            .toList();
    expect(scales, containsAll(<double>[0.96, 0.88]));
  });

  testWidgets('分段控件的指示块带 1/6 投影', (tester) async {
    await tester.pumpWidget(
      wrapDesktop(
        Center(
          child: DesktopSeg<String>(
            options: const ['day', 'week'],
            value: 'day',
            labelOf: (option) => option,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final plates =
        tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(DesktopSeg<String>),
                matching: find.byType(DecoratedBox),
              ),
            )
            .toList();
    final indicator = plates
        .map((box) => box.decoration as BoxDecoration)
        .firstWhere((decoration) => decoration.boxShadow != null);
    expect(indicator.boxShadow, isNotEmpty);
    expect(indicator.boxShadow!.first.blurRadius, 6);
  });

  testWidgets('开关是 switch 语义：有 toggled、没有 button 角色', (tester) async {
    final handle = tester.ensureSemantics();
    var value = true;
    await tester.pumpWidget(
      wrapDesktop(
        StatefulBuilder(
          builder:
              (context, setState) => Center(
                child: DesktopToggle(
                  value: value,
                  label: 'Two factor',
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
        ),
      ),
    );
    await tester.pump();

    final data =
        tester.getSemantics(find.byType(DesktopToggle)).getSemanticsData();
    expect(data.flagsCollection.isToggled, Tristate.isTrue);
    expect(data.flagsCollection.isButton, isFalse);
    handle.dispose();
  });

  testWidgets('输入框默认 40 高，页面表面档是 36 + 页面底色 + 9 圆角', (tester) async {
    await tester.pumpWidget(
      wrapDesktop(
        Center(
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DesktopTextField(
                  controller: TextEditingController(),
                  keyName: 'panel-field',
                ),
                DesktopTextField(
                  controller: TextEditingController(),
                  keyName: 'page-field',
                  height: 36,
                  tone: DesktopFieldTone.page,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final skin = skinAt(
      tester,
      find.byKey(const ValueKey<String>('panel-field')),
    );
    // v16 起底色 / 描边 / 光环统一画在外层 AnimatedContainer，TextField 透明铺满，
    // 因此高度与装饰都要按外层容器断言（键仍挂在 TextField 上用于定位与取控件）。
    Finder boxOf(String key) =>
        find
            .ancestor(
              of: find.byKey(ValueKey<String>(key)),
              matching: find.byType(AnimatedContainer),
            )
            .first;
    expect(tester.getSize(boxOf('panel-field')).height, 40);
    expect(tester.getSize(boxOf('page-field')).height, 36);

    BoxDecoration decorationOf(String key) =>
        tester.widget<AnimatedContainer>(boxOf(key)).decoration!
            as BoxDecoration;
    expect(decorationOf('panel-field').color, skin.raise);
    expect(decorationOf('page-field').color, skin.bg);
    expect(
      decorationOf('page-field').borderRadius,
      BorderRadius.circular(DesktopMetrics.radiusIconButton),
    );
  });

  testWidgets('键盘聚焦画出 2px 焦点环，Enter 也能触发', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      wrapDesktop(
        Center(child: DesktopButton(label: 'Save', onPressed: () => pressed++)),
      ),
    );
    await tester.pump();

    // 先把焦点走进去（按键触发的 traditional 高亮模式才会画环）。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final ring = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((paint) => paint.foregroundPainter != null);
    expect(ring, isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('文件页面包屑标题是 26 衬线', (tester) async {
    await tester.pumpWidget(
      wrapDesktop(
        Center(
          child: Text(
            'Files',
            style: DesktopType.crumbTitle(const Color(0xFF000000)),
          ),
        ),
      ),
    );
    await tester.pump();

    final style = tester.widget<Text>(find.text('Files')).style!;
    expect(style.fontFamily, DesktopType.serifFamily);
    expect(style.fontSize, DesktopType.sizeCrumb);
  });
}
