import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_sleep_timer_controller.dart';

void main() {
  test('定时关闭档位开启、倒计时归零后自动清理', () {
    final container = ProviderContainer.test();
    addTearDown(container.dispose);
    final notifier = container.read(musicSleepTimerControllerProvider.notifier);

    notifier.start(const Duration(minutes: 30));
    final state = container.read(musicSleepTimerControllerProvider);
    expect(state.remaining, const Duration(minutes: 30));
    expect(state.stopAfterCurrentTrack, isFalse);

    notifier.cancel();
    expect(container.read(musicSleepTimerControllerProvider).active, isFalse);
  });

  test('播完当前曲模式与倒计时互斥', () {
    final container = ProviderContainer.test();
    addTearDown(container.dispose);
    final notifier = container.read(musicSleepTimerControllerProvider.notifier);

    notifier.start(const Duration(minutes: 15));
    notifier.toggleStopAfterCurrentTrack();
    final switched = container.read(musicSleepTimerControllerProvider);
    expect(switched.stopAfterCurrentTrack, isTrue);
    expect(switched.remaining, isNull);

    notifier.toggleStopAfterCurrentTrack();
    expect(container.read(musicSleepTimerControllerProvider).active, isFalse);
  });
}
