/// 阅读器高亮预设色板。
///
/// 选点、批注弹窗与已有高亮换色共用同一份顺序，避免三处色板漂移。
class ReaderHighlightPalette {
  const ReaderHighlightPalette._();

  static const String defaultColor = '#FFEB3B';

  static const List<String> colors = <String>[
    '#FFEB3B',
    '#4CAF50',
    '#2196F3',
    '#E91E63',
    '#E0E0E0',
  ];
}
