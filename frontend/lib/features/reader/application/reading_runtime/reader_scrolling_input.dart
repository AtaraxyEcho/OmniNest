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

/// 滚动输入适配器（方案 §89/§137）。
///
/// 视图与快捷键把原生事件交给本适配器，适配器归一为
/// [ReaderScrollInputSource] 后回调 Runtime 的事务入口；输入源不携带
/// 任何位置信息，位置事实只来自 ScrollPosition 实际 offset。
class ReaderScrollInputAdapter {
  const ReaderScrollInputAdapter({required this.onInput});

  final void Function(ReaderScrollInputSource source) onInput;

  /// 滚轮/触控板滚动信号（PointerScrollEvent）。
  void pointerScroll() => onInput(ReaderScrollInputSource.mouseWheel);

  /// 指针拖动越过阈值。
  void dragThresholdCrossed() => onInput(ReaderScrollInputSource.pointerDrag);

  /// 键盘滚动。
  void keyboardScroll() => onInput(ReaderScrollInputSource.keyboard);
}
