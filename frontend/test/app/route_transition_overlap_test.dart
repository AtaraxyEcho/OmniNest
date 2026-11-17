// 推入路由的转场遮蔽（问题：抽屉点设置时两页重叠）。
//
// 托管路由的表面是环境可见的（壁纸要从内容底下透上来），而导航栈要到动画
// 结束才把上一页置为 offstage，所以 RouteEnvironmentSurface 必须在转场期间
// 自己垫一层实底。遮蔽放开得太早，两页重合的那段就变成双重曝光。
//
// 这里判两件事：遮蔽随动画进度的释放曲线（纯函数，逐点可核），以及真路由
// 推入时的首帧全遮与落位全放。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/route/app_route_surface.dart';

const _surfaceColor = Color(0xFF101418);

/// 与主题表面同色相、只靠 alpha 调节的那层遮蔽。
Finder _maskFinder() => find.byWidgetPredicate((widget) {
  if (widget is! ColoredBox) {
    return false;
  }
  return widget.color.toARGB32() & 0x00FFFFFF ==
      _surfaceColor.toARGB32() & 0x00FFFFFF;
});

double _maskAlpha(WidgetTester tester) {
  final masks = tester.widgetList<ColoredBox>(_maskFinder()).toList();
  expect(masks, hasLength(1), reason: '转场中的推入页应只垫一层环境遮蔽');
  return masks.single.color.a;
}

Future<void> _pushIncoming(WidgetTester tester) async {
  Navigator.of(tester.element(find.text('previous'))).push(
    MaterialPageRoute<void>(
      builder:
          (context) => const RouteEnvironmentSurface(
            environmentVisible: true,
            child: Center(child: Text('incoming')),
          ),
    ),
  );
  await tester.pump();
}

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(surface: _surfaceColor),
        ),
        home: const Scaffold(body: Center(child: Text('previous'))),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('遮蔽在页面仍在行程中就保持全遮', () {
    for (final value in [0.0, 0.1, 0.25, 0.4, 0.6]) {
      expect(
        environmentCoverageAt(AnimationStatus.forward, value),
        1.0,
        reason: '进度 $value 时新页仍与上一页重合',
      );
    }
  });

  test('遮蔽在尾段线性放开，落位后完全撤除', () {
    expect(
      environmentCoverageAt(AnimationStatus.forward, 0.7),
      closeTo(0.75, 0.0001),
      reason: '释放段必须连续，不能在最后一帧硬切',
    );
    expect(
      environmentCoverageAt(AnimationStatus.forward, 0.85),
      closeTo(0.375, 0.0001),
    );
    expect(environmentCoverageAt(AnimationStatus.forward, 1.0), 0.0);
    expect(
      environmentCoverageAt(AnimationStatus.completed, 1.0),
      0.0,
      reason: '静止态由环境层供底',
    );
  });

  test('退场方向同样压住正在露出的下一页', () {
    // 退场时 value 由 1 降到 0：刚离开静止位（value 接近 1）重合最多。
    expect(environmentCoverageAt(AnimationStatus.reverse, 1.0), 1.0);
    expect(environmentCoverageAt(AnimationStatus.reverse, 0.6), 1.0);
    expect(
      environmentCoverageAt(AnimationStatus.reverse, 0.2),
      closeTo(0.5, 0.0001),
    );
    expect(environmentCoverageAt(AnimationStatus.reverse, 0.0), 0.0);
  });

  test('释放曲线单调不回弹且始终在 0..1', () {
    for (final status in const [
      AnimationStatus.forward,
      AnimationStatus.reverse,
    ]) {
      var previous = 1.0;
      for (var step = 0; step <= 100; step++) {
        // 行程统一成"离开静止位的距离"再采样，两个方向共用一条曲线。
        final value =
            status == AnimationStatus.reverse ? 1 - step / 100 : step / 100;
        final coverage = environmentCoverageAt(status, value);
        expect(coverage, inInclusiveRange(0.0, 1.0));
        expect(
          coverage,
          lessThanOrEqualTo(previous + 0.0001),
          reason: '${status.name} 行程 $step% 处遮蔽反而变厚',
        );
        previous = coverage;
      }
    }
  });

  testWidgets('真路由推入：首帧全遮、落位全放', (tester) async {
    await pumpApp(tester);
    await _pushIncoming(tester);

    expect(_maskAlpha(tester), 1.0, reason: '推入第一帧就得压住上一页');

    await tester.pumpAndSettle();
    expect(find.text('incoming'), findsOneWidget);
    expect(_maskFinder(), findsNothing, reason: '动画结束后壁纸必须照常透上来，遮蔽层整个撤掉');
  });
}
