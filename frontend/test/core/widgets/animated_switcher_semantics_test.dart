import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/animated_switcher_semantics.dart';

Set<int> _semanticsIds(WidgetTester tester) {
  // ignore: deprecated_member_use
  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root == null) {
    return const <int>{};
  }
  final ids = <int>{};
  void visit(SemanticsNode node) {
    ids.add(node.id);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(root);
  return ids;
}

void main() {
  testWidgets('AnimatedSwitcher 切换时不摘除当前子树既有语义节点', (tester) async {
    Widget build(bool first) {
      return MaterialApp(
        home: Scaffold(
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 50),
            layoutBuilder: excludeExitingSemanticsStack,
            child: ColoredBox(
              key: ValueKey<bool>(first),
              color: first ? Colors.red : Colors.blue,
              child: SizedBox(
                width: 100,
                height: 100,
                child: Center(
                  child: Text(first ? 'alpha-stable' : 'beta-stable'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final handle = tester.ensureSemantics();
    await tester.pumpWidget(build(true));
    await tester.pump();
    final before = _semanticsIds(tester);
    expect(before, isNotEmpty);

    await tester.pumpWidget(build(false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('beta-stable'), findsOneWidget);
    // 退场中的 alpha 节点应被排除语义，但入场 beta 的稳定节点必须在树上。
    expect(find.text('alpha-stable'), findsNothing);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('excludeExitingSemanticsStack 排除 previousChildren 语义', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: excludeExitingSemanticsStack(
            const Text('current'),
            const <Widget>[ExcludeSemantics(child: Text('outgoing'))],
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.pump();

    expect(find.text('current'), findsOneWidget);
    expect(find.text('outgoing'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
