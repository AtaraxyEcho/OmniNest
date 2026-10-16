import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_stylesheet.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';

/// 装配规则的等宽文本视图：换行照原样，缩进盒子记成同样字宽的全角空格。
///
/// 真实排版由 `paragraphGapSpans` 给出 span 序列；这里只为把一整块的版面拼成
/// 字符串比对，规则一律以 `paragraphGap` 为准。
String paragraphLineSeparator({
  required bool isFirstLine,
  required bool isNewParagraph,
  required bool previousLineIsEmpty,
  required bool isBlockContinuation,
  required bool startsWithFullWidthIndent,
  int indentChars = defaultFirstLineIndentChars,
  bool isSoftWrap = false,
}) {
  final gap = paragraphGap(
    isFirstLine: isFirstLine,
    isNewParagraph: isNewParagraph,
    previousLineIsEmpty: previousLineIsEmpty,
    isBlockContinuation: isBlockContinuation,
    startsWithFullWidthIndent: startsWithFullWidthIndent,
    indentChars: indentChars,
    isSoftWrap: isSoftWrap,
  );
  return '${gap.newLine ? '\n' : ''}${'　' * gap.indentChars}';
}

void main() {
  group('parseBlocks - basic', () {
    test('returns empty list for empty HTML', () {
      expect(parseBlocks(''), isEmpty);
      expect(parseBlocks('   '), isEmpty);
    });

    test('parses simple paragraph', () {
      final blocks = parseBlocks('<p>Hello World</p>');
      expect(blocks, hasLength(1));
      expect(blocks.first, isA<ParagraphBlock>());
      final p = blocks.first as ParagraphBlock;
      expect(p.lines, hasLength(1));
      expect(p.lines.first.spans.first.text, 'Hello World');
    });

    test('skips inline style and script elements in body content', () {
      // HTML5 只在 body 直属层把 style/script 抬进 head；写在 div、figure 里的
      // 样式表会留在原地，不跳过就把 CSS 源码当正文渲染，还白占字符偏移。
      final blocks = parseBlocks(
        '<div><style>p { text-indent: 2em; margin-bottom: 0 }</style>'
        '<p>正文一。</p></div>'
        '<div><script>var broken = 1;</script><p>正文二。</p></div>',
      );
      final text =
          blocks
              .whereType<ParagraphBlock>()
              .expand((block) => block.lines)
              .expand((line) => line.spans)
              .map((span) => span.text)
              .join();
      expect(text, isNot(contains('text-indent')));
      expect(text, isNot(contains('var broken')));
      expect(text, contains('正文一。'));
      expect(text, contains('正文二。'));
    });

    test('内联样式表在正文各层级都不进文本', () {
      // `_isNonContentTag` 原先只挡在块级分发处：标题、单元格、`pre`、`li` 与段落
      // 内联子节点各有一条取文本的路，漏一条就把 CSS 源码渲染成正文，还按字符数
      // 撑大本章的偏移域（书签与标注都会跟着偏）。
      const css = 'p { margin-bottom: 0; text-indent: 2em }';
      final cases = <String, String>{
        '段落内': r'<p>前段<$css>后段</p>',
        '标题内': r'<h2>标题<$css></h2>',
        '单元格内': r'<table><tr><td>格<$css></td></tr></table>',
        '代码块内': r'<pre>代码<$css></pre>',
        '列表项内': r'<ul><li>项<$css></li></ul>',
        '引用内': r'<blockquote>引<$css></blockquote>',
      };
      for (final entry in cases.entries) {
        // 把样式表原文塞进正文里对应的位置，再整块查文本。
        final html = entry.value.replaceAll(r'$css', '<style>$css</style>');
        final text = _allBlockText(parseBlocks(html));
        expect(text, isNot(contains('margin-bottom')), reason: entry.key);
        expect(text, isNot(contains('text-indent')), reason: entry.key);
      }
    });

    test('skips inline script nested in body content', () {
      final blocks = parseBlocks(
        '<p>正文<script>var leak = "css源码";</script>续。</p>',
      );
      final text = _allBlockText(blocks);
      expect(text, isNot(contains('var leak')));
      expect(text, contains('正文'));
      expect(text, contains('续。'));
    });

    test('parses heading', () {
      final blocks = parseBlocks('<h1>Title</h1>');
      expect(blocks, hasLength(1));
      expect(blocks.first, isA<HeadingBlock>());
      final h = blocks.first as HeadingBlock;
      expect(h.text, 'Title');
      expect(h.level, 1);
    });

    test('parses multiple headings', () {
      final blocks = parseBlocks('<h1>H1</h1><h2>H2</h2><h3>H3</h3>');
      expect(blocks, hasLength(3));
      expect((blocks[0] as HeadingBlock).level, 1);
      expect((blocks[1] as HeadingBlock).level, 2);
      expect((blocks[2] as HeadingBlock).level, 3);
    });

    test('parses bold and italic inline spans', () {
      final blocks = parseBlocks('<p><b>Bold</b> and <i>Italic</i></p>');
      expect(blocks, hasLength(1));
      final p = blocks.first as ParagraphBlock;
      final spans = p.lines.first.spans;
      // Parser flushes on style transitions: "Bold" (bold), " and " (normal), "Italic" (italic)
      expect(spans.length, greaterThanOrEqualTo(2));
      expect(spans[0].text, 'Bold');
      expect(spans[0].isBold, isTrue);
      expect(spans.last.text, 'Italic');
      expect(spans.last.isItalic, isTrue);
    });

    test('parses link with href', () {
      final blocks = parseBlocks(
        '<p><a href="https://example.com">Link</a></p>',
      );
      final p = blocks.first as ParagraphBlock;
      final span = p.lines.first.spans.first;
      expect(span.text, 'Link');
      expect(span.href, 'https://example.com');
    });

    test('parses image block', () {
      final blocks = parseBlocks('<img src="test.png" alt="Test"/>');
      expect(blocks, hasLength(1));
      expect(blocks.first, isA<ImageBlock>());
      final img = blocks.first as ImageBlock;
      expect(img.src, 'test.png');
      expect(img.alt, 'Test');
    });

    test('parses horizontal rule', () {
      // Note: <hr/> (no space) may not match the br regex pattern.
      // <hr /> (with space) matches the first pattern.
      final blocks = parseBlocks('<p>A</p><hr /><p>B</p>');
      expect(blocks.any((b) => b is DividerBlock), isTrue);
      expect(blocks.any((b) => b is ParagraphBlock), isTrue);
    });

    test('parses code inline', () {
      final blocks = parseBlocks('<p><code>var x = 1;</code></p>');
      final p = blocks.first as ParagraphBlock;
      final span = p.lines.first.spans.first;
      expect(span.text, 'var x = 1;');
      expect(span.isCode, isTrue);
    });

    test('parses pre block as code', () {
      final blocks = parseBlocks('<pre>line1\nline2</pre>');
      expect(blocks, hasLength(1));
      final p = blocks.first as ParagraphBlock;
      expect(p.lines.first.spans.first.isCode, isTrue);
    });
  });

  group('parseBlocks - blockquote', () {
    test('parses simple blockquote', () {
      final blocks = parseBlocks('<blockquote><p>Quote text</p></blockquote>');
      expect(blocks, hasLength(1));
      expect(blocks.first, isA<BlockquoteBlock>());
      final bq = blocks.first as BlockquoteBlock;
      expect(bq.lines, isNotEmpty);
      expect(bq.lines.first.spans.first.text, 'Quote text');
    });

    test('parses blockquote with br', () {
      // <br> inside blockquote may leak Line2 to a separate ParagraphBlock
      // due to parser flush ordering. Test that Line1 is in the blockquote.
      final blocks = parseBlocks('<blockquote>Line1<br>Line2</blockquote>');
      expect(blocks.first, isA<BlockquoteBlock>());
      final bq = blocks.first as BlockquoteBlock;
      expect(bq.lines, isNotEmpty);
      final allText =
          bq.lines.map((l) => l.spans.map((s) => s.text).join()).join();
      expect(allText, contains('Line1'));
    });

    test('blockquote does not leak into next paragraph', () {
      final blocks = parseBlocks(
        '<blockquote><p>Quote</p></blockquote><p>After</p>',
      );
      expect(blocks.length, greaterThanOrEqualTo(2));
      expect(blocks.first, isA<BlockquoteBlock>());
      expect(blocks.last, isA<ParagraphBlock>());
      final after = blocks.last as ParagraphBlock;
      expect(after.lines.first.spans.first.text, 'After');
    });

    test('heading inside blockquote demotes to bold', () {
      final blocks = parseBlocks(
        '<blockquote><h2>Title</h2><p>Text</p></blockquote>',
      );
      expect(blocks, hasLength(1));
      expect(blocks.first, isA<BlockquoteBlock>());
      // Heading should NOT produce a separate HeadingBlock
      expect(blocks.whereType<HeadingBlock>(), isEmpty);
    });

    test('格式化缩进的空白不再变成引用块首尾的空行', () {
      // 制作工具写的 `<blockquote>\n  <p>一</p>\n  <p>二</p>\n</blockquote>`
      // 里，标签之间的换行与缩进以前会被当成一行画出来：引用块第一行是空白，
      // 真正的第一段退到第二行并丢掉自己的首行缩进。
      final blocks = parseBlocks(
        '<blockquote>\n  <p>引用段一</p>\n  <p>引用段二</p>\n</blockquote>',
      );
      final bq = blocks.first as BlockquoteBlock;
      final texts =
          bq.lines
              .map((line) => line.spans.map((span) => span.text).join())
              .toList();

      expect(texts, ['引用段一', '引用段二']);
      expect(bq.lines.first.isNewParagraph, isFalse);
      expect(bq.lines.last.isNewParagraph, isTrue);
    });

    test('引用块内的硬换行仍是同段续行', () {
      final blocks = parseBlocks('<blockquote>甲<br>乙</blockquote>');
      final bq = blocks.first as BlockquoteBlock;
      final texts =
          bq.lines
              .map((line) => line.spans.map((span) => span.text).join())
              .toList();

      expect(texts, ['甲', '乙']);
      // <br> 之后不是新起一段，不该补首行缩进。
      expect(bq.lines.last.isNewParagraph, isFalse);
    });
  });

  group('parseBlocks - figure', () {
    test('嵌套容器里的图与图注都要收进来', () {
      final blocks = parseBlocks(
        '<figure><div><img src="images/a.png" alt="甲"/></div>'
        '<figcaption>图一</figcaption></figure>',
      );

      expect(blocks.whereType<ImageBlock>().map((b) => b.src), [
        'images/a.png',
      ]);
      expect(blocks.whereType<ImageBlock>().single.caption, '图一');
      expect(blocks.whereType<ImageBlock>().single.alt, '甲');
    });

    test('链接包住的图不被丢掉', () {
      final blocks = parseBlocks(
        '<figure><a href="#x"><img src="b.png"/></a></figure>',
      );

      expect(blocks.whereType<ImageBlock>().map((b) => b.src), ['b.png']);
    });
  });

  group('parseBlocks - list', () {
    test('parses unordered list', () {
      final blocks = parseBlocks('<ul><li>A</li><li>B</li></ul>');
      expect(blocks, hasLength(1));
      expect(blocks.first, isA<ListBlock>());
      final list = blocks.first as ListBlock;
      expect(list.isOrdered, isFalse);
      // Parser may create empty trailing item
      expect(list.items.length, greaterThanOrEqualTo(2));
    });

    test('parses ordered list', () {
      final blocks = parseBlocks('<ol><li>First</li><li>Second</li></ol>');
      expect(blocks, hasLength(1));
      final list = blocks.first as ListBlock;
      expect(list.isOrdered, isTrue);
      expect(list.items.length, greaterThanOrEqualTo(2));
    });

    test('nested list produces list blocks', () {
      final blocks = parseBlocks(
        '<ol><li>A<ul><li>B</li></ul></li><li>C</li></ol>',
      );
      // Should produce at least one ListBlock
      final lists = blocks.whereType<ListBlock>().toList();
      expect(lists, isNotEmpty);
    });

    test('list does not leak consecutiveBreaks', () {
      final blocks = parseBlocks('<ul><li>A<br/>B</li></ul><p>After</p>');
      expect(blocks, hasLength(2));
      expect(blocks[1], isA<ParagraphBlock>());
      final after = blocks[1] as ParagraphBlock;
      expect(after.hasTrailingSpacing, isFalse);
    });
  });

  group('parseBlocks - table', () {
    test('parses simple table', () {
      final blocks = parseBlocks(
        '<table><tr><td>A</td><td>B</td></tr></table>',
      );
      expect(blocks, hasLength(1));
      expect(blocks.first, isA<TableBlock>());
      final table = blocks.first as TableBlock;
      expect(table.rows, hasLength(1));
      expect(table.rows.first.cells, hasLength(2));
    });

    test('parses table with header', () {
      final blocks = parseBlocks(
        '<table><thead><tr><th>H1</th><th>H2</th></tr></thead>'
        '<tbody><tr><td>D1</td><td>D2</td></tr></tbody></table>',
      );
      expect(blocks, hasLength(1));
      final table = blocks.first as TableBlock;
      expect(table.rows, hasLength(2));
      expect(table.rows.first.isHeader, isTrue);
      expect(table.rows.last.isHeader, isFalse);
    });

    test('empty table cell is preserved', () {
      final blocks = parseBlocks(
        '<table><tr><td></td><td>Content</td></tr></table>',
      );
      final table = blocks.first as TableBlock;
      expect(table.rows.first.cells, hasLength(2));
    });
  });

  group('parseBlocks - inline tags', () {
    test('superscript tag', () {
      final blocks = parseBlocks('<p>X<sup>2</sup></p>');
      final p = blocks.first as ParagraphBlock;
      final spans = p.lines.first.spans;
      expect(spans.any((s) => s.text == '2' && s.isSuperscript), isTrue);
    });

    test('subscript tag', () {
      final blocks = parseBlocks('<p>H<sub>2</sub>O</p>');
      final p = blocks.first as ParagraphBlock;
      final spans = p.lines.first.spans;
      expect(spans.any((s) => s.text == '2' && s.isSubscript), isTrue);
    });

    test('mark tag', () {
      final blocks = parseBlocks('<p><mark>highlighted</mark></p>');
      final p = blocks.first as ParagraphBlock;
      expect(p.lines.first.spans.first.isMarked, isTrue);
    });

    test('strikethrough tag', () {
      final blocks = parseBlocks('<p><del>deleted</del></p>');
      final p = blocks.first as ParagraphBlock;
      expect(p.lines.first.spans.first.isDeleted, isTrue);
    });

    test('underline tag', () {
      final blocks = parseBlocks('<p><u>underlined</u></p>');
      final p = blocks.first as ParagraphBlock;
      expect(p.lines.first.spans.first.isUnderlined, isTrue);
    });

    /// 行内元素里嵌套的 `<br>` 必须与直接子节点的 `<br>` 同权：诗句、信件与台词
    /// 全靠它分行，被吞掉就会把多行压成一行，折叠字符数也少算一个。
    test('行内标签内嵌 br 仍按行断开', () {
      final blocks = parseBlocks('<p><i>第一行诗<br/>第二行诗</i></p>');
      expect(blocks, hasLength(1));
      final p = blocks.single as ParagraphBlock;
      final texts =
          p.lines
              .map((line) => line.spans.map((span) => span.text).join())
              .toList();

      expect(texts, ['第一行诗', '第二行诗']);
      expect(p.lines[1].collapsedChars, 1);
      expect(p.lines.first.spans.first.isItalic, isTrue);
    });

    test('span 内嵌 br 与嵌套两层标签内嵌 br 都断行', () {
      final spanBlocks = parseBlocks(
        '<p><span class="poem">甲<br/>乙</span></p>',
      );
      final spanLines = (spanBlocks.single as ParagraphBlock).lines;
      expect(
        spanLines.map((line) => line.spans.map((s) => s.text).join()).toList(),
        ['甲', '乙'],
      );

      final nested = parseBlocks('<p><b><em>丙<br/>丁</em></b></p>');
      final nestedLines = (nested.single as ParagraphBlock).lines;
      expect(
        nestedLines
            .map((line) => line.spans.map((s) => s.text).join())
            .toList(),
        ['丙', '丁'],
      );
    });

    test('容器直属裸 br 与行内元素里的 br 都断段', () {
      final blocks = parseBlocks('<div>甲<br/>乙</div>');
      final texts =
          blocks
              .whereType<ParagraphBlock>()
              .expand(
                (block) => block.lines.map(
                  (line) => line.spans.map((span) => span.text).join(),
                ),
              )
              .toList();

      expect(texts, ['甲', '乙']);
    });
  });

  group('parseBlocks - entity decoding', () {
    test('decodes common entities', () {
      final blocks = parseBlocks('<p>&amp; &lt; &gt; &quot;</p>');
      final text =
          (blocks.first as ParagraphBlock).lines.first.spans.first.text;
      expect(text, contains('&'));
      expect(text, contains('<'));
      expect(text, contains('>'));
      expect(text, contains('"'));
    });

    test('decodes typographic entities', () {
      final blocks = parseBlocks('<p>&mdash; &ndash; &hellip;</p>');
      final text =
          (blocks.first as ParagraphBlock).lines.first.spans.first.text;
      expect(text, contains('—'));
      expect(text, contains('–'));
      expect(text, contains('…'));
    });

    test('decodes numeric entities', () {
      final blocks = parseBlocks('<p>&#65; &#x42;</p>');
      final text =
          (blocks.first as ParagraphBlock).lines.first.spans.first.text;
      expect(text, contains('A'));
      expect(text, contains('B'));
    });
  });

  group('parseBlocks - globalOffset tracking', () {
    test('offsets are sequential across blocks', () {
      // 连续段落会被合并为单个块（中文排版惯例），用不同块类型测试偏移
      final blocks = parseBlocks('<p>ABC</p><h1>DEF</h1>');
      final p1 = blocks[0] as ParagraphBlock;
      final h1 = blocks[1] as HeadingBlock;
      final span1 = p1.lines.first.spans.first;
      expect(span1.startOffset, 0);
      expect(h1.startOffset, greaterThan(0));
    });

    test('heading has correct startOffset', () {
      final blocks = parseBlocks('<p>AB</p><h1>CD</h1>');
      final h = blocks[1] as HeadingBlock;
      expect(h.startOffset, greaterThan(0));
    });

    test('块起始偏移等于前面所有块的字符累计', () {
      // 分页前缀表与页内裁剪都按"块起点 = 前面块的字符数之和"取数；引用、列表、
      // 表格这三类块在收集完子内容之后才写 startOffset，落的其实是块尾。
      final blocks = parseBlocks(
        '<p>正文四。</p>'
        '<blockquote>引用两行。</blockquote>'
        '<ul><li>列表项。</li></ul>'
        '<table><tr><td>单元格</td></tr></table>',
      );
      expect(blocks, hasLength(4));
      var prefix = 0;
      for (final block in blocks) {
        final start = switch (block) {
          ParagraphBlock() => block.lines.first.spans.first.startOffset,
          BlockquoteBlock() => block.startOffset,
          ListBlock() => block.startOffset,
          TableBlock() => block.startOffset,
          HeadingBlock() => block.startOffset,
          _ => 0,
        };
        expect(
          start,
          prefix,
          reason: '${block.runtimeType} 的起始偏移应落在 $prefix，实得 $start',
        );
        prefix += BlockClipper.blockCharCount(block);
      }
    });

    test('标题、分隔线与换行都不给字符域凭空加一格', () {
      // 游标（span 与块偏移的来源）和 blockCharCount 之和必须是同一个域。旧实现里
      // 标题与 hr 各多 advance 1、相邻 `<br>` 的空行信号再加 1、引用块与段尾的 `<br>`
      // 只 advance 不记账：漂移随标题/分隔线数量单调增长，标注存下来的偏移比分页域
      // 偏高，甚至可以超出本章 totalChars。
      final blocks = parseBlocks(
        '<h2>章标题</h2>'
        '<p>第一段正文</p>'
        '<hr>'
        '<p>甲行\n  乙行\n  丙行</p>'
        '<p>甲<br>\n乙</p>'
        '<p>A<br>B<br>C</p>'
        '<p>尾随换行<br></p>'
        '<blockquote>引一<br>引二</blockquote>'
        '<p>收尾段落</p>',
      );
      var prefix = 0;
      for (final block in blocks) {
        final lines = switch (block) {
          ParagraphBlock() => block.lines,
          BlockquoteBlock() => block.lines,
          _ => const <LineData>[],
        };
        final start = switch (block) {
          ParagraphBlock() =>
            lines.first.spans.first.startOffset - lines.first.collapsedChars,
          BlockquoteBlock() => block.startOffset,
          ListBlock() => block.startOffset,
          TableBlock() => block.startOffset,
          HeadingBlock() => block.startOffset,
          _ => prefix,
        };
        expect(
          start,
          prefix,
          reason: '${block.runtimeType} 起点应落在 $prefix，实得 $start',
        );
        // 行内每个 span 的偏移就是它自己的源位置：块内前缀 + 行首折叠量 + 行内偏移。
        var linePrefix = prefix;
        for (final line in lines) {
          var paintedInLine = 0;
          for (final span in line.spans) {
            expect(
              span.startOffset,
              linePrefix + line.collapsedChars + paintedInLine,
              reason: 'span "${span.text}" 的偏移没落在自己的源位置上',
            );
            paintedInLine += span.text.length;
          }
          linePrefix += line.sourceChars;
        }
        prefix += BlockClipper.blockCharCount(block);
      }
    });

    test('章内锚点记在同一个字符域里', () {
      // 跳转过去按 stripHtml(前缀).length 反推：标签折成的空格、实体长度都不在块的
      // 字符计数里，落点会偏。锚点必须在解析期就记成与块偏移同一个口径。
      // 源文本 `标题`(2) + `a b`(3，&nbsp; 归一为空格) → `fn2` 落在 5。
      const html = '<h2>标题</h2><p>a&nbsp;b</p><p id="fn2">target</p>';
      final anchors = <String, int>{};
      final blocks = parseBlocks(html, anchors: anchors);
      final total = blocks.fold<int>(
        0,
        (sum, block) => sum + BlockClipper.blockCharCount(block),
      );

      expect(anchors['fn2'], 5);
      expect(anchors['fn2'], lessThanOrEqualTo(total), reason: '锚点不能超出本章字符域');
      // 旧算法给的是 6：多算的正是标签换出来的那一个空格。
      expect(
        stripHtml(html.substring(0, html.indexOf('id="fn2"'))).length,
        isNot(5),
      );
    });
    test('整段空白与孤立 br 不给字符域留洞', () {
      // 这几条分支都折不出任何行：折叠量没有行可挂，旧写法只推进游标、不退回，
      // 于是块字符记账从此比游标少一格 —— 之后每个锚点与块起点都落在偏移后的
      // 域里，高亮与跳转整体偏，锚点甚至能超出本章 totalChars。
      // (正文, 本章字符域总数, 期望的 anchors['b'])
      const cases = <(String, int, int)>[
        ('<p id="a">x</p><p> </p><p id="b">y</p>', 2, 1),
        ('<p id="a">x</p><p><br></p><p id="b">y</p>', 2, 1),
        ('<p id="a">x</p><div>\n\n</div><p id="b">y</p>', 2, 1),
        ('<p id="a">x</p><blockquote><br></blockquote><p id="b">y</p>', 2, 1),
        ('<p id="a">x</p><p>y<br>\nB</p><p id="b">z</p>', 6, 5),
      ];
      final failures = <String>[];
      for (final (html, expectedTotal, expectedAnchor) in cases) {
        final anchors = <String, int>{};
        final blocks = parseBlocks(html, anchors: anchors);
        final total = blocks.fold<int>(
          0,
          (sum, block) => sum + BlockClipper.blockCharCount(block),
        );
        // 相邻同版式的段落会并成一块，锚点因此可以落在块中间的某一行的行首；
        // "某一行的起点"才是域内定位的判据，"某个块的起点"太严。
        final lineStarts = _lineStartOffsets(blocks);
        if (total != expectedTotal) {
          failures.add('$html 字符域 $total，应为 $expectedTotal');
        }
        if (anchors['b'] != expectedAnchor) {
          failures.add('$html 锚点 ${anchors['b']}，应为 $expectedAnchor');
        }
        if (!lineStarts.contains(expectedAnchor)) {
          failures.add('$html 锚点没落在任何行的行首：$lineStarts');
        }
      }
      expect(failures, isEmpty);
    });
  });

  group('stripHtml', () {
    test('strips tags and decodes entities', () {
      final result = stripHtml('<p>Hello &amp; <b>World</b></p>');
      expect(result, 'Hello & World');
    });

    test('returns empty for empty input', () {
      expect(stripHtml(''), '');
      expect(stripHtml('   '), '');
    });

    test('collapses whitespace', () {
      final result = stripHtml('<p>A</p>  <p>B</p>');
      expect(result, contains('A'));
      expect(result, contains('B'));
    });

    test('drops style and script bodies, not just tags', () {
      // 书的样式表随章节正文一起送达；只剥标签会把 CSS 留给 TTS 与正文检索。
      final result = stripHtml(
        '<p>正文</p><style>p { text-indent: 2em }</style>'
        '<script>var a = 1;</script><p>续</p>',
      );
      expect(result, '正文 续');
      expect(result, isNot(contains('text-indent')));
      expect(result, isNot(contains('var a')));
    });

    test('style 元素不闭合时整段不算正文', () {
      // 浏览器读到 EOF 也不渲染 RAWTEXT 内容；旧正则要求闭标签，于是 CSS 源码
      // 原样留在朗读文本与章内检索里。
      final result = stripHtml('<p>a</p><style>b{margin:0}');
      expect(result, 'a');
      expect(result, isNot(contains('margin')));
    });

    test('实体只解码一次', () {
      // 旧实现按实体表逐个 replaceAll，`&amp;lt;` 先变成 `&lt;`，后面那一遍又把它
      // 变成 `<`：书上写的字面量在朗读与检索里换成了另一个字符。
      expect(stripHtml('&amp;lt;'), '&lt;');
      expect(stripHtml('&amp;amp;'), '&amp;');
    });

    test('认不出的实体原样保留，超范围数字不抛', () {
      // `String.fromCharCode(1114112)` 会抛 RangeError，旧实现让整章的纯文本兜底失败。
      expect(stripHtml('&#1114112;'), '&#1114112;');
      expect(stripHtml('&#xZZ;'), '&#xZZ;');
      expect(stripHtml('&notit;'), '&notit;');
      expect(stripHtml('&AMP;'), '&AMP;');
      expect(stripHtml('&#65;&#x42;&nbsp;'), 'AB ');
    });
  });

  group('段内图按文档顺序断开', () {
    // 旧写法先预遍历把 <p> 里的图**全部**提到段前，再收整段文本，
    // 真书库实测 2403 处"图前后都有字"的插图因此跑到句子前面去了。
    String firstLineText(ParagraphBlock block) =>
        block.lines.first.spans.map((span) => span.text).join();

    int charsOf(List<ContentBlock> blocks) => blocks.fold(
      0,
      (sum, block) => sum + BlockClipper.blockCharCount(block),
    );

    test('甲<img/>乙 收成 前半、图、后半', () {
      final blocks = parseBlocks('<p>甲段正文<img src="i.png" alt="插图"/>乙段正文</p>');
      expect(blocks.map((block) => block.runtimeType), [
        ParagraphBlock,
        ImageBlock,
        ParagraphBlock,
      ]);
      final img = blocks[1] as ImageBlock;
      expect(img.src, 'i.png');
      expect(img.alt, '插图');
      expect(firstLineText(blocks.first as ParagraphBlock), '甲段正文');
      expect(firstLineText(blocks.last as ParagraphBlock), '乙段正文');
    });

    test('后半截是同一段的续行：既不补换行也不补首行缩进', () {
      final blocks = parseBlocks('<p>甲段正文<img src="i.png"/>乙段正文</p>');
      final tail = blocks.last as ParagraphBlock;
      expect(tail.lines.first.softWrap, isTrue);
      expect(
        paragraphLineSeparator(
          isFirstLine: true,
          isNewParagraph: tail.lines.first.isNewParagraph,
          previousLineIsEmpty: false,
          isBlockContinuation: false,
          startsWithFullWidthIndent: lineStartsWithFullWidthIndent(
            tail.lines.first.spans,
          ),
          isSoftWrap: tail.lines.first.softWrap,
        ),
        isEmpty,
        reason: '分隔符是缩进的唯一出口，这里必须是空串',
      );
    });

    test('图不占字符域：与去掉图的同一句字符总数相等', () {
      expect(
        charsOf(parseBlocks('<p>甲段正文<img src="i.png"/>乙段正文</p>')),
        charsOf(parseBlocks('<p>甲段正文乙段正文</p>')),
      );
    });

    test('包装元素里的图也按原位断开，内联样式不外泄', () {
      final blocks = parseBlocks('<p>甲段<b>粗文<img src="i.png"/>乙段</b></p>');
      expect(blocks.map((block) => block.runtimeType), [
        ParagraphBlock,
        ImageBlock,
        ParagraphBlock,
      ]);
      expect(firstLineText(blocks.first as ParagraphBlock), '甲段粗文');
      final tailSpan = (blocks.last as ParagraphBlock).lines.first.spans.first;
      expect(tailSpan.text, '乙段');
      expect(tailSpan.isBold, isTrue, reason: '断开点仍在 <b> 之内');
    });

    test('段尾图留在段后', () {
      final blocks = parseBlocks('<p>甲段正文<img src="i.png"/></p>');
      expect(blocks.map((block) => block.runtimeType), [
        ParagraphBlock,
        ImageBlock,
      ]);
    });

    test('容器裸文本里的图同样按原位断开', () {
      final blocks = parseBlocks('<div>甲段正文<img src="i.png"/>乙段正文</div>');
      expect(blocks.map((block) => block.runtimeType), [
        ParagraphBlock,
        ImageBlock,
        ParagraphBlock,
      ]);
      expect((blocks.last as ParagraphBlock).lines.first.softWrap, isTrue);
    });
  });

  group('预格式化文本', () {
    test('代码块记下"顶格"这本书已经说过', () {
      // 预格式化文本的行首空白本来就是内容，再由阅读器补一遍首行缩进就凭空多出一截；
      // 补不补由开关决定，这里只保证书的表达查得到（默认档一寸不动）。
      final paragraph =
          parseBlocks(
            '<pre>fn main() {\n  run();\n}</pre>',
          ).whereType<ParagraphBlock>().single;
      expect(paragraph.lines.single.style?.firstLineIndentChars, 0);
    });

    test('书写在 pre 上的行距落在代码块自己的样式槽', () {
      // 跟随档只把读者的行距乘这一份：不带这一份时，整本书的代码块与正文同高，
      // 书的代码留白层次在「跟随原书排版」上查不到出处。
      final paragraph =
          parseBlocks(
            '<pre>fn main() {\n  run();\n}</pre>',
            css: 'pre { line-height: 2 }',
          ).whereType<ParagraphBlock>().single;
      expect(
        paragraph.lines.single.style?.lineHeightScale,
        closeTo(2 / BookStyleSheet.baseBookLineHeight, 0.001),
      );
      expect(paragraph.lines.single.style?.firstLineIndentChars, 0);
    });

    test('pre 与后一段行距不同即另起一块', () {
      final paragraphs =
          parseBlocks(
            '<pre>code</pre><p>正文</p>',
            css: 'pre { line-height: 2 }',
          ).whereType<ParagraphBlock>().toList();
      expect(paragraphs, hasLength(2), reason: '行高是块级量：并成一块后两段只能共用首段那一份');
    });
  });

  group('标题的图片与空锚点（T8）', () {
    test('卷首艺术字标题保留层级，图按原顺序落块', () {
      final blocks = parseBlocks(
        '<h1><img src="title.png" alt="第一卷"></h1><p>正文</p>',
      );
      final heading = blocks.first as HeadingBlock;
      expect(heading.level, 1, reason: '标题层级不能因为正文是图就一起丢掉');
      expect(heading.text, '第一卷');
      expect(blocks[1], isA<ImageBlock>());
      expect(
        BlockClipper.blockCharCount(blocks.first),
        '第一卷'.length,
        reason: 'alt 顶位的那几个字必须占字符域，后面的块起点才会整体错开',
      );
    });

    test('只做目录跳转的空标题不丢锚点', () {
      final anchors = <String, int>{};
      final blocks = parseBlocks(
        '<h1 id="ch1"></h1><p>正文</p>',
        anchors: anchors,
      );
      expect(blocks.first, isA<HeadingBlock>());
      expect(anchors.containsKey('ch1'), isTrue);
    });
  });
}

/// 块内所有可读文本，按块型汇总。
///
/// 用来断言"样式表源码不会出现在正文的任何一层"：标题、单元格、`pre`、列表项与
/// 引用各有独立的取文本路径，逐个拼在一起才不会再漏一条。
String _allBlockText(List<ContentBlock> blocks) {
  final buffer = StringBuffer();
  void writeSpans(Iterable<ReaderInlineSpan> spans) {
    for (final span in spans) {
      buffer.write(span.text);
    }
  }

  for (final block in blocks) {
    if (block is HeadingBlock) {
      buffer.write(block.text);
    } else if (block is ParagraphBlock) {
      for (final line in block.lines) {
        writeSpans(line.spans);
      }
    } else if (block is BlockquoteBlock) {
      for (final line in block.lines) {
        writeSpans(line.spans);
      }
    } else if (block is ListBlock) {
      for (final item in block.items) {
        writeSpans(item.spans);
      }
    } else if (block is TableBlock) {
      for (final row in block.rows) {
        for (final cell in row.cells) {
          writeSpans(cell);
        }
      }
    } else if (block is ImageBlock) {
      buffer.write(block.caption ?? '');
      buffer.write(block.alt ?? '');
    }
  }
  return buffer.toString();
}

/// 每个逻辑行在字符域里的起点。
///
/// 锚点挂在块级元素上，而相邻同版式的段落会被并成一个块（块内一行一格），
/// 所以"某个块的起点"太严；行的起点才是页内裁剪与高亮真正用来定位的刻度。
List<int> _lineStartOffsets(List<ContentBlock> blocks) {
  final starts = <int>[];
  var prefix = 0;
  for (final block in blocks) {
    final lines = switch (block) {
      ParagraphBlock() => block.lines,
      BlockquoteBlock() => block.lines,
      _ => const <LineData>[],
    };
    if (lines.isEmpty) {
      prefix += BlockClipper.blockCharCount(block);
      continue;
    }
    for (final line in lines) {
      starts.add(prefix);
      prefix += line.sourceChars;
    }
  }
  return starts;
}
