import 'package:shared_preferences/shared_preferences.dart';

/// 保存影视播放器仅与当前设备相关的轻量偏好。
class VideoLocalPreferenceStore {
  const VideoLocalPreferenceStore();

  static const _audioCacheNoticeShownKey = 'audio_cache_notice_shown';

  Future<bool> loadAudioCacheNoticeShown() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_audioCacheNoticeShownKey) ?? false;
  }

  Future<void> markAudioCacheNoticeShown() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_audioCacheNoticeShownKey, true);
  }
}
