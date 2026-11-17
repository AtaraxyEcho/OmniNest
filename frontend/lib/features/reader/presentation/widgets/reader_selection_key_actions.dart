import 'package:flutter/services.dart';

/// 选区工具栏可用时的键盘动作：1–5 选调色板颜色，N 取消与选区重叠的高亮。
///
/// 由正文在有有效选区时注册、选区结束时清除；页面按键处理器按注册状态
/// 决定这一层是否消费按键，未注册时 `ReaderShortcutResolver` 照常工作。
class ReaderSelectionKeyActions {
  const ReaderSelectionKeyActions({
    required this.colors,
    required this.applyColor,
    this.removeHighlight,
  });

  /// 与选区工具栏圆点同序的颜色值，数字键 1 对应第一个。
  final List<String> colors;

  /// 与点选圆点完全一致的动作：重叠时换色或取消，未重叠时新建高亮。
  final ValueChanged<String> applyColor;

  /// 仅当选区与已有高亮重叠时有值，按 N 移除重叠的高亮。
  final VoidCallback? removeHighlight;
}

const List<LogicalKeyboardKey> _colorDigitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
];

const List<LogicalKeyboardKey> _colorNumpadKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
];

/// 执行选区键盘动作，返回该按键是否已被这一层消费。
bool runReaderSelectionKeyShortcut(
  LogicalKeyboardKey key,
  ReaderSelectionKeyActions? actions,
) {
  if (actions == null) {
    return false;
  }
  if (key == LogicalKeyboardKey.keyN) {
    final removeHighlight = actions.removeHighlight;
    if (removeHighlight == null) {
      return false;
    }
    removeHighlight();
    return true;
  }
  final index = _colorKeyIndex(key);
  if (index == null || index >= actions.colors.length) {
    return false;
  }
  actions.applyColor(actions.colors[index]);
  return true;
}

int? _colorKeyIndex(LogicalKeyboardKey key) {
  final mainRow = _colorDigitKeys.indexOf(key);
  if (mainRow >= 0) {
    return mainRow;
  }
  final numpad = _colorNumpadKeys.indexOf(key);
  return numpad >= 0 ? numpad : null;
}
