part of 'reader_html_parser.dart';

// ── 段内换行折叠 ──

/// 含换行的空白串：段内硬换行（如 Project Gutenberg 老书每约 35 字断行）。
final _wrapRunPattern = RegExp(r'[ \t　 ]*\n[ \t\n　 ]*');

/// 行首空白，缩进统一由渲染端注入，源字符数转入 `collapsedChars`。
final _lineLeadingPattern = RegExp(r'^[ \t　 ]+');

/// 空白串里的**空行**（两个换行之间只剩空白）：这是段落边界，不是段内换行。
///
/// 容器里的裸文本常用空行分段（`<div>甲段\n\n乙段</div>`，TXT 转 XHTML 也是这个形状）。
/// 只把它当软换行的话，续行既不补换行也不补缩进，两段被连排成一段：
/// 开关关掉时读者就再也分不出段落，看起来"这个开关什么也没改"。
final _blankLineRunPattern = RegExp(r'\n[ \t　]*\n');

/// 源文本行首空白里表达了几个全角缩进单位。
///
/// 一个全角空格算一个字，两个半角空格算一个字（中文稿用四个半角空格顶两个字的
/// 习惯）。只有含全角空格、或半空格成串到 4 个才算版式缩进：1-3 个半角空格是源码
/// 缩进（为了让 XHTML 可读打的空格），把它当缩进会让整章版面跟着源码抖动。
int _literalIndentChars(String whitespace) {
  var full = 0;
  var half = 0;
  for (final unit in whitespace.codeUnits) {
    if (unit == 0x3000) {
      full++;
    } else if (unit == 0x20 || unit == 0x09) {
      half++;
    }
  }
  if (full == 0 && half < 4) return 0;
  return (full + half ~/ 2).clamp(0, BookStyleSheet.maxIndentChars);
}

/// 段首行从源文本读出的排版表达：字面缩进与空行留白，折算进同一个样式槽。
///
/// 只在**段首行**登记：软换行续行的行首空白是源码折行，既不是缩进也不是留白。
/// 登记后缩进那一格与样式表的 `text-indent` 走同一字段，留白那一格由合并阶段
/// 转记到前一段的尾部；两者都只在「跟随原书」打开时被采纳，关闭档一寸不动。
ParagraphStyleSpec? _sourceParagraphStyle({
  required int indentChars,
  required int blankGapLines,
}) {
  if (indentChars <= 0 && blankGapLines <= 0) return null;
  return ParagraphStyleSpec(
    firstLineIndentChars: indentChars > 0 ? indentChars : null,
    paragraphBlankGapLines: blankGapLines > 0 ? blankGapLines : null,
  );
}

/// 空白串里最后一个换行之后的那一截，也就是续行真正的行首空白。
///
/// 只能取最后一行之后的部分：空白串里可能夹着整行的空白行（`<p>\n    \n甲`），
/// 把那些空格也算进缩进会让一个根本没缩进的文件报出「书要求四个字的缩进」。
String _trailingWhitespace(String gap) {
  final lastBreak = gap.lastIndexOf('\n');
  return lastBreak < 0 ? gap : gap.substring(lastBreak + 1);
}

bool _isAsciiWordUnit(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A);

/// 用新的可绘制文本复制 span，样式不变，起始偏移**重定位到这一片自己的源位置**。
///
/// 一个源文本节点会被折成若干片（行首空白、软换行边界前后的片段），照抄原 span
/// 的 startOffset 会让第二片以后的偏移全部指回段首：标注与高亮按 span.startOffset
/// 命中字符，存下来的区间就会涂到同段的其他行上。
ReaderInlineSpan _respan(
  ReaderInlineSpan source,
  String text,
  int sourceStart,
) => ReaderInlineSpan(
  text: text,
  isBold: source.isBold,
  isItalic: source.isItalic,
  isHeading: source.isHeading,
  href: source.href,
  isCode: source.isCode,
  startOffset: sourceStart,
  isSuperscript: source.isSuperscript,
  isSubscript: source.isSubscript,
  isMarked: source.isMarked,
  isDeleted: source.isDeleted,
  isUnderlined: source.isUnderlined,
);

/// 把一段内联 spans 折成逻辑行。
///
/// 折叠规则：
/// - 行首空白剥除，长度记入本行 `collapsedChars`；段首行剥掉的那一截若构成版式
///   缩进（全角空格，或成串的半角空格），同时折算进本行的
///   `style.firstLineIndentChars`，与样式表里 `text-indent` 同一个字段；
/// - 含换行的空白串视为软换行边界：结束当前行，续行标记 `softWrap`，
///   空白串长度记入续行 `collapsedChars`；两侧都是 ASCII 词字符时保留一个空格
///   作为可绘制文本（对应空白串中的一个源字符），避免英文被粘连；
/// - 全空白行不产出，其字符数并入后续行的折叠量。
///
/// 折叠量一律只落在行首，所以同一行内 `源索引 = 可绘制索引 + collapsedChars`
/// 恒成立，块级字符记账与页内裁剪可以共用这一不变式。
///
/// 返回的 `residue` 是**没有任何行可以承接**的源字符数（整段只有空白时才会出现）：
/// 调用方必须把它从 `ctx.offset` 退回去，否则解析游标比块字符记账多走，
/// 之后记下的章内锚点与块起点就落在另一个域里，高亮与跳转整体偏移。
(List<LineData> lines, int residue) _foldIntoLines(
  List<ReaderInlineSpan> spans, {
  required bool firstLineIsNewParagraph,
  int carriedCollapsed = 0,
}) {
  final out = <LineData>[];
  var buffer = <ReaderInlineSpan>[];
  var painted = 0;
  var collapsed = carriedCollapsed;
  var isNewParagraph = firstLineIsNewParagraph;
  var isSoftWrap = false;
  var literalIndent = 0;
  var blankGapLines = 0;
  var lastPaintedUnit = 0;

  void closeLine() {
    if (painted == 0) {
      buffer = <ReaderInlineSpan>[];
      return;
    }
    out.add(
      LineData(
        spans: List<ReaderInlineSpan>.unmodifiable(buffer),
        isNewParagraph: isNewParagraph,
        collapsedChars: collapsed,
        softWrap: isSoftWrap,
        style: _sourceParagraphStyle(
          indentChars: isNewParagraph ? literalIndent : 0,
          blankGapLines: isNewParagraph ? blankGapLines : 0,
        ),
      ),
    );
    buffer = <ReaderInlineSpan>[];
    painted = 0;
    collapsed = 0;
    isNewParagraph = false;
    isSoftWrap = true;
    literalIndent = 0;
    blankGapLines = 0;
  }

  void append(String text, ReaderInlineSpan source, int sourceStart) {
    if (text.isEmpty) {
      return;
    }
    buffer.add(_respan(source, text, sourceStart));
    painted += text.length;
    lastPaintedUnit = text.codeUnitAt(text.length - 1);
  }

  for (final span in spans) {
    final text = span.text;
    var cursor = 0;
    for (final match in _wrapRunPattern.allMatches(text)) {
      var pieceStart = cursor;
      var piece = text.substring(cursor, match.start);
      if (painted == 0) {
        final leading = _lineLeadingPattern.firstMatch(piece);
        if (leading != null) {
          literalIndent = _literalIndentChars(piece.substring(0, leading.end));
          collapsed += leading.end;
          piece = piece.substring(leading.end);
          pieceStart += leading.end;
        }
      }
      append(piece, span, span.startOffset + pieceStart);

      final gap = match[0]!;
      final nextUnit = match.end < text.length ? text.codeUnitAt(match.end) : 0;
      final joinSpace =
          _isAsciiWordUnit(lastPaintedUnit) && _isAsciiWordUnit(nextUnit)
              ? ' '
              : '';
      closeLine();
      // 空白行为空时 `closeLine` 不产出行也不清零折叠量：这里必须累加，
      // 直接赋值会把 `<br>` 结转来的折叠量连同这一段空白一起丢掉。
      collapsed += gap.length - joinSpace.length;
      // 空白串里最后一个换行之后的行首空白，就是续行的缩进（TXT 转 XHTML、
      // 以及 `<div>` 裸文本空行分段都走这一条，行首空白不会单独成支）。
      final gapIndent = _literalIndentChars(_trailingWhitespace(gap));
      if (gapIndent > 0) literalIndent = gapIndent;
      // 一段前的空白行是作者留的白：两个换行=一行白，三个=两行……行数按原样记下，
      // 折算成像素留给设置层做（那里才知道读者的行高，解析层只存相对量）。
      final gapBreaks = '\n'.allMatches(gap).length;
      if (gapBreaks >= 2) blankGapLines = gapBreaks - 1;
      if (_blankLineRunPattern.hasMatch(gap)) {
        // 空行分段：续行是新段落的首行，要补换行与缩进，不能按软换行连排。
        isSoftWrap = false;
        isNewParagraph = true;
      }
      if (joinSpace.isNotEmpty) {
        // 补回的空格对应空白串里的最后一个源字符，其余都记在本行折叠量里。
        append(joinSpace, span, span.startOffset + match.end - 1);
      }
      cursor = match.end;
      if (cursor >= text.length) {
        break;
      }
      // 续行行首不再含空白：它已被上面的空白串整体吞掉。
    }
    if (cursor < text.length) {
      var restStart = cursor;
      var rest = text.substring(cursor);
      if (painted == 0) {
        final leading = _lineLeadingPattern.firstMatch(rest);
        if (leading != null) {
          literalIndent = _literalIndentChars(rest.substring(0, leading.end));
          collapsed += leading.end;
          rest = rest.substring(leading.end);
          restStart += leading.end;
        }
      }
      append(rest, span, span.startOffset + restStart);
    }
  }

  if (painted == 0) {
    // 段尾只剩空白：这些字符不进可绘制文本，也没有下一行承接行首折叠量。
    // 记在最后一行的 trailingCollapsedChars 上——字符域要收下落地的每一个源字符，
    // 但它们在这一行可绘制文本之后，混进行首折叠量会让裁剪侧的定位整体前移。
    if (collapsed > 0 && out.isNotEmpty) {
      final tail = out.removeLast();
      out.add(
        LineData(
          spans: tail.spans,
          isNewParagraph: tail.isNewParagraph,
          collapsedChars: tail.collapsedChars,
          trailingCollapsedChars: tail.trailingCollapsedChars + collapsed,
          softWrap: tail.softWrap,
          style: tail.style,
        ),
      );
    }
    // 连一行都没有：折叠量无处可挂，交回调用方退账。
    return (out, collapsed);
  }
  closeLine();
  return (out, 0);
}

// ── 内联内容提取 ──

/// 遍历元素的子节点，提取内联 spans 并处理 `<br>` 分行。
///
/// [onBr] 回调在遇到 `<br>` 时调用，由调用者决定如何处理换行。
/// [onImage] 在遇到 `<img>` 时按文档顺序调用，由调用者决定图文怎么落块。
void _walkInlineChildren(
  dom.Element element,
  List<ReaderInlineSpan> currentSpans,
  _StyleContext style,
  _ParseContext ctx, {
  void Function()? onBr,
  void Function()? onText,
  void Function(String src, String? alt)? onImage,
}) {
  for (final child in element.nodes) {
    if (child is dom.Text) {
      onText?.call();
      _collectInlineSpans(
        child,
        currentSpans,
        style,
        ctx,
        onBr: onBr,
        onImage: onImage,
      );
    } else if (child is dom.Element) {
      final tag = child.localName;
      if (tag == 'br') {
        onBr?.call();
      } else if (_isBlockTag(tag)) {
        onText?.call();
        _collectInlineSpans(
          child,
          currentSpans,
          style,
          ctx,
          onBr: onBr,
          onImage: onImage,
        );
      } else {
        onText?.call();
        _collectInlineSpans(
          child,
          currentSpans,
          style,
          ctx,
          onBr: onBr,
          onImage: onImage,
        );
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
///
/// [onImage] 按文档顺序拿到段内 `<img>` 的 src：图在句子中间时，调用方要在那里
/// 断开当前片段（真书库实测 2403 处"图前后都有字"）。不给回调时图不产 span，
/// 与引用块、列表、单元格里一贯的"内联图不落在文本流"相同。
///
/// [onBr] 在遇到 `<br>` 时要求上层断开当前行：`<p><i>第一句<br/>第二句</i></p>` 这类
/// 行内元素内嵌的换行必须与直接子节点的 `<br>` 同权，否则诗句、信件与台词被拼成一行，
/// 折叠字符数也少算一个。
void _collectInlineSpans(
  dom.Node node,
  List<ReaderInlineSpan> spans,
  _StyleContext style,
  _ParseContext ctx, {
  int depth = 0,
  void Function()? onBr,
  void Function(String src, String? alt)? onImage,
}) {
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
  if (_isNonContentTag(tag)) return;
  ctx.noteAnchor(node);
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
      // 行内元素里的 <br> 由上层按换行处理；没有回调时保持旧行为（不产文本）。
      onBr?.call();
      break;

    case 'img':
      // 图不产文本、也不推进字符域（ImageBlock 本就是零字符块）；只在调用方愿意
      // 按原位断开时把 src 与 alt 交出去。
      final src = node.attributes['src'];
      if (src != null && src.isNotEmpty) {
        onImage?.call(src, node.attributes['alt']);
      }
      break;

    case 'b':
    case 'strong':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isBold: true),
          ctx,
          depth: depth + 1,
          onBr: onBr,
          onImage: onImage,
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
          depth: depth + 1,
          onBr: onBr,
          onImage: onImage,
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
          depth: depth + 1,
          onBr: onBr,
          onImage: onImage,
        );
      }

    case 'code':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isCode: true),
          ctx,
          depth: depth + 1,
          onBr: onBr,
          onImage: onImage,
        );
      }

    case 'sup':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isSuperscript: true),
          ctx,
          depth: depth + 1,
          onBr: onBr,
          onImage: onImage,
        );
      }

    case 'sub':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isSubscript: true),
          ctx,
          depth: depth + 1,
          onBr: onBr,
          onImage: onImage,
        );
      }

    case 'mark':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isMarked: true),
          ctx,
          depth: depth + 1,
          onBr: onBr,
          onImage: onImage,
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
          depth: depth + 1,
          onBr: onBr,
          onImage: onImage,
        );
      }

    case 'u':
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style.copyWith(isUnderlined: true),
          ctx,
          depth: depth + 1,
          onBr: onBr,
          onImage: onImage,
        );
      }

    default:
      // span, abbr, cite, q, small 等 —— 递归处理子节点
      for (final child in node.nodes) {
        _collectInlineSpans(
          child,
          spans,
          style,
          ctx,
          depth: depth + 1,
          onBr: onBr,
          onImage: onImage,
        );
      }
  }
}

// ── 文本收集 ──

/// 递归收集节点及其后代中的所有文本。
///
/// 非正文子树（内联 `<style>`、`<script>`）整段跳过：这里汇了标题、题注、单元格、
/// `pre` 与超深折叠的取文本路径，漏一处就把 CSS 源码当正文渲染。
String _collectText(dom.Node node) {
  final buffer = StringBuffer();
  _collectTextRecursive(node, buffer);
  return buffer.toString();
}

void _collectTextRecursive(dom.Node node, StringBuffer buffer) {
  if (node is dom.Text) {
    buffer.write(_sanitizeText(node.text));
  } else if (node is dom.Element) {
    if (_isNonContentTag(node.localName)) return;
    if (node.localName == 'br') {
      buffer.write('\n');
    }
    for (final child in node.nodes) {
      _collectTextRecursive(child, buffer);
    }
  }
}
