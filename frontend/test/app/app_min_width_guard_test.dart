import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/app_min_width_guard.dart';

/// 桌面形态最小内容宽护栏测试：
/// 桌面形态低于 1024 固定宽度横向滚动并改写 MediaQuery 宽度；
/// 移动形态与 ≥1024 直通。
void main() {
  Widget host({required bool mobileForm, required Size viewport}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: viewport),
        child: DesktopFormMinWidth(
          mobileForm: mobileForm,
          child: Builder(
            builder:
                (context) => Text(
                  MediaQuery.sizeOf(context).width.toStringAsFixed(0),
                  key: const Key('reported-width'),
                ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpAt(
    WidgetTester tester,
    Size viewport, {
    required bool mobileForm,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(mobileForm: mobileForm, viewport: viewport));
    await tester.pump();
  }

  testWidgets('桌面形态低于 1024：横向滚动 + 内容按 1024 宽感知', (tester) async {
    await pumpAt(tester, const Size(700, 900), mobileForm: false);

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.scrollDirection, Axis.horizontal);
    expect(
      find.text('1024', findRichText: false),
      findsOneWidget,
      reason: '子树 MediaQuery 宽度被改写为护栏宽度',
    );
  });

  testWidgets('移动形态直通，不改写宽度', (tester) async {
    await pumpAt(tester, const Size(700, 900), mobileForm: true);

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('700', findRichText: false), findsOneWidget);
  });

  testWidgets('桌面形态不低于 1024 直通', (tester) async {
    await pumpAt(tester, const Size(1280, 900), mobileForm: false);

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('1280', findRichText: false), findsOneWidget);
  });
}
