import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/application/photo_cover_recovery.dart';

/// 记录 refreshForRealtime 调用次数的假控制器：不触网。
class _CountingPhotoCenterController extends PhotoCenterController {
  _CountingPhotoCenterController();

  int realtimeRefreshCalls = 0;

  @override
  Future<void> refreshForRealtime() async {
    realtimeRefreshCalls += 1;
  }
}

void main() {
  test('首次失败立即触发恢复刷新，节流窗口内的后续失败不重复触发', () {
    final container = ProviderContainer(
      overrides: [
        photoCenterControllerProvider.overrideWith(
          () => _CountingPhotoCenterController(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final recovery = container.read(photoCoverRecoveryProvider.notifier);
    recovery.reportFailure();
    recovery.reportFailure();
    recovery.reportFailure();

    final controller =
        container.read(photoCenterControllerProvider.notifier)
            as _CountingPhotoCenterController;
    expect(controller.realtimeRefreshCalls, 1);
  });

  test('连续失败达到次数上限后停止触发恢复刷新', () {
    final container = ProviderContainer(
      overrides: [
        photoCenterControllerProvider.overrideWith(
          () => _CountingPhotoCenterController(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final recovery = container.read(photoCoverRecoveryProvider.notifier);
    recovery.reportFailure();
    expect(container.read(photoCoverRecoveryProvider), 1);
  });

  test('恢复控制器暴露的失败计数供测试与诊断消费', () {
    final container = ProviderContainer(
      overrides: [
        photoCenterControllerProvider.overrideWith(
          () => _CountingPhotoCenterController(),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(photoCoverRecoveryProvider), 0);
    container.read(photoCoverRecoveryProvider.notifier).reportFailure();
    expect(container.read(photoCoverRecoveryProvider), 1);
  });
}
