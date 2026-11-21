import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';

import 'desktop_test_harness.dart';

/// 焦点是否落在 [scope] 子树里（样例 `useDialogFocus` 的 Tab 陷阱）。
bool _focusInside(WidgetTester tester, Finder scope) {
  final context = tester.binding.focusManager.primaryFocus?.context;
  if (context == null) {
    return false;
  }
  final target = scope.evaluate().single;
  var inside = false;
  context.visitAncestorElements((element) {
    if (element == target) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDialogHost(
    WidgetTester tester, {
    required FocusNode pageFocus,
    required TextEditingController pageController,
    required TextEditingController dialogController,
  }) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrapDesktop(
        Builder(
          builder:
              (context) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DesktopTextField(
                      keyName: 'page-field',
                      controller: pageController,
                      focusNode: pageFocus,
                    ),
                    const SizedBox(height: 12),
                    DesktopButton(
                      label: 'Open',
                      onPressed: () {
                        // 键盘/命令面板触发弹层时焦点留在原地；这里显式
                        // 摆好同样的前提，弹层才有「上一个焦点」可归还。
                        pageFocus.requestFocus();
                        showDesktopDialog<void>(
                          context,
                          builder:
                              (_) => DesktopDialog(
                                title: 'Edit',
                                content: DesktopTextField(
                                  keyName: 'dialog-field',
                                  controller: dialogController,
                                  label: 'Title',
                                ),
                                actions: const [
                                  DesktopButton(
                                    label: 'Cancel',
                                    variant: DesktopButtonVariant.ghost,
                                  ),
                                  DesktopButton(
                                    label: 'Save',
                                    variant: DesktopButtonVariant.primary,
                                  ),
                                ],
                              ),
                        );
                      },
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  testWidgets('弹层打开聚焦首个输入框，关闭后焦点归还', (tester) async {
    final pageFocus = FocusNode();
    final pageController = TextEditingController();
    final dialogController = TextEditingController();
    addTearDown(pageFocus.dispose);
    addTearDown(pageController.dispose);
    addTearDown(dialogController.dispose);

    await pumpDialogHost(
      tester,
      pageFocus: pageFocus,
      pageController: pageController,
      dialogController: dialogController,
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final dialogField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('dialog-field')),
    );
    expect(dialogField.focusNode!.hasFocus, isTrue);
    expect(pageFocus.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Edit'), findsNothing);
    expect(pageFocus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab 在弹层内循环，不漏到背后的页面', (tester) async {
    final pageFocus = FocusNode();
    final pageController = TextEditingController();
    final dialogController = TextEditingController();
    addTearDown(pageFocus.dispose);
    addTearDown(pageController.dispose);
    addTearDown(dialogController.dispose);

    await pumpDialogHost(
      tester,
      pageFocus: pageFocus,
      pageController: pageController,
      dialogController: dialogController,
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    // 弹层里只有 1 个输入 + 2 个按钮 + 关闭钮；多按几次一定跨过首尾。
    for (var index = 0; index < 8; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    expect(_focusInside(tester, find.byType(DesktopDialog)), isTrue);
    expect(pageFocus.hasFocus, isFalse);
  });

  testWidgets('字段装饰族：label / 必填 / 计数 / 出错描边', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController(text: 'Quiet');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapDesktop(
        Center(
          child: SizedBox(
            width: 320,
            child: DesktopTextField(
              controller: controller,
              label: 'Title',
              required: true,
              error: 'A title is required',
              counterBuilder: (text) => '${text.length} chars',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Title'), findsOneWidget);
    expect(find.text('*'), findsOneWidget);
    expect(find.text('5 chars'), findsOneWidget);
    expect(find.text('A title is required'), findsOneWidget);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.decoration!.enabledBorder!.borderSide.color,
      DesktopPalette.bad,
    );
    expect(field.maxLength, isNull);

    // 计数跟随输入刷新。
    await tester.enterText(find.byType(TextField), 'Quiet hour');
    await tester.pump();
    expect(find.text('10 chars'), findsOneWidget);
  });
}
