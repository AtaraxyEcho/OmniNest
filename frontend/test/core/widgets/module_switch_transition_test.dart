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
    final moduleElement = tester.element(find.text('module-content'));
    setState(() => transitionKey = 1);
    await tester.pump();

    final enteringFade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(ModuleSwitchTransition),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(enteringFade.opacity.value, lessThan(1));
    expect(find.text('module-content'), findsOneWidget);

    await tester.pumpAndSettle();
    // 常驻同构树：静止态保留 FadeTransition（不透明度为 1，不再推离屏层），
    // 页面树 Element 不变，切换结束不会让 StatefulNavigationShell 重挂。
    final settledFade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(ModuleSwitchTransition),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(settledFade.opacity.value, 1.0);
    expect(tester.element(find.text('module-content')), same(moduleElement));
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
    final settledFade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(ModuleSwitchTransition),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(settledFade.opacity.value, 1.0);
  });
}
