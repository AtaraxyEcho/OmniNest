import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/app_min_width_guard.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// 桌面形态最小内容宽护栏测试：
/// 桌面形态低于 1024 固定宽度横向滚动并改写 MediaQuery 宽度；
/// 移动形态与 ≥1024 直通。
void main() {
  Widget host({
    required bool mobileForm,
    required Size viewport,
    bool hoverCapable = true,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: viewport),
        child: DesktopFormMinWidth(
          mobileForm: mobileForm,
          hoverCapable: hoverCapable,
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
    bool hoverCapable = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        mobileForm: mobileForm,
        viewport: viewport,
        hoverCapable: hoverCapable,
      ),
    );
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

  testWidgets('无 hover 指针的窄窗直通，交给模块窄屏分支', (tester) async {
    await pumpAt(
      tester,
      const Size(700, 900),
      mobileForm: false,
      hoverCapable: false,
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(
      find.text('700', findRichText: false),
      findsOneWidget,
      reason: '触屏笔电/平板桌面模式不应被撑到 1024 再横向滚动',
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

  test('护栏宽度与桌面侧栏画布阈值同源', () {
    expect(
      DesktopFormMinWidth.minWidth,
      ResponsiveBreakpoints.workbenchRail,
      reason: '两处各写一份 1024 会随时间漂移成两种判定',
    );
  });
}
