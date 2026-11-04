import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_highlight_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_selection_key_actions.dart';

void main() {
  const digitKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ];

  test('数字键 1–5 按调色板同序选色，与工具栏圆点一一对应', () {
    final applied = <String>[];
    final actions = ReaderSelectionKeyActions(
      colors: ReaderHighlightPalette.colors,
      applyColor: applied.add,
    );

    for (final key in digitKeys) {
      expect(
        runReaderSelectionKeyShortcut(key, actions),
        isTrue,
        reason: '${key.keyLabel} 必须落在调色板的对应颜色',
      );
    }
    expect(applied, ReaderHighlightPalette.colors);
  });

  test('小键盘数字与主键盘同序，超出色数的按键不消费', () {
    final applied = <String>[];
    final actions = ReaderSelectionKeyActions(
      colors: const ['#AAAAAA', '#BBBBBB', '#CCCCCC'],
      applyColor: applied.add,
    );

    expect(
      runReaderSelectionKeyShortcut(LogicalKeyboardKey.numpad2, actions),
      isTrue,
    );
    expect(
      runReaderSelectionKeyShortcut(LogicalKeyboardKey.numpad4, actions),
      isFalse,
      reason: '配色不足 5 色时不得越界取色',
    );
    expect(
      runReaderSelectionKeyShortcut(LogicalKeyboardKey.digit6, actions),
      isFalse,
    );
    expect(applied, ['#BBBBBB']);
  });

  test('N 只在选区与高亮重叠时取消高亮', () {
    var removed = 0;
    final withRemove = ReaderSelectionKeyActions(
      colors: ReaderHighlightPalette.colors,
      applyColor: (_) {},
      removeHighlight: () => removed++,
    );
    expect(
      runReaderSelectionKeyShortcut(LogicalKeyboardKey.keyN, withRemove),
      isTrue,
    );
    expect(removed, 1);

    final withoutRemove = ReaderSelectionKeyActions(
      colors: ReaderHighlightPalette.colors,
      applyColor: (_) {},
    );
    expect(
      runReaderSelectionKeyShortcut(LogicalKeyboardKey.keyN, withoutRemove),
      isFalse,
      reason: '无重叠高亮时 N 必须交回页面命令（打开批注面板）',
    );
    expect(removed, 1);
  });

  test('未注册选区动作时不消费任何按键', () {
    expect(
      runReaderSelectionKeyShortcut(LogicalKeyboardKey.digit1, null),
      isFalse,
    );
    expect(
      runReaderSelectionKeyShortcut(LogicalKeyboardKey.keyN, null),
      isFalse,
    );
  });
}
