import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';

export 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
export 'package:omninest/features/reader/presentation/widgets/reader_html_text.dart';

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
  int offset = 0;
}

/// 解析 HTML 为内容块列表。
///
/// 使用 DOM 解析器替代正则，正确处理嵌套标签、
/// 畸形 HTML 和 HTML 实体。
List<ContentBlock> parseBlocks(String html) {
  if (html.trim().isEmpty) return [];

  final document = html_parser.parse(html);
  final body = document.body;
  if (body == null) return [];

  final rawBlocks = <ContentBlock>[];
  final ctx = _ParseContext();
  _walkNode(body, rawBlocks, _StyleContext(), ctx);

  // 合并连续段落块为单个块，消除段落间换行。
  // 中文排版靠首行缩进区分段落，不需要额外间距。
  final blocks = _mergeConsecutiveParagraphs(rawBlocks);
  return blocks;
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

List<ContentBlock> _mergeConsecutiveParagraphs(List<ContentBlock> blocks) {
  final result = <ContentBlock>[];
  ParagraphBlock? pending;

  for (final block in blocks) {
    if (block is ParagraphBlock) {
      if (pending != null) {
        // 合并到前一个段落
        final mergedLines = [...pending.lines];
        // 移除前一段落的尾部空白行
        while (mergedLines.isNotEmpty && _isBlankLine(mergedLines.last)) {
          mergedLines.removeLast();
        }
        for (final line in block.lines) {
          // 跳过空白行
          if (_isBlankLine(line)) continue;
          mergedLines.add(LineData(spans: line.spans, isNewParagraph: true));
        }
        pending = ParagraphBlock(
          lines: mergedLines,
          // 任一被合并块带段距即保留，避免 <br><br> 产生的段距被吞
          hasTrailingSpacing:
              pending.hasTrailingSpacing || block.hasTrailingSpacing,
        );
      } else {
        // 单个段落块：过滤内部空白行，标记新段落
        final cleanedLines = <LineData>[];
        for (final line in block.lines) {
          // 跳过空白行
          if (_isBlankLine(line)) continue;
          cleanedLines.add(
            LineData(
              spans: line.spans,
              isNewParagraph: cleanedLines.isNotEmpty,
            ),
          );
        }
        pending = ParagraphBlock(
          lines: cleanedLines,
          hasTrailingSpacing: block.hasTrailingSpacing,
        );
      }
    } else {
      if (pending != null) {
        result.add(pending);
        pending = null;
      }
      result.add(block);
    }
  }
  if (pending != null) result.add(pending);
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

bool _isBlockTag(String? tag) => _blockElements.contains(tag);

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
      ctx.offset += text.length + 1;
    }
    return;
  }
  final buffer = <ReaderInlineSpan>[];

  void flushBufferAsParagraph() {
    if (buffer.isEmpty) return;
    blocks.add(ParagraphBlock(lines: [LineData(spans: List.of(buffer))]));
    buffer.clear();
  }

  for (final child in node.nodes) {
    if (child is dom.Text) {
      _collectInlineSpans(child, buffer, style, ctx, depth + 1);
    } else if (child is dom.Element) {
      final tag = child.localName;
      if (_isBlockTag(tag)) {
        flushBufferAsParagraph();
        _processBlock(child, blocks, style, ctx, depth + 1);
      } else if (tag == 'br') {
        // 裸 br 跳过（等价于正则解析器的非段落上下文行为）
      } else {
        // 内联上下文中嵌套的 <img> 升级为独立图片块，原实现静默丢弃
        final images =
            tag == 'img' ? <dom.Element>[child] : child.querySelectorAll('img');
        for (final img in images) {
          final src = img.attributes['src'];
          if (src == null || src.isEmpty) continue;
          flushBufferAsParagraph();
          blocks.add(ImageBlock(src: src, alt: img.attributes['alt']));
        }
        _collectInlineSpans(child, buffer, style, ctx, depth + 1);
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

  switch (tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      final level = int.tryParse(tag.substring(1)) ?? 2;
      final text = _collectText(element).trim();
      if (text.isNotEmpty) {
        blocks.add(
          HeadingBlock(text: text, level: level, startOffset: ctx.offset),
        );
        ctx.offset += text.length + 1;
      }

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
      blocks.add(DividerBlock());
      ctx.offset += 1;

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

// ── 段落处理 ──

/// 处理 `<p>` / `<div>` 元素，遍历子节点处理 `<br>` 分行。
void _processParagraph(
  dom.Element element,
  List<ContentBlock> blocks,
  _StyleContext style,
  _ParseContext ctx,
) {
  final lines = <LineData>[];
  final currentSpans = <ReaderInlineSpan>[];
  var consecutiveBreaks = 0;
  var prevWasBr = false;

  /// 将当前累积的 spans 和 lines 刷新为一个 ParagraphBlock。
  void flushParagraph() {
    if (currentSpans.isNotEmpty) {
      lines.add(LineData(spans: List.of(currentSpans)));
      currentSpans.clear();
    }
    if (lines.isNotEmpty) {
      blocks.add(
        ParagraphBlock(
          lines: List.of(lines),
          hasTrailingSpacing: consecutiveBreaks >= 2,
        ),
      );
      lines.clear();
      if (consecutiveBreaks > 0) ctx.offset += 1;
      consecutiveBreaks = 0;
    }
    prevWasBr = false;
  }

  // 预遍历子节点，遇到 <img> 时刷新段落并创建 ImageBlock。
  // 内联包装元素（span/em 等）内部嵌套的 <img> 同样要提升为独立图片
  // 块，否则会被 _walkInlineChildren 静默丢弃（方案 §34 双消费/零消费
  // 防御：一个 DOM img 节点在段落上下文中只由此预遍历消费一次）。
  for (final child in element.nodes) {
    if (child is! dom.Element) continue;
    final imgs =
        child.localName == 'img'
            ? <dom.Element>[child]
            : child.querySelectorAll('img');
    for (final img in imgs) {
      flushParagraph();
      final src = img.attributes['src'];
      if (src != null && src.isNotEmpty) {
        blocks.add(ImageBlock(src: src, alt: img.attributes['alt']));
      }
    }
  }

  _walkInlineChildren(
    element,
    currentSpans,
    style,
    ctx,
    onBr: () {
      if (currentSpans.isNotEmpty) {
        lines.add(LineData(spans: List.of(currentSpans)));
        currentSpans.clear();
        prevWasBr = false;
      }
      if (prevWasBr) {
        // 连续空 <br>，跳过（A<br><br>B 中第二个 <br>）
        ctx.offset += 1;
        return;
      }
      lines.add(const LineData(spans: []));
      prevWasBr = true;
      consecutiveBreaks++;
      ctx.offset += 1;
    },
    onText: () {
      prevWasBr = false;
    },
  );

  // 最后的残余 spans
  if (currentSpans.isNotEmpty) {
    lines.add(LineData(spans: List.of(currentSpans)));
  }

  if (lines.isNotEmpty) {
    blocks.add(
      ParagraphBlock(
        lines: List.of(lines),
        hasTrailingSpacing: consecutiveBreaks >= 2,
      ),
    );
    if (consecutiveBreaks > 0) {
      ctx.offset += 1;
    }
  }
}

// ── Blockquote 处理 ──

/// 处理 `<blockquote>` 元素，将子内容转为 [LineData] 列表。
///
/// 块级子元素（p, h1-h6）被转为行，
/// 内联元素和文本被收集为行。
void _processBlockquote(
  dom.Element element,
  List<ContentBlock> blocks,
  _StyleContext style,
  _ParseContext ctx,
) {
  final bqLines = <LineData>[];
  final currentSpans = <ReaderInlineSpan>[];

  for (final child in element.nodes) {
    if (child is dom.Element) {
      final tag = child.localName ?? '';
      if (tag == 'p' || tag == 'div') {
        // 段落内容作为一行
        if (currentSpans.isNotEmpty) {
          bqLines.add(LineData(spans: List.of(currentSpans)));
          currentSpans.clear();
        }
        _walkInlineChildren(
          child,
          currentSpans,
          style,
          ctx,
          onBr: () {
            if (currentSpans.isNotEmpty) {
              bqLines.add(LineData(spans: List.of(currentSpans)));
              currentSpans.clear();
            }
            ctx.offset += 1;
          },
        );
        if (currentSpans.isNotEmpty) {
          bqLines.add(LineData(spans: List.of(currentSpans)));
          currentSpans.clear();
        }
      } else if (_isHeadingTag(tag)) {
        // heading 在 blockquote 内降级为加粗
        _collectInlineSpans(
          child,
          currentSpans,
          style.copyWith(isBold: true),
          ctx,
        );
      } else if (tag == 'br') {
        if (currentSpans.isNotEmpty) {
          bqLines.add(LineData(spans: List.of(currentSpans)));
          currentSpans.clear();
        }
        ctx.offset += 1;
      } else if (_isBlockTag(tag)) {
        // 其他块级元素 —— 递归提取文本
        _collectInlineSpans(child, currentSpans, style, ctx);
      } else {
        // 内联元素
        _collectInlineSpans(child, currentSpans, style, ctx);
      }
    } else if (child is dom.Text) {
      _collectInlineSpans(child, currentSpans, style, ctx);
    }
  }

  // 最后的残余
  if (currentSpans.isNotEmpty) {
    bqLines.add(LineData(spans: List.of(currentSpans)));
  }

  if (bqLines.isNotEmpty) {
    blocks.add(
      BlockquoteBlock(lines: List.of(bqLines), startOffset: ctx.offset),
    );
  }
}

bool _isHeadingTag(String tag) =>
    tag.length == 2 && tag[0] == 'h' && int.tryParse(tag[1]) != null;

// ── List 处理 ──

/// 处理 `<ul>` / `<ol>` 列表元素。
void _processList(
  dom.Element element,
  List<ContentBlock> blocks,
  _StyleContext style,
  _ParseContext ctx,
) {
  final isOrdered = element.localName == 'ol';
  final items = <ListItemData>[];

  for (final child in element.nodes) {
    if (child is dom.Element && child.localName == 'li') {
      _processListItem(child, items, style, ctx);
    }
  }

  if (items.isNotEmpty) {
    blocks.add(
      ListBlock(
        items: List.of(items),
        isOrdered: isOrdered,
        startOffset: ctx.offset,
      ),
    );
  }
}

/// 处理 `<li>` 列表项，支持嵌套列表。
///
/// 嵌套列表的子项会追加到当前 items 列表中，
/// 保持与正则解析器一致的扁平化行为。
void _processListItem(
  dom.Element element,
  List<ListItemData> items,
  _StyleContext style,
  _ParseContext ctx,
) {
  final spans = <ReaderInlineSpan>[];

  for (final child in element.nodes) {
    if (child is dom.Element) {
      final tag = child.localName;
      if (tag == 'ul' || tag == 'ol') {
        // 嵌套列表：先保存当前项，再递归处理子列表
        if (spans.isNotEmpty) {
          items.add(ListItemData(spans: List.of(spans)));
          spans.clear();
        }
        // 用临时 blocks 收集嵌套列表的 ListBlock
        final nestedBlocks = <ContentBlock>[];
        _processList(child, nestedBlocks, style, ctx);
        // 将嵌套列表块中的子项追加到当前 items
        for (final block in nestedBlocks) {
          if (block is ListBlock) {
            items.addAll(block.items);
          }
        }
      } else {
        _collectInlineSpans(child, spans, style, ctx);
      }
    } else if (child is dom.Text) {
      _collectInlineSpans(child, spans, style, ctx);
    }
  }

  // 空列表项也保留（序号正确性）
  items.add(ListItemData(spans: List.of(spans)));
}

// ── Table 处理 ──

/// 处理 `<table>` 元素。
void _processTable(
  dom.Element element,
  List<ContentBlock> blocks,
  _StyleContext style,
  _ParseContext ctx,
) {
  final rows = <TableRowData>[];
  _collectTableRows(element, rows, ctx);

  if (rows.isNotEmpty) {
    blocks.add(TableBlock(rows: List.of(rows), startOffset: ctx.offset));
  }
}

/// 递归收集表格行（处理 thead/tbody/tfoot）。
void _collectTableRows(
  dom.Element element,
  List<TableRowData> rows,
  _ParseContext ctx,
) {
  for (final child in element.nodes) {
    if (child is! dom.Element) continue;
    final tag = child.localName;
    if (tag == 'tr') {
      _processTableRow(child, rows, ctx);
    } else if (tag == 'thead' || tag == 'tbody' || tag == 'tfoot') {
      _collectTableRows(child, rows, ctx);
    }
  }
}

/// 处理 `<tr>` 表格行。
void _processTableRow(
  dom.Element element,
  List<TableRowData> rows,
  _ParseContext ctx,
) {
  final cells = <List<ReaderInlineSpan>>[];
  var isHeader = false;

  for (final child in element.nodes) {
    if (child is! dom.Element) continue;
    final tag = child.localName;
    if (tag == 'th' || tag == 'td') {
      if (tag == 'th') isHeader = true;
      final spans = <ReaderInlineSpan>[];
      _collectInlineSpans(child, spans, _StyleContext(), ctx);
      cells.add(List.of(spans));
    }
  }

  if (cells.isNotEmpty) {
    rows.add(TableRowData(cells: List.of(cells), isHeader: isHeader));
  }
}

// ── Pre 处理 ──

/// 处理 `<pre>` 预格式化文本。
void _processPre(
  dom.Element element,
  List<ContentBlock> blocks,
  _ParseContext ctx,
) {
  final text = _collectText(element);
  if (text.isNotEmpty) {
    final span = ReaderInlineSpan(
      text: text,
      isCode: true,
      startOffset: ctx.offset,
    );
    blocks.add(
      ParagraphBlock(
        lines: [
          LineData(spans: [span]),
        ],
      ),
    );
    ctx.offset += text.length;
  }
}

// ── Figure 处理 ──

/// 处理 `<figure>` 元素，提取图片和 figcaption。
void _processFigure(dom.Element element, List<ContentBlock> blocks) {
  for (final child in element.nodes) {
    if (child is! dom.Element) continue;
    if (child.localName == 'img') {
      final src = child.attributes['src'];
      if (src != null && src.isNotEmpty) {
        blocks.add(ImageBlock(src: src, alt: child.attributes['alt']));
      }
    } else if (child.localName == 'figcaption') {
      final captionText = _collectText(child).trim();
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
    }
  }
}

// ── 内联内容提取 ──

/// 遍历元素的子节点，提取内联 spans 并处理 `<br>` 分行。
///
/// [onBr] 回调在遇到 `<br>` 时调用，由调用者决定如何处理换行。
void _walkInlineChildren(
  dom.Element element,
  List<ReaderInlineSpan> currentSpans,
  _StyleContext style,
  _ParseContext ctx, {
  void Function()? onBr,
  void Function()? onText,
}) {
  for (final child in element.nodes) {
    if (child is dom.Text) {
      onText?.call();
      _collectInlineSpans(child, currentSpans, style, ctx);
    } else if (child is dom.Element) {
      final tag = child.localName;
      if (tag == 'br') {
        onBr?.call();
      } else if (_isBlockTag(tag)) {
        onText?.call();
        _collectInlineSpans(child, currentSpans, style, ctx);
      } else {
        onText?.call();
        _collectInlineSpans(child, currentSpans, style, ctx);
      }
    }
  }
}

/// 递归提取节点的内联文本 spans。
///
/// 根据祖先元素跟踪样式（粗体、斜体、链接等），
/// 为每个文本片段创建 [ReaderInlineSpan]。
///
/// 空白文本节点在两个内联元素之间时保留为一个空格，
/// 避免单词合并（如 `<span>A</span> <span>B</span>` → "A B"）。
void _collectInlineSpans(
  dom.Node node,
  List<ReaderInlineSpan> spans,
  _StyleContext style,
  _ParseContext ctx, [
  int depth = 0,
]) {
  if (node is dom.Text) {
    final text = _sanitizeText(node.text);
    if (text.trim().isNotEmpty) {
      spans.add(
        ReaderInlineSpan(
          text: text,
          isBold: style.isBold,
          isItalic: style.isItalic,
          isHeading: style.isHeading,
          href: style.href,
          isCode: style.isCode,
          startOffset: ctx.offset,
          isSuperscript: style.isSuperscript,
          isSubscript: style.isSubscript,
          isMarked: style.isMarked,
          isDeleted: style.isDeleted,
          isUnderlined: style.isUnderlined,
        ),
      );
      ctx.offset += text.length;
    } else if (text.contains(' ') ||
        text.contains('\n') ||
        text.contains('\t')) {
      // 空白文本节点：折叠为单个空格，保留单词间距
      spans.add(
        ReaderInlineSpan(
          text: ' ',
          isBold: style.isBold,
          isItalic: style.isItalic,
          isHeading: style.isHeading,
          href: style.href,
          isCode: style.isCode,
          startOffset: ctx.offset,
        ),
      );
      ctx.offset += 1;
    }
    return;
  }

  if (node is! dom.Element) return;
  final tag = node.localName ?? '';
  if (depth > _maxHtmlParseDepth) {
    // 超深内联嵌套折叠为纯文本 span
    final text = _sanitizeText(_collectText(node));
    if (text.trim().isNotEmpty) {
      spans.add(
        ReaderInlineSpan(
          text: text,
          isBold: style.isBold,
          isItalic: style.isItalic,
          href: style.href,
          startOffset: ctx.offset,
        ),
      );
      ctx.offset += text.length;
    }
    return;
  }

  switch (tag) {
    case 'br':
      // 内联 br —— 跳过（由上层 _walkInlineChildren 处理）
      break;

    case 'b':
    case 'strong':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isBold: true),
          ctx,
          depth + 1,
        );
      }

    case 'i':
    case 'em':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isItalic: true),
          ctx,
          depth + 1,
        );
      }

    case 'a':
      final href = node.attributes['href'];
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(href: href),
          ctx,
          depth + 1,
        );
      }

    case 'code':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isCode: true),
          ctx,
          depth + 1,
        );
      }

    case 'sup':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isSuperscript: true),
          ctx,
          depth + 1,
        );
      }

    case 'sub':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isSubscript: true),
          ctx,
          depth + 1,
        );
      }

    case 'mark':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isMarked: true),
          ctx,
          depth + 1,
        );
      }

    case 'del':
    case 's':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isDeleted: true),
          ctx,
          depth + 1,
        );
      }

    case 'u':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isUnderlined: true),
          ctx,
          depth + 1,
        );
      }

    default:
      // span, abbr, cite, q, small 等 —— 递归处理子节点
      for (final child in node.nodes) {
        _collectInlineSpans(child, spans, style, ctx, depth + 1);
      }
  }
}

// ── 文本收集 ──

/// 递归收集节点及其后代中的所有文本。
String _collectText(dom.Node node) {
  final buffer = StringBuffer();
  _collectTextRecursive(node, buffer);
  return buffer.toString();
}

void _collectTextRecursive(dom.Node node, StringBuffer buffer) {
  if (node is dom.Text) {
    buffer.write(_sanitizeText(node.text));
  } else if (node is dom.Element) {
    if (node.localName == 'br') {
      buffer.write('\n');
    }
    for (final child in node.nodes) {
      _collectTextRecursive(child, buffer);
    }
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
