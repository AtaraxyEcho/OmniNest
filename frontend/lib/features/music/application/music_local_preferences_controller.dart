import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/data/music_local_preference_store.dart';

final musicLocalPreferenceStoreProvider = Provider<MusicLocalPreferenceStore>(
  (ref) => const MusicLocalPreferenceStore(),
);

final musicLocalPreferencesControllerProvider =
    AsyncNotifierProvider<MusicLocalPreferencesController, String>(
      MusicLocalPreferencesController.new,
    );

/// 管理音乐播放的设备级偏好，当前仅包含在线播放音质。
class MusicLocalPreferencesController extends AsyncNotifier<String> {
  @override
  Future<String> build() {
    return ref
        .read(musicLocalPreferenceStoreProvider)
        .loadOnlineQuality()
        .then(
          (value) =>
              value.isEmpty
                  ? MusicLocalPreferenceStore.defaultOnlineQuality
                  : value,
        );
  }

  Future<void> setOnlineQuality(String quality) async {
    await ref
        .read(musicLocalPreferenceStoreProvider)
        .saveOnlineQuality(quality);
    state = AsyncData(quality);
  }
}
