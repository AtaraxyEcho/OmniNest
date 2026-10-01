import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';

void main() {
  testWidgets('嵌套弹窗期间焦点由最顶层陷阱接管，外层不抢焦点', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (homeContext) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed:
                        () => showWorkstationDialog<void>(
                          context: homeContext,
                          builder:
                              (contextA) => WorkstationDialogFrame(
                                title: 'OUTER',
                                body: Builder(
                                  builder:
                                      (bodyContext) => TextButton(
                                        onPressed:
                                            () => showWorkstationConfirmDialog(
                                              bodyContext,
                                              title: 'INNER',
                                              message: 'confirm?',
                                            ),
                                        child: const Text('open-inner'),
                                      ),
                                ),
                              ),
                        ),
                    child: const Text('open-outer'),
                  ),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('open-outer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-inner'));
    await tester.pumpAndSettle();

    // 内层确认弹窗默认聚焦取消按钮；多泵几帧，若外层陷阱仍会抢焦点，
    // 焦点将被拉回外层弹窗路由。
    await tester.pump(const Duration(milliseconds: 120));
    final innerRoute = ModalRoute.of(find.text('INNER').evaluate().single);
    expect(innerRoute?.isCurrent, isTrue);

    final primary = FocusManager.instance.primaryFocus;
    expect(primary, isNotNull);
    expect(ModalRoute.of(primary!.context!), same(innerRoute));

    // 关闭内层后，外层恢复为当前路由，其陷阱继续接管。
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('INNER'), findsNothing);
    expect(find.text('OUTER'), findsOneWidget);
    final outerRoute = ModalRoute.of(find.text('OUTER').evaluate().single);
    expect(outerRoute?.isCurrent, isTrue);
  });
}
