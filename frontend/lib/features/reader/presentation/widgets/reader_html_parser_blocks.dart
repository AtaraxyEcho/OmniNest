part of 'reader_html_parser.dart';

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
  var prevWasBr = false;

  /// 这个 `<p>` 在书自己的样式表里表达过的排版意图；null 表示书没说。
  final bookStyle = ctx.styles.styleFor(element);

  /// 段内是否出现过相邻的两个 `<br>`，即作者真正留出的空行。
  ///
  /// 旧实现累计段内所有 `<br>`（被文本隔开也算），导致 `A<br>B<br>C`
  /// 这种诗节行拿到段前间距，而 `A<br><br>B` 的空行反而在合并阶段被丢弃。
  var sawAdjacentBreaks = false;

  /// 硬换行边界（`<br>`）造成的、要计入下一行折叠量的源字符数。
  var pendingCollapsed = 0;

  /// 段内被 `<img>` 断开过文本：紧随其后的片段是**同一段的续行**，
  /// 不补换行也不补首行缩进（浏览器里图前后本来就是同一行）。
  var isSplitContinuation = false;

  /// 把已累积的 spans 折成逻辑行追加到 lines。
  void pushSpansAsLines() {
    if (currentSpans.isEmpty) {
      return;
    }
    final spans = List<ReaderInlineSpan>.of(currentSpans);
    currentSpans.clear();
    final (folded, residue) = _foldIntoLines(
      spans,
      firstLineIsNewParagraph: lines.isEmpty,
      carriedCollapsed: pendingCollapsed,
    );
    lines.addAll(folded);
    // 一行都没折出来（整段空白）：这些源字符既不在可绘制文本里，也没有行首折叠量
    // 可挂，只能把游标退回去，让块字符记账与 `ctx.offset` 停在同一个域。
    if (residue > 0) ctx.offset -= residue;
    pendingCollapsed = 0;
  }

  /// 将当前累积的 spans 和 lines 刷新为一个 ParagraphBlock。
  void flushParagraph() {
    pushSpansAsLines();
    // 段尾的 `<br>` 后面没有行可挂行首折叠量：记在最后一行的行尾折叠量上，
    // 字符域收下落地的每一个源字符，行首定位又不跟着偏。
    if (pendingCollapsed > 0) {
      if (lines.isNotEmpty) {
        final tail = lines.removeLast();
        lines.add(
          LineData(
            spans: tail.spans,
            isNewParagraph: tail.isNewParagraph,
            collapsedChars: tail.collapsedChars,
            trailingCollapsedChars:
                tail.trailingCollapsedChars + pendingCollapsed,
            softWrap: tail.softWrap,
            style: tail.style,
          ),
        );
      } else {
        // `<p><br></p>` 一个行都没有：同样要退账，否则这一格只存在于游标里。
        ctx.offset -= pendingCollapsed;
      }
      pendingCollapsed = 0;
    }
    if (lines.isNotEmpty) {
      // 缩进按三级取值：样式表的 `text-indent`（含祖先继承）压过源文本的字面缩进，
      // 源文本的字面缩进再补上样式表没说的那一格，两者都没说而这本书用段距分段时，
      // 由 `_withSpacingInferredIndent` 顶格。书两种表达都只可能各写一半
      // （Kindle 书常把 text-indent 挂在 body、把诗节的缩进写在字里）。
      var styled = <LineData>[
        for (final line in lines)
          line.withStyle(
            _withSpacingInferredIndent(bookStyle?.overlay(line.style)),
          ),
      ];
      if (isSplitContinuation) {
        // 图切断的后半截：`softWrap` 正是"行前不补换行也不补缩进"这一条规则，
        // 测量与渲染都经由 `paragraphGap` 取同一个判据。
        // 图后只剩空白时折出来的行没有可见字符，那不是被图切断的后半截，
        // 标成续行就是把下一段的缩进白白抹掉。
        if (styled.first.spans.any((span) => span.text.trim().isNotEmpty)) {
          styled = _markLeadingLineContinuation(styled);
        }
      }
      blocks.add(
        ParagraphBlock(
          lines: styled,
          hasTrailingSpacing: sawAdjacentBreaks,
          style: bookStyle,
        ),
      );
      lines.clear();
      // 相邻 `<br>` 的两格源字符已经由各行的折叠量收过，这里不能再替空行信号 advance。
      sawAdjacentBreaks = false;
    }
    // 续行标志只在**同一个块级元素内**有效：段尾图后面没有正文时它会被留到下一个
    // `<p>`，把本来该缩进的自然段标成续行。
    isSplitContinuation = false;
    prevWasBr = false;
  }

  _walkInlineChildren(
    element,
    currentSpans,
    style,
    ctx,
    onBr: () {
      if (currentSpans.isNotEmpty) {
        pushSpansAsLines();
        prevWasBr = false;
      }
      if (prevWasBr) {
        // 相邻的第二个 <br>：只登记空行信号，空白行字符计入下一行折叠量。
        sawAdjacentBreaks = true;
        pendingCollapsed += 1;
        ctx.offset += 1;
        return;
      }
      prevWasBr = true;
      pendingCollapsed += 1;
      ctx.offset += 1;
    },
    onText: () {
      prevWasBr = false;
    },
    // 段内图按**文档顺序**断开：旧写法先把图全部提到段落之前再收文本，
    // 句子中间的插图就跑到段首去了（真书库实测 2403 处图前后都有字）。
    // 一个 DOM img 节点仍只被消费一次（方案 §34 防御）：图只在 `onImage` 里落块，
    // `_collectInlineSpans` 不再为它产 span，也不推进字符域（ImageBlock 是零字符块）。
    onImage: (src, alt) {
      flushParagraph();
      blocks.add(ImageBlock(src: src, alt: alt));
      isSplitContinuation = true;
    },
  );

  // 收尾：残余 spans 成为最后一行，并 flush 本段。
  flushParagraph();
}

/// 把这一截的第一行标成"同一段的续行"，其余行原样保留。
List<LineData> _markLeadingLineContinuation(List<LineData> lines) {
  final head = lines.first;
  return [
    LineData(
      spans: head.spans,
      isNewParagraph: head.isNewParagraph,
      collapsedChars: head.collapsedChars,
      trailingCollapsedChars: head.trailingCollapsedChars,
      softWrap: true,
      style: head.style,
    ),
    ...lines.skip(1),
  ];
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

  /// 引用块自身在书的样式表里表达过的意图，作为块内没有单独表达时的回退。
  final quoteStyle = ctx.styles.styleFor(element);

  /// 硬换行留下的、要计入下一行折叠量的源字符数（口径同段落处理）。
  var pendingCollapsed = 0;

  /// 上一次出行是不是 `<br>`：段内硬换行之后的文本仍是同一段的续行，
  /// 不该拿首行缩进（段落侧用同一个标志，见 `_processParagraph.prevWasBr`）。
  var prevWasBr = false;

  /// 把已累积的 spans 折成一行；[lineStyle] 是这一行所属元素表达过的样式。
  ///
  /// [hardBreak] 表示这一行是被 `<br>` 断开的同段续行，不该拿首行缩进。容器里
  /// 的第 2 个及之后的 `<p>` 是新起一段，与段落侧同一口径下 `isNewParagraph`。
  ///
  /// 折叠必须走 `_foldIntoLines`（段落侧同一条路）：`<blockquote>\n  <p>` 之间那段
  /// 格式化空白以前会被当成一整行画出来，引用块首行凭空多一行缩进空白，真正的
  /// 第一段反而退到第二行、连带丢掉自己的首行缩进。
  void pushLine([ParagraphStyleSpec? lineStyle, bool hardBreak = false]) {
    if (currentSpans.isEmpty) return;
    final spans = List<ReaderInlineSpan>.of(currentSpans);
    currentSpans.clear();
    final (folded, residue) = _foldIntoLines(
      spans,
      firstLineIsNewParagraph: !hardBreak && !prevWasBr && bqLines.isNotEmpty,
      carriedCollapsed: pendingCollapsed,
    );
    if (residue > 0) ctx.offset -= residue;
    pendingCollapsed = 0;
    prevWasBr = hardBreak;
    for (final line in folded) {
      bqLines.add(line.withStyle(lineStyle ?? quoteStyle));
    }
  }

  /// 引用里的块级子树：容器元素自己不成一行，进去按其中的段落分行；
  /// 每一段取**它自己**命中的样式，不再一律回落到引用块的那份。
  ///
  /// 书信（`blockquote.z3998-letter > header > p`）的抬头与正文原先被压成一行，
  /// 且 header 上的右对齐与 `p.first-child` 的"不缩进"都丢了。
  void walkContainer(
    dom.Element container,
    ParagraphStyleSpec? owner,
    int depth,
  ) {
    for (final child in container.nodes) {
      if (child is dom.Text) {
        _collectInlineSpans(child, currentSpans, style, ctx);
        continue;
      }
      if (child is! dom.Element) continue;
      final tag = child.localName ?? '';
      if (_isNonContentTag(tag)) continue;
      if (tag == 'br') {
        pushLine(owner, true);
        pendingCollapsed += 1;
        ctx.offset += 1;
        continue;
      }
      final childStyle = ctx.styles.styleFor(child);
      if (_quoteContainerTags.contains(tag) && depth < _maxHtmlParseDepth) {
        final inner = childStyle ?? owner;
        pushLine(owner);
        walkContainer(child, inner, depth + 1);
        pushLine(inner);
        continue;
      }
      if (_isBlockTag(tag) || _isHeadingTag(tag)) {
        final own = childStyle ?? owner;
        pushLine(owner);
        if (tag == 'p' || _isHeadingTag(tag)) {
          // heading 在引用块内降级为加粗，但仍独占一行。
          _walkInlineChildren(
            child,
            currentSpans,
            _isHeadingTag(tag) ? style.copyWith(isBold: true) : style,
            ctx,
            onBr: () {
              pushLine(own, true);
              pendingCollapsed += 1;
              ctx.offset += 1;
            },
          );
        } else {
          // 列表、表格、pre：引用里少见，按原样摊平进当前行。
          _collectInlineSpans(child, currentSpans, style, ctx);
        }
        pushLine(own);
        continue;
      }
      // 内联元素
      _collectInlineSpans(child, currentSpans, style, ctx);
    }
  }

  walkContainer(element, quoteStyle, 0);

  // 最后的残余
  pushLine(quoteStyle);

  // 引用块以 `<br>` 收尾时没有下一行承接折叠量：记在最后一行的行尾折叠量上，口径同段落侧。
  if (pendingCollapsed > 0) {
    if (bqLines.isNotEmpty) {
      final tail = bqLines.removeLast();
      bqLines.add(
        LineData(
          spans: tail.spans,
          isNewParagraph: tail.isNewParagraph,
          collapsedChars: tail.collapsedChars,
          trailingCollapsedChars:
              tail.trailingCollapsedChars + pendingCollapsed,
          softWrap: tail.softWrap,
          style: tail.style,
        ),
      );
    } else {
      // 整块引用一行都没有（`<blockquote><br></blockquote>`）：这一格只存在于游标里，
      // 必须退回去，否则后面的块起点与章内锚点整体偏移。
      ctx.offset -= pendingCollapsed;
    }
    pendingCollapsed = 0;
  }

  // 按"对齐相同的连续行"切成若干引用块：一个 `Text.rich` 只能带一个 textAlign，
  // 抬头右对齐与正文默认对齐挤在同一块里必须丢一半。缩进与段距仍取引用块自己的
  // 表达，对齐来自这一组行。
  final runs = <List<LineData>>[];
  for (final line in bqLines) {
    final tail = runs.isEmpty ? null : runs.last;
    if (tail != null && tail.last.style?.textAlign == line.style?.textAlign) {
      tail.add(line);
    } else {
      runs.add(<LineData>[line]);
    }
  }
  for (var i = 0; i < runs.length; i++) {
    final isLastRun = i == runs.length - 1;
    final run = runs[i];
    blocks.add(
      BlockquoteBlock(
        lines: run,
        // 块起点 = 这一组行第一行的源起点（可绘制偏移减掉行首折叠量），不是收集完之后的
        // 游标：分页前缀表与页内裁剪都按"块起点 = 前面块字符数之和"取数。
        startOffset:
            run.first.spans.isEmpty
                ? ctx.offset
                : run.first.spans.first.startOffset - run.first.collapsedChars,
        // 盒子的上下留白属于整个引用：首段带上、尾段带下，中间段两头都不带，
        // 相邻两段才是相接的，不会每段各凭空多出 48px。
        hasTopPadding: i == 0,
        hasBottomPadding: isLastRun,
        // 块级只挂真会被消费的两项：对齐来自这一组行，下边距是引用块整段之后的
        // 一次留白，切块也只让它落在最后一块上。缩进按行生效，已经挂在各行 style。
        style: ParagraphStyleSpec(
          paragraphSpacingScale:
              isLastRun ? quoteStyle?.paragraphSpacingScale : null,
          textAlign: runs[i].first.style?.textAlign,
        ),
      ),
    );
  }
}

/// 引用里可以继续装块级子元素的容器：它们本身不是一行。
const _quoteContainerTags = {
  'div',
  'section',
  'article',
  'main',
  'header',
  'footer',
  'aside',
  'nav',
  'blockquote',
};

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
  // 块起点要在收集子项之前取：子项会推进游标，事后取到的是块尾。
  final listStart = ctx.offset;
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
        startOffset: listStart,
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
  // 块起点在收单元格之前取：单元格文本会推进游标。
  final tableStart = ctx.offset;
  final rows = <TableRowData>[];
  _collectTableRows(element, rows, ctx);

  if (rows.isNotEmpty) {
    blocks.add(TableBlock(rows: List.of(rows), startOffset: tableStart));
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
    // 书在 `pre` 上写过的行距属于代码块自己的版式：不带这一份，跟随档里
    // 代码块与正文一律按读者的行距折行，书的代码留白层次整本丢失。
    // 挂在行上而不是块上：块级样式由合并阶段从首行取，写在块上会被抹平。
    final bookStyle = ctx.styles.styleFor(element);
    blocks.add(
      ParagraphBlock(
        lines: [
          LineData(
            spans: [span],
            // 代码块顶格是它自己的版式：预格式化文本的行首空白属于内容，
            // 再由阅读器补一遍首行缩进就凭空多出一截。
            style: ParagraphStyleSpec(
              firstLineIndentChars: 0,
              lineHeightScale: bookStyle?.lineHeightScale,
            ),
          ),
        ],
      ),
    );
    ctx.offset += text.length;
  }
}

// ── Figure 处理 ──

/// 处理 `<figure>` 元素，提取图片和 figcaption。
void _processFigure(dom.Element element, List<ContentBlock> blocks) {
  // 图与图注都要按后代找：`<figure><div><img></div><figcaption>` 与
  // `<figure><a><img></a></figure>` 是 EPUB 制作工具的常见产物，只看直接子级
  // 会把整张图连同图注一起丢掉。按文档顺序走一遍，图注仍然贴到它前面那张图上。
  void visit(dom.Node node) {
    if (node is! dom.Element) {
      return;
    }
    if (node.localName == 'img') {
      final src = node.attributes['src'];
      if (src != null && src.isNotEmpty) {
        blocks.add(ImageBlock(src: src, alt: node.attributes['alt']));
      }
    } else if (node.localName == 'figcaption') {
      final captionText = _collectText(node).trim();
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
      return;
    }
    for (final child in node.nodes) {
      visit(child);
    }
  }

  visit(element);
}
