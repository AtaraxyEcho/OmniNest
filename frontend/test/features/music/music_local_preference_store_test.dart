import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/data/music_local_preference_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 曲目级歌词延迟：设备本地存取与按曲隔离。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('曲目级歌词延迟按曲目隔离存取', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    const store = MusicLocalPreferenceStore();

    expect(await store.loadLyricOffsetMs('track-a'), isNull);
    await store.saveLyricOffsetMs('track-a', 300);
    await store.saveLyricOffsetMs('track-b', -200);

    expect(
      MusicLocalPreferenceStore.lyricOffsetKey('track-a'),
      'music_lyric_offset_track-a',
    );
    expect(await store.loadLyricOffsetMs('track-a'), 300);
    expect(await store.loadLyricOffsetMs('track-b'), -200);
    // 未设置的曲目不受影响。
    expect(await store.loadLyricOffsetMs('track-c'), isNull);
  });

  test('曲目级延迟微调叠加在当前值上并持久化', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final container = ProviderContainer.test();
    addTearDown(container.dispose);

    await container.read(musicTrackLyricOffsetProvider('track-1').future);
    expect(
      container.read(musicTrackLyricOffsetProvider('track-1')).value,
      isNull,
    );

    await container
        .read(musicTrackLyricOffsetProvider('track-1').notifier)
        .adjust(300);
    await container
        .read(musicTrackLyricOffsetProvider('track-1').notifier)
        .adjust(500);
    expect(container.read(musicTrackLyricOffsetProvider('track-1')).value, 800);

    // 调整结果持久化到设备本地存储，且按曲目隔离。
    final store = const MusicLocalPreferenceStore();
    expect(await store.loadLyricOffsetMs('track-1'), 800);
  });

  test('曲目级延迟调整被限制在 ±1000ms', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final container = ProviderContainer.test();
    addTearDown(container.dispose);

    await container.read(musicTrackLyricOffsetProvider('track-1').future);
    await container
        .read(musicTrackLyricOffsetProvider('track-1').notifier)
        .adjust(-1500);
    expect(
      container.read(musicTrackLyricOffsetProvider('track-1')).value,
      -1000,
    );
  });
}
