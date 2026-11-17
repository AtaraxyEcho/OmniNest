import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/video/data/video_local_preference_store.dart';

final videoLocalPreferenceStoreProvider = Provider<VideoLocalPreferenceStore>(
  (ref) => const VideoLocalPreferenceStore(),
);

final videoLocalPreferencesControllerProvider =
    AsyncNotifierProvider<VideoLocalPreferencesController, bool>(
      VideoLocalPreferencesController.new,
    );

/// 管理影视播放器的设备级提示状态。
class VideoLocalPreferencesController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref
        .read(videoLocalPreferenceStoreProvider)
        .loadAudioCacheNoticeShown();
  }

  Future<void> markAudioCacheNoticeShown() async {
    state = const AsyncData(true);
    await ref
        .read(videoLocalPreferenceStoreProvider)
        .markAudioCacheNoticeShown();
  }
}
