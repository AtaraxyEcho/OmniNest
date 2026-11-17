import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/application/video_local_preferences_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('音频缓存提示状态通过应用控制器持久化', () async {
    final container = ProviderContainer.test();
    addTearDown(container.dispose);

    expect(
      await container.read(videoLocalPreferencesControllerProvider.future),
      isFalse,
    );

    await container
        .read(videoLocalPreferencesControllerProvider.notifier)
        .markAudioCacheNoticeShown();

    final preferences = await SharedPreferences.getInstance();
    expect(
      container.read(videoLocalPreferencesControllerProvider).value,
      isTrue,
    );
    expect(preferences.getBool('audio_cache_notice_shown'), isTrue);
  });
}
