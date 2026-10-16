import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/mobile_segment_pager.dart';

/// 受控跟手分页器的三条主张：跟手落页、外部改选带动画、关闭只禁横滑。
///
/// 第三条不是形式检查：关掉横滑用的是 NeverScrollableScrollPhysics，
/// 若它把 animateToPage 一起挡了，分段条点选会静默失灵。只有跑起来才知道。
void main() {
  const sections = <String>['a', 'b', 'c'];

  Widget page(String section) =>
      Center(child: Text('page-$section', textDirection: TextDirection.ltr));

  Widget harness({
    required String current,
    required ValueChanged<String> onChanged,
    bool interactionEnabled = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MobileSegmentPager<String>(
          sections: sections,
          current: current,
          onChanged: onChanged,
          interactionEnabled: interactionEnabled,
          pageBuilder: (context, section) => page(section),
        ),
      ),
    );
  }

  testWidgets('跟手左滑落到下一页并上报分段', (tester) async {
    final reported = <String>[];
    await tester.pumpWidget(harness(current: 'a', onChanged: reported.add));
    await tester.pumpAndSettle();
    expect(find.text('page-a'), findsOneWidget);

    // 起手即跟手：拖动中途下一页已经平移进视口。
    // 跟手的判据用当前页的位移：邻居在静止时并不在树里，测不到它的静止位。
    final restA = tester.getTopLeft(find.text('page-a')).dx;
    final gesture = await tester.startGesture(const Offset(300, 300));
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('page-a')).dx,
      closeTo(restA - 120, 8),
      reason: '拖动中当前页应随手指平移，而不是等落定才整块换',
    );

    // 落定阈值按整页比例算：拖过一半才会停在下一页。
    await gesture.moveBy(const Offset(-500, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(reported, ['b']);
    expect(find.text('page-b'), findsOneWidget);
  });

  testWidgets('外部改选带动画落页', (tester) async {
    await tester.pumpWidget(harness(current: 'a', onChanged: (_) {}));
    await tester.pumpAndSettle();
    await tester.pumpWidget(harness(current: 'c', onChanged: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('page-c'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭横滑后拖动不改分段，外部改选仍然落页', (tester) async {
    final reported = <String>[];
    await tester.pumpWidget(
      harness(current: 'a', onChanged: reported.add, interactionEnabled: false),
    );
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(300, 300), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(reported, isEmpty, reason: '关闭态下横滑必须完全不生效');
    expect(find.text('page-a'), findsOneWidget);

    // 同一状态下外部改选必须还能落页：证明关掉的是手势，不是滚动本身。
    await tester.pumpWidget(
      harness(current: 'b', onChanged: reported.add, interactionEnabled: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('page-b'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
