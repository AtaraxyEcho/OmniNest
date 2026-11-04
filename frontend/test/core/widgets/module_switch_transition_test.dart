import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/module_switch_transition.dart';

void main() {
  testWidgets('模块切换只对现有页面树执行进入动画', (tester) async {
    var transitionKey = 0;
    late StateSetter setState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) {
            setState = update;
            return ModuleSwitchTransition(
              transitionKey: transitionKey,
              child: const Text('module-content'),
            );
          },
        ),
      ),
    );

    expect(find.text('module-content'), findsOneWidget);
    setState(() => transitionKey = 1);
    await tester.pump();

    final enteringOpacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(enteringOpacity.opacity, lessThan(1));
    expect(find.text('module-content'), findsOneWidget);

    await tester.pumpAndSettle();
    // 静止态直接返回子树，不再常驻 Opacity + Transform 合成层。
    expect(find.byType(Opacity), findsNothing);
    expect(find.text('module-content'), findsOneWidget);
  });

  testWidgets('关闭动画时模块内容直接显示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: ModuleSwitchTransition(
            transitionKey: 0,
            child: Text('static-content'),
          ),
        ),
      ),
    );

    expect(find.text('static-content'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
  });
}
