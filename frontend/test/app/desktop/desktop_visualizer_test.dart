import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_visualizer.dart';

/// 播放态频谱逐帧计算出的柱高必须真正触发重绘。
///
/// 回归点：`_tick` 原地修改同一个 `List<double>`，若 painter 也拿这个引用，
/// `shouldRepaint` 会因为列表身份没变而一直返回 false，频谱看起来完全静止。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('播放时频谱 painter 每帧都请求重绘', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 120,
            child: DesktopVisualizer(
              playing: true,
              color: Colors.white,
              bars: 14,
              seed: 3,
            ),
          ),
        ),
      ),
    );

    final visualizer = find.byType(DesktopVisualizer);
    final paint = find.descendant(
      of: visualizer,
      matching: find.byType(CustomPaint),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    final first = tester.widget<CustomPaint>(paint).painter!;

    await tester.pump(const Duration(milliseconds: 32));
    final second = tester.widget<CustomPaint>(paint).painter!;

    expect(second, isNot(same(first)));
    expect(second.shouldRepaint(first), isTrue);
  });
}
