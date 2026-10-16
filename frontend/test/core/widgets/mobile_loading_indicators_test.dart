// 移动端加载指示规则：一屏之内的动画指示至多一处。
//
// MobileSkeletonBlock 早期在盒内塞 24px 转圈，同屏放两块就是两个动画，
// 放进 16px 高的槽位还会溢出；现在它是静态占位，动画只允许来自
// AppLoading（整页首屏）或 MobileLoadingLine（区级唯一一条线）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('静态占位块不产生动画指示，且短于 24px 的槽位不溢出', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          MobileSkeletonBlock(height: 16, width: 168),
          MobileSkeletonBlock(height: 220),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('区级进度线一屏一条，是不定量动画的唯一来源', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          MobileLoadingLine(top: true),
          MobileSkeletonBlock(height: 120),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    final line = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(line.value, isNull, reason: '不定量：value 为空才会自行动画');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
