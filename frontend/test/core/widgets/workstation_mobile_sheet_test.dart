import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';

Widget _host({required bool hosted, required Widget child}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: MobileShellScope(hosted: hosted, child: child)),
    ),
  );
}

void main() {
  testWidgets('未挂壳层上下文保持桌面居中弹窗', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _host(
        hosted: false,
        child: Builder(
          builder:
              (context) => TextButton(
                onPressed: () async {
                  await showWorkstationConfirmDialog(
                    context,
                    title: 'Confirm',
                    message: 'Body',
                  );
                  opened = true;
                },
                child: const Text('open'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 自定义框架不经过 Material Dialog：以工位框架在场 + 无面板判定。
    expect(find.byType(WorkstationDialogFrame), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('workstation-sheet-handle')),
      findsNothing,
    );

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('托管态自动分流为底部玻璃面板', (tester) async {
    await tester.pumpWidget(
      _host(
        hosted: true,
        child: Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => showWorkstationConfirmDialog(
                      context,
                      title: 'Confirm',
                      message: 'Body',
                    ),
                child: const Text('open'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('workstation-sheet-handle')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Confirm'), findsOneWidget);
  });

  testWidgets('面板内确认按钮返回值语义与桌面一致', (tester) async {
    Object? result = Object();
    await tester.pumpWidget(
      _host(
        hosted: true,
        child: Builder(
          builder:
              (context) => TextButton(
                onPressed: () async {
                  result = await showWorkstationConfirmDialog(
                    context,
                    title: 'Confirm',
                    message: 'Body',
                  );
                },
                child: const Text('open'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('破坏性确认面板点遮罩不可关闭且可拖拽被禁用', (tester) async {
    await tester.pumpWidget(
      _host(
        hosted: true,
        child: Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => showWorkstationDestructiveConfirm(
                      context,
                      title: 'Danger',
                      message: 'Body',
                      confirmPhrase: 'DELETE',
                    ),
                child: const Text('open'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Danger'), findsOneWidget);
  });

  testWidgets('面板内再次打开工位弹窗时路由栈叠加二级面板', (tester) async {
    await tester.pumpWidget(
      _host(
        hosted: true,
        child: Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => showWorkstationDialog<void>(
                      context: context,
                      builder:
                          (dialogContext) => WorkstationDialogFrame(
                            title: 'Outer',
                            body: TextButton(
                              onPressed:
                                  () => showWorkstationConfirmDialog(
                                    dialogContext,
                                    title: 'Inner',
                                    message: 'Body',
                                  ),
                              child: const Text('inner-open'),
                            ),
                          ),
                    ),
                child: const Text('open'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.text('inner-open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNWidgets(2));
    expect(find.text('Inner'), findsOneWidget);
  });
}
