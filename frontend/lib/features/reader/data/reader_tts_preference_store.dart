import 'package:shared_preferences/shared_preferences.dart';

/// 保存阅读器语音朗读的设备级偏好。
class ReaderTtsPreferenceStore {
  const ReaderTtsPreferenceStore();

  static const _speedKey = 'tts_speed';
  static const defaultSpeed = 1.0;

  Future<double> loadSpeed() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getDouble(_speedKey) ?? defaultSpeed;
  }

  Future<void> saveSpeed(double speed) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_speedKey, speed);
  }
}
