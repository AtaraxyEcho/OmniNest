import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_tts_speed_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('语音朗读速度从数据层恢复并通过控制器持久化', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'tts_speed': 1.5});
    final container = ProviderContainer.test();
    addTearDown(container.dispose);

    expect(await container.read(readerTtsSpeedControllerProvider.future), 1.5);

    await container
        .read(readerTtsSpeedControllerProvider.notifier)
        .setSpeed(1.75);

    final preferences = await SharedPreferences.getInstance();
    expect(container.read(readerTtsSpeedControllerProvider).value, 1.75);
    expect(preferences.getDouble('tts_speed'), 1.75);
  });
}
