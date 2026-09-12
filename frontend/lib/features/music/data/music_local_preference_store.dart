import 'package:shared_preferences/shared_preferences.dart';

/// 保存音乐播放仅与当前设备相关的轻量偏好。
class MusicLocalPreferenceStore {
  const MusicLocalPreferenceStore();

  static const _onlineQualityKey = 'music_online_quality';
  static const _playbackSpeedKey = 'music_playback_speed';
  static const String defaultOnlineQuality = 'exhigh';

  Future<String> loadOnlineQuality() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_onlineQualityKey) ?? defaultOnlineQuality;
  }

  Future<void> saveOnlineQuality(String quality) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_onlineQualityKey, quality);
  }

  Future<double> loadPlaybackSpeed() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getDouble(_playbackSpeedKey);
    return value ?? 1.0;
  }

  Future<void> savePlaybackSpeed(double speed) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_playbackSpeedKey, speed);
  }
}
