/// Desktop / 未知平台的全屏辅助。使用 no-op 实现。
class FullscreenHelperWeb {
  static void enterFullscreen(dynamic element) {}
  static void exitFullscreen() {}
  static void toggleFullscreen(dynamic element) {}
  static bool get isFullscreenEnabled => false;
  static dynamic get documentElement => null;
  static void addChangeListener(void Function(bool active) onChanged) {}
  static void removeChangeListener(void Function(bool active) onChanged) {}
}
