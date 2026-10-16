import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';

Future<void> _open(
  WidgetTester tester, {
  required bool dismissible,
  String label = 'PANEL',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showWorkstationGeneralDialog<void>(
                        context: context,
                        dismissible: dismissible,
                        barrierLabel: '浮层',
                        pageBuilder:
                            (
                              BuildContext dialogContext,
                              Animation<double> animation,
                              Animation<double> secondaryAnimation,
                            ) => Align(
                              child: Focus(autofocus: true, child: Text(label)),
                            ),
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('自绘浮层拿到 dialog role', (tester) async {
    await _open(tester, dismissible: true);
    final wrappers = tester.widgetList<Semantics>(
      find.ancestor(of: find.text('PANEL'), matching: find.byType(Semantics)),
    );
    expect(
      wrappers.map((widget) => widget.properties.role),
      contains(SemanticsRole.dialog),
      reason: '面板不经过 WorkstationDialogFrame，role 由公共入口补齐',
    );
  });

  testWidgets('模糊遮罩铺满视口：Positioned 必须是 Stack 的直接子级', (tester) async {
    await _open(tester, dismissible: true);
    // 一旦把 scrim 重新包进 IgnorePointer/FadeTransition，Positioned 的父级
    // 数据会落到 RenderOpacity 上，debug 抛断言、release 则退化成 0 尺寸。
    expect(
      tester.getSize(
        find.descendant(
          of: find.byType(WorkstationBlurScrim),
          matching: find.byType(ColoredBox),
        ),
      ),
      tester.view.physicalSize / tester.view.devicePixelRatio,
      reason: '遮罩应覆盖整个视口',
    );
  });

  testWidgets('浮层 Escape 关闭与弹窗同一通道', (tester) async {
    await _open(tester, dismissible: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('PANEL'), findsNothing);
  });

  testWidgets('dismissible:false 的浮层 Escape 不关闭', (tester) async {
    await _open(tester, dismissible: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('PANEL'), findsOneWidget);
  });
}
