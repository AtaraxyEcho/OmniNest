import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/scroll_restore.dart';

/// 摘要：回归「maxScrollExtent 微增导致恢复反复跳转、永不 settle」。
///
/// 精测收敛与图片渐进加载会让 max 每帧变化数像素，但按内容锚点计算
/// 的落点并未移动。恢复必须以落点偏差为唯一跳转依据：否则稳定帧被
/// 反复清零，主动恢复期拖到总超时（进度写入被持续抑制），监控期还会
/// 把已落位的位置反复拉回。
void main() {
  Future<void> pumpScrollable(
    WidgetTester tester,
    ScrollController controller,
    double childHeight,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: SizedBox(height: childHeight),
          ),
        ),
      ),
    );
  }

  testWidgets('max 每帧微增但落点未变时仍能 settle，且不重复跳转', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var height = 3000.0;
    await pumpScrollable(tester, controller, height);

    final restore = ScrollRestore();
    addTearDown(restore.cancel);
    final settled = <bool>[];
    final jumps = <double>[];
    double? previousOffset;

    restore.start(
      scrollController: controller,
      // 内容锚点语义：落点与 max 无关，max 增长不改变目标。
      targetOffsetBuilder: () => 800.0,
      onSettled: settled.add,
    );

    for (var i = 0; i < 15; i++) {
      height += 5;
      await pumpScrollable(tester, controller, height);
      SchedulerBinding.instance.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
      final offset = controller.offset;
      if (previousOffset != null && (offset - previousOffset).abs() > 0.01) {
        jumps.add(offset);
      }
      previousOffset = offset;
    }

    expect(controller.offset, closeTo(800, 1), reason: '首帧后应落位到目标');
    expect(settled, isNotEmpty, reason: '落点未变时应在稳定帧阈值内 settle');
    expect(settled.last, isTrue);
    expect(jumps, isEmpty, reason: '落位后不得因 max 微增再次跳转');
    expect(restore.isActive, isFalse, reason: 'settle 后进入监控期');
    // 监控期两标记必须分道：isActive 转 false 表示不再搬动落点，
    // shouldSuppressWrites 仍为 true 表示写入仍未稳定。滚动侧闸门靠这一对
    // 区分"整体早退"与"只抑制持久化"，两者同真同假就会把追踪一起停掉。
    expect(restore.shouldSuppressWrites, isTrue, reason: '监控期内仍不该落盘');
  });

  testWidgets('监控期内 max 增长把落点带出容差时才重新激活', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var height = 3000.0;
    await pumpScrollable(tester, controller, height);

    final restore = ScrollRestore();
    addTearDown(restore.cancel);
    final settled = <bool>[];

    restore.start(
      scrollController: controller,
      targetOffsetBuilder: () {
        if (!controller.hasClients) return null;
        // 比例语义：max 变化会等比移动目标。
        return 0.5 * controller.position.maxScrollExtent;
      },
      onSettled: settled.add,
    );

    for (var i = 0; i < 15; i++) {
      await pumpScrollable(tester, controller, height);
      SchedulerBinding.instance.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(settled, isNotEmpty, reason: 'max 不变时应 settle');
    final settledOffset = controller.offset;

    // 小幅增长：目标移动不足容差，监控期不应拉回或重激活。
    for (var i = 0; i < 3; i++) {
      height += 4;
      await pumpScrollable(tester, controller, height);
      SchedulerBinding.instance.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.offset, closeTo(settledOffset, 1), reason: '小幅布局变化不驱动跳转');

    // 大幅增长：目标移出容差，重新激活并跟随落位。
    height += 800;
    await pumpScrollable(tester, controller, height);
    SchedulerBinding.instance.scheduleFrame();
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      controller.offset,
      closeTo(0.5 * controller.position.maxScrollExtent, 1),
      reason: '布局大幅变化后应跟随新落点',
    );
    expect(restore.isActive, isTrue, reason: '大幅布局变化应重新激活');
  });
}
