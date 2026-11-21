import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHost(WidgetTester tester, Widget drawer) async {
    await tester.pumpWidget(
      wrapDesktop(
        Builder(
          builder:
              (context) => Center(
                child: DesktopButton(
                  label: 'Open drawer',
                  onPressed:
                      () => showDesktopDrawer<void>(
                        context,
                        builder: (_) => drawer,
                      ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Open drawer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('三段框架：头部 22/24/14、主体 18/24/24、底部 14/24/18', (tester) async {
    await pumpHost(
      tester,
      DesktopDrawerFrame(
        eyebrow: 'Book details',
        title: 'Edit metadata',
        footer: DesktopButton(label: 'Save', onPressed: () {}),
        child: const SizedBox(height: 400, child: Text('body')),
      ),
    );

    expect(find.text('BOOK DETAILS'), findsOneWidget);
    expect(find.text('Edit metadata'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);

    // 两处发丝分隔线：头/主体、主体/底。
    expect(find.byType(Divider), findsNWidgets(2));

    // 底部动作固定在滚动区之外，内容再长也够得到。
    expect(
      find.ancestor(
        of: find.text('Save'),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.text('body'),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );

    // 主体内距 18/24/24 落在滚动视图的 padding 上。
    final body = tester.widget<SingleChildScrollView>(
      find.ancestor(
        of: find.text('body'),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(body.padding, const EdgeInsets.fromLTRB(24, 18, 24, 24));
  });

  testWidgets('抽屉上再开弹窗用浅遮罩，不再叠第二层模糊', (tester) async {
    await pumpHost(
      tester,
      DesktopDrawerFrame(
        title: 'Edit metadata',
        child: Builder(
          builder:
              (context) => DesktopButton(
                label: 'Delete',
                onPressed:
                    () => showDesktopDialog<void>(
                      context,
                      builder:
                          (_) => DesktopDialog(
                            title: 'Delete file?',
                            content: const Text('This cannot be undone'),
                            actions: [DesktopButton(label: 'Cancel')],
                          ),
                    ),
              ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Delete file?'), findsOneWidget);

    // 第二层只压暗：全屏 BackdropFilter 仍只有抽屉那一层。
    expect(find.byType(BackdropFilter), findsOneWidget);
    final nested =
        tester
            .widgetList<ColoredBox>(find.byType(ColoredBox))
            .map((box) => box.color)
            .toList();
    expect(nested, contains(DesktopPalette.scrimNested));
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭抽屉先播退场再拆掉节点', (tester) async {
    await pumpHost(
      tester,
      const DesktopDrawerFrame(title: 'Edit metadata', child: Text('body')),
    );

    expect(find.text('Edit metadata'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    // 退场 300ms：中途还在，动画结束后才移除。
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Edit metadata'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Edit metadata'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
