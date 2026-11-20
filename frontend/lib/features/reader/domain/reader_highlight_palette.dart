/// 阅读器高亮预设色板（1:1 对齐样例 `ReaderView.tsx:19` 四色）。
///
/// 历史数据库中的旧 5 色批注在渲染层直接按十六进制解析，保持 100% 向下兼容。
class ReaderHighlightPalette {
  const ReaderHighlightPalette._();

  static const String defaultColor = '#F2D36B';

  static const List<String> colors = <String>[
    '#F2D36B',
    '#8CC5B2',
    '#E69A8D',
    '#A99BD8',
  ];
}
