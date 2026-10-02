import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/infinite_scroll.dart';

void main() {
  group('InfiniteScrollTrigger', () {
    Widget host({
      bool enabled = true,
      required VoidCallback onLoadMore,
      DateTime Function()? now,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: InfiniteScrollTrigger(
            enabled: enabled,
            onLoadMore: onLoadMore,
            now: now ?? DateTime.now,
            child: ListView.builder(
              itemCount: 200,
              itemBuilder:
                  (context, index) =>
                      SizedBox(height: 100, child: Text('item-$index')),
            ),
          ),
        ),
      );
    }

    testWidgets('滚动到底部附近触发加载回调', (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(onLoadMore: () => calls++));

      await tester.dragUntilVisible(
        find.text('item-195'),
        find.byType(ListView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(calls, greaterThan(0), reason: '接近底部应触发续页回调');
    });

    testWidgets('enabled=false 时滚动不触发', (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(enabled: false, onLoadMore: () => calls++));

      await tester.dragUntilVisible(
        find.text('item-195'),
        find.byType(ListView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(calls, 0, reason: '门闩关闭时不得触发');
    });

    testWidgets('触发后有 200ms 节流不连发', (tester) async {
      var calls = 0;
      // 注入手动步进时钟：节流判断不受真实墙钟抖动影响。
      var fakeNow = DateTime.fromMillisecondsSinceEpoch(60_000_000);
      DateTime stepClock() => fakeNow;
      await tester.pumpWidget(host(onLoadMore: () => calls++, now: stepClock));

      await tester.dragUntilVisible(
        find.text('item-195'),
        find.byType(ListView),
        const Offset(0, -400),
      );
      await tester.pump();
      final afterFirstDrag = calls;
      expect(afterFirstDrag, greaterThan(0));

      // 立即小幅回滚再前进：节流窗口内的重复触发应被吞掉。
      fakeNow = fakeNow.add(const Duration(milliseconds: 30));
      await tester.timedDrag(
        find.byType(ListView),
        const Offset(0, 50),
        const Duration(milliseconds: 100),
      );
      fakeNow = fakeNow.add(const Duration(milliseconds: 30));
      await tester.timedDrag(
        find.byType(ListView),
        const Offset(0, -50),
        const Duration(milliseconds: 50),
      );
      await tester.pump();
      expect(calls, afterFirstDrag, reason: '节流窗口内不重复触发');
    });
  });
}
