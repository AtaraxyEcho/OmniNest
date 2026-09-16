import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/scroll_restore.dart';

/// 摘要：回归「恢复目标未就绪时在错误位置 settle」。
///
/// 章节高度未精测时估算落点对章尾可低估数十个百分点，恢复必须支持
/// targetOffsetBuilder 返回 null（原地保持、不积累稳定帧、不触发
/// onSettled），待目标就绪后再驱动落位。
void main() {
  testWidgets('目标未就绪时保持原位，就绪后驱动到真实目标', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: const SizedBox(height: 5000),
          ),
        ),
      ),
    );

    final restore = ScrollRestore();
    addTearDown(restore.cancel);
    var settled = <bool>[];
    var ready = false;
    var builderCalls = 0;

    restore.start(
      scrollController: controller,
      targetOffsetBuilder: () {
        builderCalls++;
        if (!ready) {
          return null;
        }
        return 800.0;
      },
      onSettled: (completed) => settled.add(completed),
    );

    // 未就绪期：逐帧原地保持，不跳转、不 settle。
    // （ScrollRestore 用 addPostFrameCallback 自循环，不主动调度帧，
    // 测试环境需手动 scheduleFrame 驱动；生产环境引擎持续出帧。）
    for (var i = 0; i < 3; i++) {
      SchedulerBinding.instance.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(builderCalls, greaterThanOrEqualTo(3), reason: 'tick 链应持续重试');
    expect(controller.offset, 0, reason: '保持期不得跳转');
    expect(settled, isEmpty, reason: '保持期不得 settle');

    // 目标就绪：驱动到真实目标并稳定 settle（10 帧稳定判定）。
    ready = true;
    for (var i = 0; i < 15; i++) {
      SchedulerBinding.instance.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.offset, closeTo(800, 1), reason: '就绪后应落位到目标');
    expect(settled, isNotEmpty);
    expect(settled.last, isTrue);
  });
}
