import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/files/presentation/widgets/hover_horizontal_scroll.dart';

/// 悬停横滚容器：悬停时纵向滚轮驱动横向滚动，未悬停不拦截。
void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    Size surface = const Size(400, 100),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 40,
              child: HoverHorizontalScroll(
                child: Row(
                  children: [
                    for (var i = 0; i < 10; i++)
                      SizedBox(
                        width: 60,
                        child: Center(child: Text('chip-$i')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double scrollOffset(WidgetTester tester) {
    final state = tester.state(
      find.descendant(
        of: find.byType(HoverHorizontalScroll),
        matching: find.byType(Scrollable),
      ),
    );
    return (state as ScrollableState).position.pixels;
  }

  testWidgets('悬停区域时纵向滚轮驱动横向滚动', (tester) async {
    await pumpHost(tester);
    expect(scrollOffset(tester), 0, reason: '初始未滚动');

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(HoverHorizontalScroll)));
    await tester.pumpAndSettle();

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(HoverHorizontalScroll)),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();
    expect(scrollOffset(tester), greaterThan(0), reason: '滚轮横向推进');

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(HoverHorizontalScroll)),
        scrollDelta: const Offset(0, -40),
      ),
    );
    await tester.pumpAndSettle();
    expect(scrollOffset(tester), lessThan(120), reason: '反向滚轮回退');
  });

  testWidgets('未悬停时滚轮不驱动横向滚动', (tester) async {
    await pumpHost(tester);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(5, 5),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();
    expect(scrollOffset(tester), 0);
  });
}
