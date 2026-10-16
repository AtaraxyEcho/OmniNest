import 'package:flutter/widgets.dart';

import 'package:omninest/features/reader/presentation/widgets/reader_book_stylesheet.dart';

/// 阅读器默认档的段落首行缩进字数，与段距倍率同样只在这里表达一次。
///
/// 用字数而不是 em：缩进由注入的全角空格实现，CJK 下 `2em` 不保证正好两个字。
const int defaultFirstLineIndentChars = 2;

/// 阅读器默认档的段落尾间距倍率，稿子 `.article-column > p` 的 `margin-bottom: 1.35em`。
const double defaultParagraphSpacingScale = 1.35;

/// 源文本空行折算段距时的上限（一行白 = 读者的一个行高）。
///
/// 抓取残留与畸形文件会连排十几个空行，不设上限就是章末凭空多出半页留白；
/// 两行已经足够表达"作者在这里分了段"这一意图。
const int maxBlankLineGapLines = 2;

/// 稿子 `.article-column blockquote` 的文字档：`calc(+1px)` 字号与 `line-height: 1.75`。
///
/// 放这里而不是渲染件里：测量侧与渲染侧都要取同一份，任何一侧另写都会在页底裁字。
const double blockquoteFontDeltaPx = 1.0;
const double blockquoteLineHeight = 1.75;

/// 阅读器内容块的基础类型。
sealed class ContentBlock {}

/// 标题内容块。
class HeadingBlock extends ContentBlock {
  HeadingBlock({
    required this.text,
    required this.level,
    this.startOffset = 0,
    this.align,
  });

  final String text;
  final int level;
  final int startOffset;

  /// 书在这个标题元素上表达过的对齐方式（样式表命中或祖先继承）。
  ///
  /// null 表示这本书没说。章名居中是中文书最常见的标题版式（`h1 { text-align: center }`），
  /// 不带这一份表达时「跟随原书排版」对标题就无从生效。字号与字重不在此列：
  /// 标题档位由阅读器统一给，混字号会让测量、装页与渲染三处失去同一把尺。
  final TextAlign? align;
}

/// 段落内容块。
class ParagraphBlock extends ContentBlock {
  ParagraphBlock({
    required this.lines,
    this.hasTrailingSpacing = false,
    this.style,
  });

  final List<LineData> lines;
  final bool hasTrailingSpacing;

  /// 书对这个段落表达过的排版意图；null 表示没说，交给阅读器默认档。
  ///
  /// 块级字段（段距、对齐）由合并规则保证块内一致，缩进按行取 `lines[i].style`。
  final ParagraphStyleSpec? style;
}

/// 段落中的逻辑行。
class LineData {
  const LineData({
    required this.spans,
    this.isNewParagraph = false,
    this.collapsedChars = 0,
    this.trailingCollapsedChars = 0,
    this.softWrap = false,
    this.style,
  });

  final List<ReaderInlineSpan> spans;

  /// 标记此行是否为合并后新段落的起始行。
  final bool isNewParagraph;

  /// 本行所属源段落的书样式，与所在 [ParagraphBlock.style] 同源。
  final ParagraphStyleSpec? style;

  /// 源文本中存在、但不进入可绘制文本的字符数。
  ///
  /// 只包含本行**行首**被剥除的字符：缩进，以及上一行结束时那段含换行的空白。
  /// 裁剪侧按 `源索引 = 行首 + collapsedChars + 可绘制索引` 定位，所以行尾那部分
  /// 不能混进来，另记在 [trailingCollapsedChars]。
  final int collapsedChars;

  /// 本行**行尾**存在但不绘制的源字符数（段尾空白、以 `<br>` 收尾的最后一格）。
  ///
  /// 它们必须计入块的字符总数——每个源字符都要在字符域里有一个位置，TXT 切片的
  /// 偏移也直接以源长度为准——但不能当行首折叠量，否则整行可绘制文本错位。
  final int trailingCollapsedChars;

  /// 本行是同一段落内的软换行续行：行前不插换行符，由排版宽度自然折行。
  ///
  /// 词界需要补回的那一个空格在解析期就已并入本行首个 span，
  /// 测量与绘制都不再各自推导邻居字符。
  final bool softWrap;

  /// 本行在源文本中占用的总字符数。
  int get sourceChars =>
      _paintedChars + collapsedChars + trailingCollapsedChars;

  /// 带上所属源段落的书样式，行内容与其他记账保持不变。
  LineData withStyle(ParagraphStyleSpec? style) {
    if (style == null || identical(this.style, style)) return this;
    return LineData(
      spans: spans,
      isNewParagraph: isNewParagraph,
      collapsedChars: collapsedChars,
      trailingCollapsedChars: trailingCollapsedChars,
      softWrap: softWrap,
      style: style,
    );
  }

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

/// 合并段落块某一行之前的分隔内容。
///
/// 换行仍是文本字符，首行缩进改由定宽盒子表达：两端对齐把行首空白算进可压缩
/// 空间，多行段的全角空格缩进会被折成零宽，只有不可拉伸的盒子能保住这一截。
class ParagraphLineGap {
  const ParagraphLineGap({required this.newLine, required this.indentChars});

  /// 空分隔：软换行与续接页首行都不加任何东西。
  static const ParagraphLineGap none = ParagraphLineGap(
    newLine: false,
    indentChars: 0,
  );

  /// 本行之前是否要补段落分隔符（换行）。
  final bool newLine;

  /// 首行缩进字数；0 表示不缩进。宽度只能经由
  /// `ReaderViewSettings.indentBoxWidth` 换算，两侧各算一份会折出不同行数。
  final int indentChars;

  /// 在 TextPainter 平铺文本里占用的码元数。
  ///
  /// 每个缩进盒子是一个 `0xFFFC` 对象替换字符：占排版文本的一个位置，
  /// 但不占章节字符域的任何位置——字符偏移始终按源文本换算。
  int get painterUnits =>
      (newLine ? _newLineChars : 0) + (indentChars > 0 ? _placeholderUnits : 0);

  static const int _newLineChars = 1;

  /// 一个 WidgetSpan 在排版文本里占一个码元。
  static const int _placeholderUnits = 1;
}

/// 行前分隔符的排版长度（码元数）：测量侧推进排版游标必须用它，
/// 而不是 span 的文本长度——缩进盒子没有文本。
int paragraphGapPainterUnits(ParagraphLineGap gap) => gap.painterUnits;

/// 装配行前分隔 span：测量与绘制共用，两侧必须给出完全相同的 span 序列。
List<InlineSpan> paragraphGapSpans(
  ParagraphLineGap gap, {
  required double indentWidth,
}) {
  final spans = <InlineSpan>[];
  if (gap.newLine) {
    spans.add(const TextSpan(text: '\n'));
  }
  if (gap.indentChars > 0 && indentWidth > 0) {
    spans.add(
      // 零高度的盒子贴在基线上：只让出水平宽度，不参与行高。不能用 baseline 对齐，
      // SizedBox 提供不了 alphabetic 基线，框架会因取不到 baseline 直接断言失败。
      WidgetSpan(
        alignment: PlaceholderAlignment.bottom,
        child: SizedBox(width: indentWidth),
      ),
    );
  }
  return spans;
}

/// 修剪装配文本末尾的空白。
///
/// 缩进改成定宽盒子之前，这一刀只落在绘制侧：测量侧仍按注入了全角空格的文本折行，
/// 两侧的 `U+3000` 口径不一致，宽度与行数都会漂。现在分隔符两侧同为盒子，
/// 这一处只剩绘制侧需要（行尾空白不画），测量不再另立一份规则。
void trimTrailingSpacesInSpans(List<InlineSpan> spans) {
  if (spans.isEmpty) {
    return;
  }
  final last = spans.last;
  if (last is! TextSpan || last.text == null) {
    return;
  }
  final trimmed = last.text!.trimRight();
  if (trimmed.length == last.text!.length) {
    return;
  }
  spans[spans.length - 1] = TextSpan(
    text: trimmed,
    style: last.style,
    recognizer: last.recognizer,
  );
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

/// 某一行之前的分隔内容：换行 + 首行缩进盒子。
///
/// 测绘两侧一律经由这里取值：换行是文本，缩进是定宽盒子。
ParagraphLineGap paragraphGap({
  required bool isFirstLine,
  required bool isNewParagraph,
  required bool previousLineIsEmpty,
  required bool isBlockContinuation,
  required bool startsWithFullWidthIndent,
  int indentChars = defaultFirstLineIndentChars,
  bool isSoftWrap = false,
}) {
  if (isSoftWrap) {
    return ParagraphLineGap.none;
  }
  if (isFirstLine) {
    return ParagraphLineGap(
      newLine: false,
      indentChars:
          (!startsWithFullWidthIndent && !isBlockContinuation)
              ? indentChars
              : 0,
    );
  }
  return ParagraphLineGap(
    newLine: true,
    indentChars:
        (isNewParagraph && !previousLineIsEmpty && !startsWithFullWidthIndent)
            ? indentChars
            : 0,
  );
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
///
/// [style] 是这本书在 `<blockquote>` 自己身上表达过的意图（段距与对齐）。按行生效的
/// 缩进挂在各行的 `style` 上，块级量必须挂在块上，否则裁剪与层叠两侧取不到同一份值。
///
/// 一个引用会按对齐拆成若干块（一个 `Text.rich` 只带一个 `textAlign`）。盒子的上下
/// 留白属于**整个引用**而不是每一段，所以只有带标记的那一侧才收这一份；页内裁剪按
/// "运行位置 ∧ 窗口位置"取交集，段与段之间因此是相接的，而不是各加一份 48px。
class BlockquoteBlock extends ContentBlock {
  BlockquoteBlock({
    required this.lines,
    this.startOffset = 0,
    this.style,
    this.hasTopPadding = true,
    this.hasBottomPadding = true,
  });

  final List<LineData> lines;
  final int startOffset;
  final ParagraphStyleSpec? style;
  final bool hasTopPadding;
  final bool hasBottomPadding;
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
