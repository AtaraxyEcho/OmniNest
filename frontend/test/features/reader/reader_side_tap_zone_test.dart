import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_side_tap_zone.dart';

/// 摘要：侧区只能自己吃掉这一次点击。
///
/// 侧区原先用 Listener 观察指针（不进手势竞技场），正文层的 onTap 在同一次
/// 点击里照样触发——移动端点左右两侧就是"滚视口 + 弹 chrome"两件事。
void main() {
  Future<void> host(
    WidgetTester tester, {
    required VoidCallback onZoneTap,
    required VoidCallback onContentTap,
    ScrollController? scrollController,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: onContentTap,
                  child: ListView(
                    controller: scrollController,
                    children: [
                      for (var i = 0; i < 40; i++)
                        SizedBox(
                          height: 80,
                          child: Text(
                            'row $i',
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 35,
                bottom: 16,
                width: 60,
                child: SideTapZone(onTap: onZoneTap),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('侧区点击只触发区域，不触发正文', (tester) async {
    var zoneTaps = 0;
    var contentTaps = 0;
    await host(
      tester,
      onZoneTap: () => zoneTaps++,
      onContentTap: () => contentTaps++,
    );

    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();

    expect(zoneTaps, 1);
    expect(contentTaps, 0, reason: '同一次点击不能被两层各算一遍');

    // 区域外的正文点击仍然照常弹 chrome。
    await tester.tapAt(const Offset(300, 400));
    await tester.pumpAndSettle();
    expect(zoneTaps, 1);
    expect(contentTaps, 1);
  });

  testWidgets('侧区只声明点击，纵向拖拽仍归滚动体', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var zoneTaps = 0;
    await host(
      tester,
      onZoneTap: () => zoneTaps++,
      onContentTap: () {},
      scrollController: controller,
    );

    await tester.dragFrom(const Offset(20, 500), const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0), reason: '侧区不能挡住翻页滚动');
    expect(zoneTaps, 0);
  });
}
