import 'dart:ui';

/// 阅读器内容块的基础类型。
sealed class ContentBlock {}

/// 标题内容块。
class HeadingBlock extends ContentBlock {
  HeadingBlock({required this.text, required this.level, this.startOffset = 0});

  final String text;
  final int level;
  final int startOffset;
}

/// 段落内容块。
class ParagraphBlock extends ContentBlock {
  ParagraphBlock({required this.lines, this.hasTrailingSpacing = false});

  final List<LineData> lines;
  final bool hasTrailingSpacing;
}

/// 段落中的逻辑行。
class LineData {
  const LineData({
    required this.spans,
    this.isNewParagraph = false,
    this.collapsedChars = 0,
    this.softWrap = false,
  });

  final List<ReaderInlineSpan> spans;

  /// 标记此行是否为合并后新段落的起始行。
  final bool isNewParagraph;

  /// 源文本中存在、但不进入可绘制文本的字符数。
  ///
  /// 包含本行行首被剥除的缩进，以及上一行结束时那段含换行的空白。
  /// 折叠量一律只可能出现在行首，因此本行内
  /// `源文本索引 = 可绘制索引 + collapsedChars` 恒成立，
  /// 块级字符记账与页内裁剪都以此为前提。
  final int collapsedChars;

  /// 本行是同一段落内的软换行续行：行前不插换行符，由排版宽度自然折行。
  ///
  /// 词界需要补回的那一个空格在解析期就已并入本行首个 span，
  /// 测量与绘制都不再各自推导邻居字符。
  final bool softWrap;

  /// 本行在源文本中占用的总字符数。
  int get sourceChars => _paintedChars + collapsedChars;

  /// 本行可绘制文本长度。
  int get paintedChars => _paintedChars;

  int get _paintedChars {
    var total = 0;
    for (final span in spans) {
      total += span.text.length;
    }
    return total;
  }
}

/// 合并段落块中，某一行之前应插入的分隔文本。
///
/// 测量（分页、高度表）与绘制必须共用这一条规则：两处分别实现时，
/// 同一块会"按带缩进的文本测量、按不带缩进的文本绘制"，
/// 行宽差异直接变成分页与字符偏移漂移。
/// 返回值长度即 TextPainter 中该分隔符占用的字符数。
String paragraphLineSeparator({
  required bool isFirstLine,
  required bool isNewParagraph,
  required bool previousLineIsEmpty,
  required bool isBlockContinuation,
  required bool startsWithFullWidthIndent,
  bool isSoftWrap = false,
}) {
  // 软换行续行不产生换行符：段内硬换行已被连排，折行交给排版宽度。
  // 切块边界同样适用：块的第一个有效行若正是续行，不能因为它换块就补出缩进。
  if (isSoftWrap) {
    return '';
  }
  if (isFirstLine) {
    return (!startsWithFullWidthIndent && !isBlockContinuation) ? '　　' : '';
  }
  if (isNewParagraph && !previousLineIsEmpty && !startsWithFullWidthIndent) {
    return '\n　　';
  }
  return '\n';
}

/// 行首是否已带全角缩进；已缩进的行不再重复注入缩进。
bool lineStartsWithFullWidthIndent(List<ReaderInlineSpan> spans) {
  for (final span in spans) {
    if (span.text.isEmpty) {
      continue;
    }
    return span.text.startsWith('　　');
  }
  return false;
}

/// 图片内容块。
class ImageBlock extends ContentBlock {
  ImageBlock({required this.src, this.caption, this.alt});

  final String src;
  final String? caption;
  final String? alt;
}

/// 分隔线内容块。
class DividerBlock extends ContentBlock {}

/// 引用内容块。
class BlockquoteBlock extends ContentBlock {
  BlockquoteBlock({required this.lines, this.startOffset = 0});

  final List<LineData> lines;
  final int startOffset;
}

/// 列表内容块。
class ListBlock extends ContentBlock {
  ListBlock({
    required this.items,
    required this.isOrdered,
    this.startOffset = 0,
  });

  final List<ListItemData> items;
  final bool isOrdered;
  final int startOffset;
}

/// 列表项数据。
class ListItemData {
  const ListItemData({required this.spans});

  final List<ReaderInlineSpan> spans;
}

/// 表格内容块。
class TableBlock extends ContentBlock {
  TableBlock({required this.rows, this.startOffset = 0});

  final List<TableRowData> rows;
  final int startOffset;
}

/// 表格行数据。
class TableRowData {
  const TableRowData({required this.cells, required this.isHeader});

  final List<List<ReaderInlineSpan>> cells;
  final bool isHeader;
}

/// 阅读器行内文本及样式信息。
class ReaderInlineSpan {
  const ReaderInlineSpan({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.isHeading = false,
    this.href,
    this.isCode = false,
    this.startOffset = 0,
    this.backgroundColor,
    this.isSuperscript = false,
    this.isSubscript = false,
    this.isMarked = false,
    this.isDeleted = false,
    this.isUnderlined = false,
  });

  final String text;
  final bool isBold;
  final bool isItalic;
  final bool isHeading;
  final String? href;
  final bool isCode;
  final int startOffset;
  final Color? backgroundColor;
  final bool isSuperscript;
  final bool isSubscript;
  final bool isMarked;
  final bool isDeleted;
  final bool isUnderlined;
}
