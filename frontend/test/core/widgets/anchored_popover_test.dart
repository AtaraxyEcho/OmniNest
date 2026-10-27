import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/anchored_popover.dart';

void main() {
  testWidgets('窗口尺寸变化后锚点浮层自动收起', (tester) async {
    final popover = AnchoredPopover();
    addTearDown(() => popover.close());
    final anchorKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder:
                  (context) => ElevatedButton(
                    key: anchorKey,
                    onPressed:
                        () => popover.open(
                          anchorKey.currentContext!,
                          (_) => const SizedBox(
                            width: 160,
                            height: 120,
                            child: Text('popover-panel'),
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
    expect(find.text('popover-panel'), findsOneWidget);
    expect(popover.isOpen, isTrue);

    // 模拟窗口缩放：绑定发出 metrics 变化后浮层应自行收起。
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    expect(find.text('popover-panel'), findsNothing);
    expect(popover.isOpen, isFalse);
  });
}
