import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';

/// 模态内容自己绑定的 Escape 必须先行消费：站内多处弹窗内层另有 Escape
/// 语义（取消行内编辑、退出沉浸），它们比“关闭弹窗”更具体，不能被劫持。
class _InlineEscapeIntent extends Intent {
  const _InlineEscapeIntent();
}

Widget _app({
  required bool hosted,
  required bool destructive,
  FocusNode? backgroundFocusNode,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: MobileShellScope(
          hosted: hosted,
          child: Builder(
            builder:
                (context) => TextButton(
                  focusNode: backgroundFocusNode,
                  onPressed: () {
                    if (destructive) {
                      showWorkstationDestructiveConfirm(
                        context,
                        title: 'Danger',
                        message: 'Body',
                        confirmPhrase: 'DELETE',
                      );
                      return;
                    }
                    showWorkstationConfirmDialog(
                      context,
                      title: 'Confirm',
                      message: 'Body',
                    );
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required bool hosted,
  required bool destructive,
  FocusNode? backgroundFocusNode,
}) async {
  await tester.pumpWidget(
    _app(
      hosted: hosted,
      destructive: destructive,
      backgroundFocusNode: backgroundFocusNode,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

bool _insideFrame(FocusNode? node) {
  final element = node?.context;
  if (element == null) {
    return false;
  }
  return element.findAncestorWidgetOfExactType<WorkstationDialogFrame>() !=
      null;
}

void main() {
  testWidgets('桌面弹窗 Escape 关闭可消解确认框', (tester) async {
    await _pump(tester, hosted: false, destructive: false);
    expect(find.text('Confirm'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('桌面高危确认框 Escape 不关闭，只能按按钮决定', (tester) async {
    await _pump(tester, hosted: false, destructive: true);
    expect(find.text('Danger'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Danger'), findsOneWidget);
  });

  testWidgets('托管态底部面板 Escape 关闭', (tester) async {
    await _pump(tester, hosted: true, destructive: false);
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('托管态高危面板 Escape 不关闭', (tester) async {
    await _pump(tester, hosted: true, destructive: true);
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('弹窗内容自己的 Escape 处理器优先于模态关闭', (tester) async {
    var inlineHits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showWorkstationDialog<void>(
                          context: context,
                          builder:
                              (dialogContext) => Actions(
                                actions: {
                                  _InlineEscapeIntent:
                                      CallbackAction<_InlineEscapeIntent>(
                                        onInvoke: (_) {
                                          inlineHits++;
                                          return null;
                                        },
                                      ),
                                },
                                child: Shortcuts(
                                  shortcuts: const {
                                    SingleActivator(LogicalKeyboardKey.escape):
                                        _InlineEscapeIntent(),
                                  },
                                  child: WorkstationDialogFrame(
                                    title: 'Inline',
                                    body: Focus(
                                      autofocus: true,
                                      child: const Text('body'),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () {},
                                        child: const Text('noop'),
                                      ),
                                    ],
                                  ),
                                ),
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

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(inlineHits, 1);
    expect(find.text('Inline'), findsOneWidget);
  });

  for (final hosted in [false, true]) {
    final surface = hosted ? '托管面板' : '桌面弹窗';
    testWidgets('Tab 遍历始终留在$surface内', (tester) async {
      await _pump(tester, hosted: hosted, destructive: false);
      for (var step = 1; step <= 5; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final primary = FocusManager.instance.primaryFocus;
        expect(_insideFrame(primary), isTrue, reason: '第 \$step 次 Tab 后焦点逃出模态');
        expect(
          primary?.context?.widget,
          isNot(isA<ModalBarrier>()),
          reason: '焦点落在遮罩节点上，读屏会读到不可见控件',
        );
      }
    });
  }

  testWidgets('焦点逃逸出弹窗时被陷阱拉回', (tester) async {
    final background = FocusNode();
    addTearDown(background.dispose);
    await _pump(
      tester,
      hosted: false,
      destructive: false,
      backgroundFocusNode: background,
    );
    expect(_insideFrame(FocusManager.instance.primaryFocus), isTrue);

    background.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(
      _insideFrame(FocusManager.instance.primaryFocus),
      isTrue,
      reason: '焦点被拉回弹窗内',
    );
  });

  testWidgets('弹窗语义角色随破坏性档位切换 dialog / alertDialog', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, hosted: false, destructive: false);
    expect(
      tester.getSemantics(find.byType(WorkstationDialogFrame)).role,
      SemanticsRole.dialog,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await _pump(tester, hosted: false, destructive: true);
    expect(
      tester.getSemantics(find.byType(WorkstationDialogFrame)).role,
      SemanticsRole.alertDialog,
    );
    handle.dispose();
  });
}
