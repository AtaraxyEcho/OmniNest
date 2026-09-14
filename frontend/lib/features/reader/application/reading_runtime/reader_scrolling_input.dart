/// 滚动输入源（方案 §89）：输入适配层只向 Runtime 声明「出现了什么输入」，
/// 不负责「当前位置在哪里」（方案 §27：Pointer Event 不是位置事实）。
enum ReaderScrollInputSource {
  /// 指针拖动（已越过拖动阈值）。
  pointerDrag,

  /// 鼠标滚轮。
  mouseWheel,

  /// 触控板高频小 delta。
  touchpad,

  /// 键盘滚动。
  keyboard,
}
