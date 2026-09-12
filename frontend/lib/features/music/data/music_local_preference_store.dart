import 'package:shared_preferences/shared_preferences.dart';

/// 保存音乐播放仅与当前设备相关的轻量偏好。
class MusicLocalPreferenceStore {
  const MusicLocalPreferenceStore();

  static const _onlineQualityKey = 'music_online_quality';
  static const String defaultOnlineQuality = 'exhigh';

  Future<String> loadOnlineQuality() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_onlineQualityKey) ?? defaultOnlineQuality;
  }

  Future<void> saveOnlineQuality(String quality) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_onlineQualityKey, quality);
  }
}
