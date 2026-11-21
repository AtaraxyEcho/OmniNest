import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_select.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('下拉展开后选择新值并收起', (tester) async {
    var value = 'a';
    await tester.pumpWidget(
      wrapDesktop(
        StatefulBuilder(
          builder:
              (context, setState) => Center(
                child: SizedBox(
                  width: 240,
                  child: DesktopSelect<String>(
                    value: value,
                    options: const [
                      DesktopSelectOption(value: 'a', label: 'Alpha'),
                      DesktopSelectOption(value: 'b', label: 'Beta'),
                      DesktopSelectOption(value: 'c', label: 'Gamma'),
                    ],
                    onChanged: (next) => setState(() => value = next),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);

    await tester.tap(find.text('Beta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选项超过 12 个时出现搜索框并可过滤', (tester) async {
    var value = '0';
    await tester.pumpWidget(
      wrapDesktop(
        StatefulBuilder(
          builder:
              (context, setState) => Center(
                child: SizedBox(
                  width: 240,
                  child: DesktopSelect<String>(
                    value: value,
                    options: [
                      for (var i = 0; i < 15; i++)
                        DesktopSelectOption(value: '$i', label: 'Option $i'),
                    ],
                    onChanged: (next) => setState(() => value = next),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Option 0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Option 1'), findsWidgets);

    await tester.enterText(find.byType(TextField), '14');
    await tester.pump();
    expect(find.text('Option 14'), findsOneWidget);
    expect(find.text('Option 3'), findsNothing);

    await tester.tap(find.text('Option 14'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Option 14'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收起时方向键即可展开，End + Enter 选中末项', (tester) async {
    var value = 'a';
    await tester.pumpWidget(
      wrapDesktop(
        StatefulBuilder(
          builder:
              (context, setState) => Center(
                child: SizedBox(
                  width: 240,
                  child: DesktopSelect<String>(
                    value: value,
                    options: const [
                      DesktopSelectOption(value: 'a', label: 'Alpha'),
                      DesktopSelectOption(value: 'b', label: 'Beta'),
                      DesktopSelectOption(value: 'c', label: 'Gamma'),
                    ],
                    onChanged: (next) => setState(() => value = next),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.pump();

    // 触发器自持 FocusNode，这里借 Text 的祖先把它取出来。
    final trigger = tester.widget<Focus>(
      find.ancestor(of: find.text('Alpha'), matching: find.byType(Focus)).first,
    );
    trigger.focusNode!.requestFocus();
    await tester.pump();

    // 样例 `Select.tsx:56-62`：收起态箭头键就能展开，不必先点开。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Beta'), findsOneWidget);

    // Home / End 直接跳到首尾，再按 Enter 提交。
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(value, 'c');
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('触发器支持前导图标与错误描边', (tester) async {
    await tester.pumpWidget(
      wrapDesktop(
        Center(
          child: SizedBox(
            width: 240,
            child: DesktopSelect<String>(
              value: 'a',
              icon: DesktopIcons.search,
              invalid: true,
              options: const [DesktopSelectOption(value: 'a', label: 'Alpha')],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(DesktopIcons.search), findsOneWidget);
    final trigger = tester.widget<Container>(
      find
          .ancestor(of: find.text('Alpha'), matching: find.byType(Container))
          .first,
    );
    expect(
      (trigger.decoration! as BoxDecoration).border!.top.color,
      DesktopPalette.bad,
    );
  });

  testWidgets('选项右侧附注按 11.5 渲染在标签之后', (tester) async {
    await tester.pumpWidget(
      wrapDesktop(
        Center(
          child: SizedBox(
            width: 240,
            child: DesktopSelect<String>(
              value: 'a',
              options: const [
                DesktopSelectOption(
                  value: 'a',
                  label: 'Alpha',
                  hint: '12 files',
                ),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final hint = tester.widget<Text>(find.text('12 files'));
    expect(hint.style!.fontSize, 11.5);
    // 触发器与选项各有一份 Alpha，取选项那一份（后构建）比位置。
    expect(
      tester.getCenter(find.text('12 files')).dx,
      greaterThan(tester.getCenter(find.text('Alpha').last).dx),
    );
  });

  testWidgets('align=end 的弹层不越出右缘', (tester) async {
    await tester.pumpWidget(
      wrapDesktop(
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 4, top: 40),
            child: SizedBox(
              width: 200,
              child: DesktopSelect<String>(
                value: 'a',
                align: DesktopSelectAlign.end,
                options: const [
                  DesktopSelectOption(value: 'a', label: 'Alpha'),
                  DesktopSelectOption(value: 'b', label: 'Beta'),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final screen =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    // 样例把弹层钳进视口 8px 内，贴右缘的触发器也不会把面板顶出去。
    expect(
      tester.getRect(find.text('Beta')).right,
      lessThanOrEqualTo(screen - 8),
    );
  });

  testWidgets('展开时按 Tab 收起面板并把焦点交还出去', (tester) async {
    await tester.pumpWidget(
      wrapDesktop(
        Center(
          child: SizedBox(
            width: 240,
            child: DesktopSelect<String>(
              value: 'a',
              options: const [
                DesktopSelectOption(value: 'a', label: 'Alpha'),
                DesktopSelectOption(value: 'b', label: 'Beta'),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Beta'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('Beta'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
