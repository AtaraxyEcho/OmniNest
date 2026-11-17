import 'package:shared_preferences/shared_preferences.dart';

/// 保存音乐播放仅与当前设备相关的轻量偏好。
class MusicLocalPreferenceStore {
  const MusicLocalPreferenceStore();

  static const _onlineQualityKey = 'music_online_quality';
  static const _playbackSpeedKey = 'music_playback_speed';
  static const _lyricScrollModeKey = 'music_lyric_scroll_mode';
  static const String defaultOnlineQuality = 'exhigh';

  /// 歌词滚动模式默认开启（设备级偏好，不随视觉设置跨端同步）。
  static const bool defaultLyricScrollMode = true;

  /// 曲目级歌词延迟的存储键（设备本地，不入库、不跨端同步）。
  static String lyricOffsetKey(String trackId) => 'music_lyric_offset_$trackId';

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

  Future<bool> loadLyricScrollMode() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_lyricScrollModeKey) ?? defaultLyricScrollMode;
  }

  Future<void> saveLyricScrollMode(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_lyricScrollModeKey, enabled);
  }

  /// 读取曲目级歌词延迟（毫秒）；未设置覆盖时返回 null。
  Future<int?> loadLyricOffsetMs(String trackId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(lyricOffsetKey(trackId));
  }

  Future<void> saveLyricOffsetMs(String trackId, int offsetMs) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(lyricOffsetKey(trackId), offsetMs);
  }
}
