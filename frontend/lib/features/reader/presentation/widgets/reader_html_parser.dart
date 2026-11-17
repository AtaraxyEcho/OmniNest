import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:omninest/features/reader/presentation/widgets/reader_book_stylesheet.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';

export 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
export 'package:omninest/features/reader/presentation/widgets/reader_html_text.dart';

// ── 分文件（同一库，私有成员共享）──
// 各块型的处理器在 reader_html_parser_blocks.dart，段内换行折叠与内联提取在 reader_html_parser_text.dart。
part 'reader_html_parser_blocks.dart';
part 'reader_html_parser_text.dart';

/// 清洗文本中的占宽不可见 Unicode 字符。
///
/// -  （不换行空格）→ 普通空格，避免 RichText 换行计算异常
/// - ​（零宽空格）、‌、‍、﻿、­、⁠ → 移除
String _sanitizeText(String text) {
  return text
      .replaceAll(' ', ' ')
      .replaceAll('​', '')
      .replaceAll('‌', '')
      .replaceAll('‍', '')
      .replaceAll('﻿', '')
      .replaceAll('­', '')
      .replaceAll('⁠', '');
}

// ── HTML Parser (DOM-based) ──

/// 解析上下文，携带文本偏移量状态，替代全局可变变量。
class _ParseContext {
  _ParseContext(this.styles);

  /// 这本书声明过的样式表，元素的内联 `style` 在解析时就地与它层叠。
  final BookStyleSheet styles;

  int offset = 0;

  /// 章内锚点（`id` / `name`）在字符域里的位置，与块偏移、页区间同一个域。
  ///
  /// 跳转以前按 `stripHtml(前缀).length` 反推，那是第三个域：实体、`<title>`、
  /// 标签空白都不在块的字符计数里，落到页上会偏十几到几十字符。
  final Map<String, int> anchors = {};

  /// 记录一个元素携带的锚点名。只登记第一次出现的位置，重复 id 按 DOM 顺序取先者。
  void noteAnchor(dom.Element element) {
    for (final key in const ['id', 'name']) {
      final value = element.attributes[key];
      if (value == null || value.isEmpty) continue;
      anchors.putIfAbsent(value, () => offset);
    }
  }
}

/// isolate 侧的章节解析入口：正文与这本书在本章生效的样式表一次传入。
///
/// `compute` 只能带一个位置参数，所以入参是一条 record，返回也带上出参 anchors：
/// 跨 isolate 不整体打包的话，大章走 isolate 时锚点会静默丢失，跳回旧算法的偏移口径。
({List<ContentBlock> blocks, Map<String, int> anchors}) parseChapterPayload(
  ({String html, String css}) chapter,
) {
  final anchors = <String, int>{};
  return (
    blocks: parseBlocks(chapter.html, anchors: anchors, css: chapter.css),
    anchors: anchors,
  );
}

/// 解析 HTML 为内容块列表。
///
/// 使用 DOM 解析器替代正则，正确处理嵌套标签、
/// 畸形 HTML 和 HTML 实体。
///
/// [anchors] 非空时，把章内锚点（`id` / `name`）在字符域里的位置写进去，
/// 供跳转使用同一个偏移口径。
///
/// [css] 是这本书在本章生效的外部样式表全文，由调用方按**本章的次序**拼好传入：
/// EPUB 的样式表不再随正文流动，改为书级池 + 章节次序引用（见 `_authorCssText`）。
List<ContentBlock> parseBlocks(
  String html, {
  Map<String, int>? anchors,
  String css = '',
}) {
  if (html.trim().isEmpty) return [];

  final document = html_parser.parse(html);
  final body = document.body;
  if (body == null) return [];

  final rawBlocks = <ContentBlock>[];
  final ctx = _ParseContext(
    BookStyleSheet.parse(_authorCssText(document, css)),
  );
  _walkNode(body, rawBlocks, _StyleContext(), ctx);
  anchors?.addAll(ctx.anchors);

  // 先把下一段的上边距折成前一段的尾间距，再合并连续段落块。
  // 顺序不能颠倒：合并以后"段与段之间"这一层就不存在了，top-margin 型的书
  // （靠上边距分段）会在合并块内部丢掉全部留白。
  final blocks = _mergeConsecutiveParagraphs(
    _foldParagraphTopMargins(rawBlocks),
  );
  return blocks;
}

/// 把下一段的上外边距折进前一段的尾间距，口径同 CSS 的相邻兄弟外边距折叠。
///
/// 阅读器只花"块尾间距"这一份额度（前间距会让同一处被上下两块各算一遍），所以
/// 折算发生在解析期：段距 = max(自身 margin-bottom, 下一段 margin-top)。
/// 作用范围是扁平化后的相邻块——跨父级的相邻在规范里还受父级边距影响，这里按同
/// 一规则近似，最坏是多给一点这本书自己索要的留白。
List<ContentBlock> _foldParagraphTopMargins(List<ContentBlock> blocks) {
  final hasLeading = blocks.any(
    (block) =>
        block is ParagraphBlock && (block.style?.topMarginScale ?? 0) > 0,
  );
  if (!hasLeading) return blocks;

  final result = <ContentBlock>[];
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    if (block is! ParagraphBlock || block.style == null) {
      result.add(block);
      continue;
    }
    final style = block.style!;
    // XHTML 源码里段落之间的缩进空白也会被切成段落块，它们在合并时被丢掉、
    // 不构成兄弟之间的隔断，查"下一段"时必须跳过，否则上边距永远找不到归属。
    var nextIndex = i + 1;
    while (nextIndex < blocks.length &&
        _isBlankParagraphBlock(blocks[nextIndex])) {
      nextIndex++;
    }
    final next = nextIndex < blocks.length ? blocks[nextIndex] : null;
    final leading = next is ParagraphBlock ? next.style?.topMarginScale : null;
    final trailing = style.paragraphSpacingScale;
    var spacing =
        leading == null
            ? trailing
            : trailing == null
            ? leading
            : (trailing > leading ? trailing : leading);
    // 序列里第一个段落没有前置兄弟来代收它的上边距（紧跟标题、分隔线之后的那一段
    // 同理）：折叠规则在这里退化成自己交给自己，否则这一段之前的留白凭空消失。
    final ownTop = style.topMarginScale;
    if (ownTop != null && !_hasPrecedingParagraph(blocks, i)) {
      spacing = spacing == null || ownTop > spacing ? ownTop : spacing;
    }
    if (spacing == trailing) {
      result.add(block);
      continue;
    }
    final folded = ParagraphStyleSpec(
      firstLineIndentChars: style.firstLineIndentChars,
      paragraphSpacingScale: spacing,
      lineHeightScale: style.lineHeightScale,
      textAlign: style.textAlign,
    );
    result.add(
      ParagraphBlock(
        // 行上的样式只更新块级那两份：缩进要保留这一行自己登记过的值（样式表没写、
        // 源文本用全角空格写的那一格），而 `topMarginScale` 必须继续留空——
        // 前间距已经折进这一段自己的尾间距，行上再带一份会被合并块当成本段的表达，
        // 相邻两段就各扣一次。
        lines: [
          for (final line in block.lines)
            line.withStyle(
              ParagraphStyleSpec(
                firstLineIndentChars:
                    style.firstLineIndentChars ??
                    line.style?.firstLineIndentChars,
                paragraphSpacingScale: spacing,
                // 空行留白要原样带过去：合并阶段才把它转记成块尾段距，
                // 这里漏掉的话靠 margin-top 分段的书同时失去两种留白。
                paragraphBlankGapLines: line.style?.paragraphBlankGapLines,
                lineHeightScale:
                    style.lineHeightScale ?? line.style?.lineHeightScale,
                textAlign: style.textAlign,
              ),
            ),
        ],
        hasTrailingSpacing: block.hasTrailingSpacing,
        style: folded,
      ),
    );
  }
  return result;
}

/// [blocks] 里第 [index] 个段落之前是否已经有一个段落块。
///
/// 只算段落：标题与分隔线在版面上把上一段隔开了，它们之后的第一段必须自己交出
/// 上边距。空白段落块（只有缩进空格的假段）会在合并时被丢掉，不构成隔断。
bool _hasPrecedingParagraph(List<ContentBlock> blocks, int index) {
  for (var i = index - 1; i >= 0; i--) {
    final block = blocks[i];
    if (_isBlankParagraphBlock(block)) {
      continue;
    }
    if (block is ParagraphBlock) {
      return true;
    }
    if (block is HeadingBlock || block is DividerBlock) {
      return false;
    }
  }
  return false;
}

/// 按「样式表明写 > 源文本字面 > 分段机制推断」的次序补齐缩进。
///
/// 第三档只补一种情况：这本书给段落要了留白（`margin-bottom` 或 `margin-top`），
/// 却在元素自己到根的链上从头到尾没写过 `text-indent` —— 那是"顶格 + 段距"的版式，
/// 浏览器里它的 `text-indent` 计算值就是 0（CSS 2.1 的 initial 值）。果麦那一类书整本
/// 都是这型：开关打开后若仍由阅读器补两个字，就成了"又缩进又留白"的双重分段，两头都不像。
/// 书连样式表都没提供时不推断——那本书对排版什么都没说，交给阅读器默认档。
///
/// 只在跟随档被采纳（`ReaderViewSettings.firstLineIndentChars` 把关），关闭档一寸不动。
ParagraphStyleSpec? _withSpacingInferredIndent(ParagraphStyleSpec? style) {
  if (style == null || style.firstLineIndentChars != null) return style;
  final separatesBySpacing =
      (style.paragraphSpacingScale ?? 0) > 0 || (style.topMarginScale ?? 0) > 0;
  if (!separatesBySpacing) return style;
  return ParagraphStyleSpec(
    firstLineIndentChars: 0,
    paragraphSpacingScale: style.paragraphSpacingScale,
    topMarginScale: style.topMarginScale,
    lineHeightScale: style.lineHeightScale,
    textAlign: style.textAlign,
  );
}

/// 把"后一段之前的空白行数"转记成这一块自己的尾留白。
///
/// 始终以传入值为准（包括传 0 表示没有留白）：块样式取自首行的样式，而首行那份
/// `paragraphBlankGapLines` 描述的是**这一段之前**的白，留着它就成了这一段的段后距。
ParagraphStyleSpec? _withTrailingBlankGap(
  ParagraphStyleSpec? style,
  int gapLines,
) {
  final gap = gapLines > 0 ? gapLines : null;
  if (style == null) {
    return gap == null ? null : ParagraphStyleSpec(paragraphBlankGapLines: gap);
  }
  if (style.paragraphBlankGapLines == gap) return style;
  return ParagraphStyleSpec(
    firstLineIndentChars: style.firstLineIndentChars,
    paragraphSpacingScale: style.paragraphSpacingScale,
    topMarginScale: style.topMarginScale,
    paragraphBlankGapLines: gap,
    lineHeightScale: style.lineHeightScale,
    textAlign: style.textAlign,
  );
}

/// 收集这份文档的作者样式表：文档内联的 `<style>` 在前，[external] 拼在最后。
///
/// 顺序就是层叠的源序，不能反。书的内联 `<style>` 基本都写在 head，外部表由同一份
/// head 里的 `<link>` 引用、按引用点生效，于是同特异度的冲突规则由外部表胜出；
/// 反过来拼会让外部表输给章节自己的一份内联声明。
/// `<style>` 的文本不会进正文（见 `_isNonContentTag`），在这里只作为层叠的作者段使用。
String _authorCssText(dom.Document document, String external) {
  final buffer = StringBuffer();
  for (final node in document.querySelectorAll('style')) {
    buffer
      ..write(node.text)
      ..write('\n');
  }
  if (external.isNotEmpty) {
    buffer
      ..write(external)
      ..write('\n');
  }
  return buffer.toString();
}

// ── 段落合并 ──

/// 合并连续的 ParagraphBlock 为单个块。
///
/// 中文排版靠首行缩进区分段落，不需要段落间换行或间距。
/// 合并后所有行在同一个 Text.rich 中渲染，消除 Column 布局产生的自然换行。
/// 判断行是否只包含空白字符（空格、换行、制表符等）。
bool _isBlankLine(LineData line) {
  if (line.spans.isEmpty) return true;
  final text = line.spans.map((s) => s.text).join();
  return text.trim().isEmpty;
}

/// 整块都是空白（源码缩进、段间换行）的段落块：合并时会被丢掉，也不构成兄弟块之间的隔断。
bool _isBlankParagraphBlock(ContentBlock block) =>
    block is ParagraphBlock &&
    (block.lines.isEmpty || block.lines.every(_isBlankLine));

/// 合并段落块的分块上限：行数与字符数双阈值，先到先切。
///
/// 段落合并会把连续段落压进单个 TextPainter 才能消除 Column 的行间空隙；
/// 不设上限时整章会退化为一个块，测高与分页的所有分批防线同时失效。
const _maxMergedParagraphLines = 48;
const _maxMergedParagraphChars = 4000;

/// 硬上限：只允许在自然段落边界切块，但一段连排到底也不能无限增长。
///
/// 软换行续行之间切块会产生一次真实的控件边界（表现为短行），
/// 所以优先在段首切；超过硬上限时才不顾段落边界强行切块。
const _hardMergedParagraphLines = 120;
const _hardMergedParagraphChars = 10000;

List<ContentBlock> _mergeConsecutiveParagraphs(List<ContentBlock> blocks) {
  final result = <ContentBlock>[];
  final pendingLines = <LineData>[];
  var pendingTrailingSpacing = false;
  var pendingTrailingGapLines = 0;
  var pendingChars = 0;
  ParagraphStyleSpec? pendingStyle;

  void flushPending() {
    if (pendingLines.isEmpty) {
      // 没有正文块可挂这份留白（章首就是空行的那一型）：丢掉。块与块之间才有段距，
      // 章首留白既没有前一块可记，也不该把第一行推下去。
      pendingTrailingGapLines = 0;
      return;
    }
    result.add(
      ParagraphBlock(
        lines: List<LineData>.of(pendingLines),
        hasTrailingSpacing: pendingTrailingSpacing,
        style: _withTrailingBlankGap(pendingStyle, pendingTrailingGapLines),
      ),
    );
    pendingLines.clear();
    pendingTrailingSpacing = false;
    pendingTrailingGapLines = 0;
    pendingChars = 0;
    pendingStyle = null;
  }

  for (final block in blocks) {
    if (block is! ParagraphBlock) {
      flushPending();
      result.add(block);
      continue;
    }
    // 任一被合并块带段距即保留，避免 <br><br> 产生的段距被吞。
    pendingTrailingSpacing = pendingTrailingSpacing || block.hasTrailingSpacing;
    var carriedCollapsed = 0;
    for (final line in block.lines) {
      if (_isBlankLine(line)) {
        // 空白行不产出，但其源字符必须结转给下一个有效行，
        // 否则块的字符总数小于源文本长度，charOffset 与页裁剪会落到不同空间。
        carriedCollapsed += line.sourceChars;
        continue;
      }
      final lineChars = line.sourceChars;
      final overSoftLimit =
          pendingLines.length >= _maxMergedParagraphLines ||
          pendingChars + lineChars > _maxMergedParagraphChars;
      final overHardLimit =
          pendingLines.length >= _hardMergedParagraphLines ||
          pendingChars + lineChars > _hardMergedParagraphChars;
      // 段距与对齐是块级的：两个段落各自表达不同时不能塞进同一块，否则后一个
      // 段落的前间距与前一个的对齐都会被首段的值抹平。
      final differentBlockLayout =
          !ParagraphStyleSpec.sameBlockLayout(pendingStyle, line.style);
      // 书真的用段距分段时，段落必须各自成块：块内的行距只是排版折行，不是书的
      // 留白，合并会把整章的段距抹成块尾的一次。
      final spacingKeepsParagraphsApart =
          line.isNewParagraph && (pendingStyle?.paragraphSpacingScale ?? 0) > 0;
      // 作者用空行分段：这一段之前的空白属于**前一段之后**的那一份留白，口径与
      // `margin-top` 的折算一致（额度只花一次）。块内的行距只是排版折行，表达不了
      // 它，所以在这里切块并把行数转记给前一块。
      final blankGapLines = line.style?.paragraphBlankGapLines ?? 0;
      final gapKeepsParagraphsApart =
          blankGapLines > 0 && pendingLines.isNotEmpty;
      if (gapKeepsParagraphsApart) {
        pendingTrailingGapLines = blankGapLines;
      }
      if (pendingLines.isNotEmpty &&
          (overHardLimit ||
              differentBlockLayout ||
              spacingKeepsParagraphsApart ||
              gapKeepsParagraphsApart ||
              (overSoftLimit && !line.softWrap))) {
        flushPending();
      }
      // 新块首行不再标记新段落，由渲染端按首行缩进处理；
      // 软换行续行带着 softWrap 进新块也不会被补出缩进。
      pendingLines.add(
        LineData(
          spans: line.spans,
          isNewParagraph: pendingLines.isNotEmpty,
          collapsedChars: line.collapsedChars + carriedCollapsed,
          trailingCollapsedChars: line.trailingCollapsedChars,
          softWrap: line.softWrap,
          style: line.style,
        ),
      );
      pendingStyle ??= line.style;
      carriedCollapsed = 0;
      pendingChars += lineChars;
    }
  }
  flushPending();
  return result;
}

// ── 块级元素集合 ──

const _blockElements = {
  'p',
  'div',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'ul',
  'ol',
  'table',
  'pre',
  'hr',
  'img',
  'figure',
  'figcaption',
  'section',
  'article',
  'main',
  'header',
  'footer',
  'nav',
  'aside',
};

/// 取标题内第一张内联图的 `alt`：纯图片标题没有文字，`alt` 是它唯一的可读语义。
String _headingImageAlt(dom.Element element) {
  for (final image in element.getElementsByTagName('img')) {
    final alt = image.attributes['alt']?.trim() ?? '';
    if (alt.isNotEmpty) {
      return alt;
    }
  }
  return '';
}

/// 把标题内的图片按文档顺序落成 [ImageBlock]。
///
/// 卷首艺术字标题整块只有一张图，连标题块一起丢弃等于把图也丢了。
void _collectHeadingImages(dom.Element element, List<ContentBlock> blocks) {
  for (final image in element.getElementsByTagName('img')) {
    final src = image.attributes['src'];
    if (src != null && src.isNotEmpty) {
      blocks.add(ImageBlock(src: src, alt: image.attributes['alt']));
    }
  }
}

bool _isBlockTag(String? tag) => _blockElements.contains(tag);

/// 非正文元素：它们的文本子节点是样式表、脚本源码或元数据，不是可读内容。
///
/// 正文 XHTML 里带内联 `<style>` 很常见（部分转换工具把每章的样式写进 body），
/// 不跳过会把 CSS 源码当正文渲染出来，还会白占字符偏移，把书签与标注推歪。
const _nonContentElements = {
  'style',
  'script',
  'head',
  'title',
  'noscript',
  'template',
};

bool _isNonContentTag(String? tag) => _nonContentElements.contains(tag);

/// 块级与内联递归的最大深度；畸形 EPUB 的超深嵌套折叠为纯文本，
/// 防止解析期栈溢出。
const _maxHtmlParseDepth = 64;

// ── 节点遍历 ──

/// 递归遍历 DOM 节点的子节点，将块级元素转为 [ContentBlock]。
///
/// 裸露的文本和内联元素被收集为临时段落，
/// 遇到块级元素时先刷新这些临时内容。
void _walkNode(
  dom.Node node,
  List<ContentBlock> blocks,
  _StyleContext style,
  _ParseContext ctx, [
  int depth = 0,
]) {
  if (depth > _maxHtmlParseDepth) {
    // 超深块级嵌套折叠为纯文本段落
    final text = _collectText(node).trim();
    if (text.isNotEmpty) {
      blocks.add(
        ParagraphBlock(
          lines: [
            LineData(
              spans: [ReaderInlineSpan(text: text, startOffset: ctx.offset)],
            ),
          ],
        ),
      );
      ctx.offset += text.length;
    }
    return;
  }
  final buffer = <ReaderInlineSpan>[];

  /// 容器自己（含祖先继承）表达过的排版意图，裸文本就落在这个块盒里。
  ///
  /// `<p>` 走 `_processParagraph` 取样式，这一条通路不取的话，全书正文都写成
  /// `<div>甲\n\n乙</div>` 的书（PG 与 Kindle 导出的裸文本形状）就把书的表达
  /// 整份丢掉，读者看到的内容与关掉开关一模一样。
  final containerStyle = node is dom.Element ? ctx.styles.styleFor(node) : null;

  /// 容器里的文本被段内 `<img>` 断开过：后半截是同一段的续行，不补首行缩进。
  var isSplitContinuation = false;

  void flushBufferAsParagraph() {
    if (buffer.isEmpty) return;
    final spans = List.of(buffer);
    buffer.clear();
    // 与 `<p>` 共用同一条折叠规则：容器直属的裸文本也带着源码里的硬换行
    // （PG 语料的许可页就是 `<div>` 里每约 35 字断行的一段），不折就把
    // HTML 的空格规范化当排版换行用，一行只剩十几个字符。
    final (lines, residue) = _foldIntoLines(
      spans,
      firstLineIsNewParagraph: true,
    );
    if (residue > 0) {
      // 整段只有空白：没有行可挂折叠量，退账并放弃这个块 —— 旧写法会产出一个
      // 零行的 ParagraphBlock，字符一格不收，却照样占一份段距。
      ctx.offset -= residue;
    }
    if (lines.isEmpty) return;
    var styled = <LineData>[
      for (final line in lines)
        line.withStyle(_withSpacingInferredIndent(containerStyle)),
    ];
    if (isSplitContinuation) {
      styled = _markLeadingLineContinuation(styled);
      isSplitContinuation = false;
    }
    blocks.add(ParagraphBlock(lines: styled, style: containerStyle));
  }

  /// 内联上下文里遇到 `<img>`：按文档顺序在此断开，图自己成一个零字符块。
  void splitAtImage(String src, String? alt) {
    flushBufferAsParagraph();
    blocks.add(ImageBlock(src: src, alt: alt));
    isSplitContinuation = true;
  }

  /// 容器里遇到 `<br>`：断开当前段，后半截是同一段的续行，不补首行缩进。
  /// 缓冲区为空时什么都不做，否则前导 `<br>` 会把下一段的缩进也吞掉。
  void splitAtBreak() {
    if (buffer.isEmpty) {
      return;
    }
    flushBufferAsParagraph();
    isSplitContinuation = true;
  }

  for (final child in node.nodes) {
    if (child is dom.Text) {
      _collectInlineSpans(
        child,
        buffer,
        style,
        ctx,
        depth: depth + 1,
        onImage: splitAtImage,
      );
    } else if (child is dom.Element) {
      final tag = child.localName;
      if (_isNonContentTag(tag)) {
        continue;
      }
      if (_isBlockTag(tag)) {
        flushBufferAsParagraph();
        _processBlock(child, blocks, style, ctx, depth + 1);
        // `<div>甲<img/>乙</div>`：乙仍是同一段的后半截。
        if (tag == 'img') isSplitContinuation = true;
      } else if (tag == 'br') {
        // 容器直属的裸 br 与 `<p>` 内的 br 同权：断行，不能吞掉。
        splitAtBreak();
      } else {
        // 内联包装元素（span/em 等）里嵌套的 `<img>` 由 `onImage` 就地断开，
        // 不再先整批提到段前（旧写法会让句子中间的插图跑到句子前面）。
        _collectInlineSpans(
          child,
          buffer,
          style,
          ctx,
          depth: depth + 1,
          onBr: splitAtBreak,
          onImage: splitAtImage,
        );
      }
    }
  }

  flushBufferAsParagraph();
}

// ── 块级元素处理分发 ──

/// 处理单个块级元素，生成对应的 [ContentBlock]。
void _processBlock(
  dom.Element element,
  List<ContentBlock> blocks,
  _StyleContext style,
  _ParseContext ctx, [
  int depth = 0,
]) {
  final tag = element.localName ?? '';
  if (_isNonContentTag(tag)) {
    return;
  }
  ctx.noteAnchor(element);

  switch (tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      final level = int.tryParse(tag.substring(1)) ?? 2;
      final text = _collectText(element).trim();
      // 只取对齐：白名单里的缩进与段距对标题没有落点（标题条目按固定档位画），
      // 居中却是中文书页码最常见的标题版式，不取就等于开关对标题无效。
      final align = ctx.styles.styleFor(element)?.textAlign;
      if (text.isEmpty) {
        // 卷首艺术字标题（`<h1 class="..."><img/></h1>`）与只做目录跳转的空锚点
        // （`<h1 id="ch1"></h1>`）都没有文字：整块丢掉会让标题层级与锚点一起消失，
        // 图也跟着落不进块列表。这里保留标题块（有 alt 就用 alt 顶位），
        // 并把内联图片按原顺序落块。
        final alt = _headingImageAlt(element);
        blocks.add(
          HeadingBlock(
            text: alt,
            level: level,
            startOffset: ctx.offset,
            align: align,
          ),
        );
        ctx.offset += alt.length;
        _collectHeadingImages(element, blocks);
        break;
      }
      blocks.add(
        HeadingBlock(
          text: text,
          level: level,
          startOffset: ctx.offset,
          align: align,
        ),
      );
      ctx.offset += text.length;

    case 'p':
      _processParagraph(element, blocks, style, ctx);

    case 'div':
      // <div> 可以包含块级子元素，递归遍历而非当段落处理
      _walkNode(element, blocks, style, ctx, depth + 1);

    case 'img':
      final src = element.attributes['src'];
      if (src != null && src.isNotEmpty) {
        blocks.add(ImageBlock(src: src, alt: element.attributes['alt']));
      }

    case 'figure':
      _processFigure(element, blocks);

    case 'figcaption':
      final captionText = _collectText(element).trim();
      if (captionText.isNotEmpty &&
          blocks.isNotEmpty &&
          blocks.last is ImageBlock) {
        final last = blocks.last as ImageBlock;
        blocks[blocks.length - 1] = ImageBlock(
          src: last.src,
          caption: captionText,
          alt: last.alt,
        );
      }

    case 'hr':
      // 分隔线在字符域里不占位（blockCharCount 为 0），游标也不能替它 advance：
      // 多出来的这 1 会让后面每个块的起点与分页前缀表逐块错开一格。
      blocks.add(DividerBlock());

    case 'blockquote':
      _processBlockquote(element, blocks, style, ctx);

    case 'ul':
    case 'ol':
      _processList(element, blocks, style, ctx);

    case 'table':
      _processTable(element, blocks, style, ctx);

    case 'pre':
      _processPre(element, blocks, ctx);

    default:
      // section, article, main 等 —— 递归子节点
      _walkNode(element, blocks, style, ctx, depth + 1);
  }
}

// ── 样式上下文 ──

/// 不可变的内联样式上下文，用于跟踪 DOM 遍历中的祖先样式。
class _StyleContext {
  const _StyleContext({
    this.isBold = false,
    this.isItalic = false,
    this.isHeading = false,
    this.href,
    this.isCode = false,
    this.isSuperscript = false,
    this.isSubscript = false,
    this.isMarked = false,
    this.isDeleted = false,
    this.isUnderlined = false,
  });

  final bool isBold;
  final bool isItalic;
  final bool isHeading;
  final String? href;
  final bool isCode;
  final bool isSuperscript;
  final bool isSubscript;
  final bool isMarked;
  final bool isDeleted;
  final bool isUnderlined;

  _StyleContext copyWith({
    bool? isBold,
    bool? isItalic,
    bool? isHeading,
    String? href,
    bool clearHref = false,
    bool? isCode,
    bool? isSuperscript,
    bool? isSubscript,
    bool? isMarked,
    bool? isDeleted,
    bool? isUnderlined,
  }) {
    return _StyleContext(
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isHeading: isHeading ?? this.isHeading,
      href: clearHref ? null : (href ?? this.href),
      isCode: isCode ?? this.isCode,
      isSuperscript: isSuperscript ?? this.isSuperscript,
      isSubscript: isSubscript ?? this.isSubscript,
      isMarked: isMarked ?? this.isMarked,
      isDeleted: isDeleted ?? this.isDeleted,
      isUnderlined: isUnderlined ?? this.isUnderlined,
    );
  }
}
