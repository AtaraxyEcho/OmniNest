import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/router.dart';

void main() {
  testWidgets('快速替换路由页面时不保留自定义动画监听器', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final pages = ValueNotifier<List<Page<void>>>([
      buildAppRoutePage(
        key: const ValueKey<String>('page-a'),
        child: const SizedBox(key: ValueKey<String>('content-a')),
      ),
    ]);
    addTearDown(pages.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<List<Page<void>>>(
          valueListenable: pages,
          builder:
              (context, value, child) => Navigator(
                key: navigatorKey,
                pages: value,
                onDidRemovePage: (page) {},
              ),
        ),
      ),
    );

    pages.value = [
      buildAppRoutePage(
        key: const ValueKey<String>('page-b'),
        child: const SizedBox(key: ValueKey<String>('content-b')),
      ),
    ];
    await tester.pump();
    pages.value = [
      buildAppRoutePage(
        key: const ValueKey<String>('page-c'),
        child: const SizedBox(key: ValueKey<String>('content-c')),
      ),
    ];
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('content-c')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
