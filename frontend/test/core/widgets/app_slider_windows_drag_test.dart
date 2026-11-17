import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/app_slider.dart';

void main() {
  testWidgets('Windows 自绘滑条拖动应连续触发 onChanged', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    var changed = 0;
    double last = 0.5;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: AppSlider(
                value: 0.5,
                onChanged: (v) {
                  changed++;
                  last = v;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(AppSlider), const Offset(80, 0));
    await tester.pump();

    expect(changed, greaterThan(0), reason: '拖动应触发 onChanged');
    expect(last, greaterThan(0.5), reason: '向右拖动应增大取值');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows 自绘滑条点击应触发 onChanged', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    var changed = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: AppSlider(value: 0.5, onChanged: (v) => changed++),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final box = tester.getRect(find.byType(AppSlider));
    await tester.tapAt(box.center + const Offset(60, 0));
    await tester.pump();

    expect(changed, greaterThan(0), reason: '点击应触发 onChanged');
    debugDefaultTargetPlatformOverride = null;
  });
}
