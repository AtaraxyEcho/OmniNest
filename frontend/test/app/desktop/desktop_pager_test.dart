import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_pager.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('7 页以内全列，超过才折叠成省略号', (tester) async {
    Future<void> pumpPager({required int totalItems, required int page}) {
      return tester.pumpWidget(
        wrapDesktop(
          Center(
            child: SizedBox(
              width: 800,
              child: DesktopPager(
                page: page,
                pageSize: 10,
                totalItems: totalItems,
                onPageChanged: (_) {},
              ),
            ),
          ),
        ),
      );
    }

    // 7 页及以内直出，`…` 反而更难读。
    await pumpPager(totalItems: 70, page: 0);
    await tester.pump();
    expect(find.text('…'), findsNothing);
    for (final label in ['1', '2', '3', '4', '5', '6', '7']) {
      expect(find.text(label), findsOneWidget);
    }

    // 首末页与当前页 ±1 必显，中间用 `…`。
    await pumpPager(totalItems: 120, page: 0);
    await tester.pump();
    expect(find.text('…'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    await pumpPager(totalItems: 120, page: 5);
    await tester.pump();
    expect(find.text('…'), findsNWidgets(2));
    for (final label in ['1', '6', '12']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('首末页在两端禁用，点页码回到对应页', (tester) async {
    var page = 4;
    await tester.pumpWidget(
      wrapDesktop(
        StatefulBuilder(
          builder:
              (context, setState) => Center(
                child: SizedBox(
                  width: 800,
                  child: DesktopPager(
                    page: page,
                    pageSize: 10,
                    totalItems: 120,
                    onPageChanged: (next) => setState(() => page = next),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('of 120'), findsOneWidget);
    // 12 页：1 … 4 5 6 … 12，其中 5 当前选中。
    for (final label in ['1', '4', '5', '6', '12']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('…'), findsNWidgets(2));

    await tester.tap(find.text('4'));
    await tester.pump();
    expect(page, 3);

    await tester.tap(find.byTooltip('First page'));
    await tester.pump();
    expect(page, 0);

    await tester.tap(find.byTooltip('Last page'));
    await tester.pump();
    expect(page, 11);
  });

  testWidgets('末页时 Next / Last 点了也不动', (tester) async {
    final changes = <int>[];
    await tester.pumpWidget(
      wrapDesktop(
        Center(
          child: SizedBox(
            width: 800,
            child: DesktopPager(
              page: 2,
              pageSize: 10,
              totalItems: 30,
              onPageChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Next page'));
    await tester.pump();
    await tester.tap(find.byTooltip('Last page'));
    await tester.pump();

    expect(changes, isEmpty);
  });

  testWidgets('每页行数下拉只列 10/20/50 并回传', (tester) async {
    var size = 20;
    await tester.pumpWidget(
      wrapDesktop(
        StatefulBuilder(
          builder:
              (context, setState) => Center(
                child: SizedBox(
                  width: 800,
                  child: DesktopPager(
                    page: 0,
                    pageSize: size,
                    totalItems: 30,
                    onPageSizeChanged: (next) => setState(() => size = next),
                    onPageChanged: (_) {},
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.pump();

    // 样例标签就是短词 `Rows`。
    expect(find.text('Rows'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);

    await tester.tap(find.text('20'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('10'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);

    await tester.tap(find.text('50'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(size, 50);
  });
}
