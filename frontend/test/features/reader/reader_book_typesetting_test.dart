import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_stylesheet.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：书自己的排版意图怎么进层叠，以及进来之后测量与渲染是否仍然同源。
///
/// 跟随原书默认关闭，所以这一份用例同时守住两件事：关掉时读者看到的版面一寸没动，
/// 打开时书的段距与缩进同时进入测量、装页与绘制三处。
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
  final base = ReaderViewSettings(
    fontFamily: 'sans',
    fontSize: 18,
    lineHeight: 1.6,
  );
  final followBook = base.copyWith(followBookTypesetting: true);

  const indented = ParagraphStyleSpec(firstLineIndentChars: 3);
  const spaced = ParagraphStyleSpec(paragraphSpacingScale: 2.0);
  const aligned = ParagraphStyleSpec(textAlign: TextAlign.left);

  group('层叠取值', () {
    test('未跟随原书时一律用阅读器默认档', () {
      expect(base.firstLineIndentChars(indented), defaultFirstLineIndentChars);
      expect(
        base.paragraphSpacingScaleFor(
          bookStyle: spaced,
          hasTrailingSpacing: true,
        ),
        defaultParagraphSpacingScale,
      );
      expect(
        base.paragraphSpacingScaleFor(
          bookStyle: spaced,
          hasTrailingSpacing: false,
        ),
        0.0,
        reason: '阅读器档只认 <br><br> 信号，书表达过的段距不能越过开关生效',
      );
      expect(base.paragraphAlign(aligned), TextAlign.justify);
    });

    test('跟随原书时只接管书表达过的项', () {
      expect(followBook.firstLineIndentChars(indented), 3);
      expect(followBook.paragraphAlign(aligned), TextAlign.left);
      expect(
        followBook.firstLineIndentChars(null),
        defaultFirstLineIndentChars,
      );
      expect(followBook.paragraphAlign(null), TextAlign.justify);
      // 靠段距分段的书没有 <br><br>：打开开关后书的倍率直接生效，不看读者侧信号。
      expect(
        followBook.paragraphSpacingScaleFor(
          bookStyle: spaced,
          hasTrailingSpacing: false,
        ),
        2.0,
      );
      expect(
        followBook.paragraphSpacingScaleFor(
          bookStyle: null,
          hasTrailingSpacing: true,
        ),
        defaultParagraphSpacingScale,
      );
      expect(
        followBook.paragraphSpacingScaleFor(
          bookStyle: null,
          hasTrailingSpacing: false,
        ),
        0.0,
      );
    });

    test('书明确写 0 时按 0，不静默补回默认缩进', () {
      expect(
        followBook.firstLineIndentChars(
          const ParagraphStyleSpec(firstLineIndentChars: 0),
        ),
        0,
      );
    });
  });

  group('解析承载段落样式', () {
    test('文档内的 style 表达式落到所属段落', () {
      final blocks = parseBlocks(
        '<style>p { text-indent: 2em; margin-bottom: 1.5em; text-align: left }</style>'
        '<p>正文内容。</p>',
      );
      final paragraph = blocks.whereType<ParagraphBlock>().single;
      expect(paragraph.style?.firstLineIndentChars, 2);
      expect(paragraph.style?.paragraphSpacingScale, closeTo(1.5, 0.001));
      expect(paragraph.style?.textAlign, TextAlign.left);
      for (final line in paragraph.lines) {
        expect(line.style, same(paragraph.style), reason: '缩进按行取，行上必须带同一份');
      }
    });

    test('段距不同的相邻段落不再被合并成一块', () {
      final blocks = parseBlocks(
        '<style>'
        '.a { margin-bottom: 1em } .b { margin-bottom: 2em }'
        '</style>'
        '<p class="a">第一段。</p><p class="b">第二段。</p>',
      );
      final paragraphs = blocks.whereType<ParagraphBlock>().toList();
      expect(paragraphs, hasLength(2));
      expect(paragraphs[0].style?.paragraphSpacingScale, closeTo(1.0, 0.001));
      expect(paragraphs[1].style?.paragraphSpacingScale, closeTo(2.0, 0.001));
    });

    test('书没有表达时样式槽为空，默认档照旧', () {
      final blocks = parseBlocks('<p>正文内容。</p>');
      final paragraph = blocks.whereType<ParagraphBlock>().single;
      expect(paragraph.style, isNull);
      expect(paragraph.lines.single.style, isNull);
    });
  });

  group('块间距与绘制同源', () {
    ParagraphBlock blockWith(
      ParagraphStyleSpec? style, {
      bool trailing = true,
    }) => ParagraphBlock(
      lines: [LineData(spans: const [], style: style)],
      hasTrailingSpacing: trailing,
      style: style,
    );

    test('段距倍率同时进块高与渲染，两侧不再各算一份', () {
      for (final settings in [base, followBook]) {
        for (final style in [null, spaced]) {
          for (final trailing in [true, false]) {
            final block = blockWith(style, trailing: trailing);
            final scale = settings.paragraphSpacingScaleFor(
              bookStyle: style,
              hasTrailingSpacing: trailing,
            );
            expect(
              ReaderContentBlockItem.blockChromeHeight(block, settings),
              settings.fontSize * scale,
              reason: '$trailing/$style 下块高与渲染取的间距不是同一份',
            );
          }
        }
      }
    });

    testWidgets('打开跟随原书后，测量高度仍等于条目实际渲染高度', (tester) async {
      const width = 360.0;
      final body =
          '<style>'
          'p { text-indent: 0em; margin-bottom: 2.2em }'
          '</style>'
          '<p>${'正文内容 body words ' * 12}<br><br></p>';
      final blocks = parseBlocks(body);
      final paragraph = blocks.whereType<ParagraphBlock>().toList();
      expect(paragraph, isNotEmpty);

      for (final settings in [base, followBook]) {
        for (var index = 0; index < paragraph.length; index++) {
          final block = paragraph[index];
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                // 滚动视图给子项无限高，Column 才会收拢到内容高度；
                // 直接放在屏幕里条目会填满视口，量到的是视口高而不是块高。
                body: SingleChildScrollView(
                  child: SizedBox(
                    width: width,
                    child: ReaderContentBlockItem(
                      block: block,
                      settings: settings,
                      itemId: 'item',
                      chapterId: 'chapter',
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final rendered = tester.getSize(find.byType(ReaderContentBlockItem));
          expect(
            ReaderPaginationEngine.measureBlockHeight(block, width, settings),
            closeTo(rendered.height, 2.0),
            reason:
                '第 $index 段在 ${settings.followBookTypesetting ? '跟随' : '不跟随'}'
                '原书时测量与渲染不等高',
          );
        }
      }
    });

    testWidgets('跟随原书时缩进按书的字数注入，关闭时保持默认两个字宽', (tester) async {
      const width = 360.0;
      final block =
          parseBlocks(
            '<style>p { text-indent: 0em }</style><p>第一段。</p><p>第二段。</p>',
          ).whereType<ParagraphBlock>().single;

      String painted() {
        final richText = tester.widget<RichText>(find.byType(RichText).first);
        return richText.text.toPlainText();
      }

      Future<void> pump(ReaderViewSettings settings) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: width,
                child: ReaderContentBlockItem(
                  block: block,
                  settings: settings,
                  itemId: 'item',
                  chapterId: 'chapter',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      // 缩进是定宽盒子，纯文本里只剩一个对象替换字符；宽度差异只能从盒子宽度上看。
      await pump(base);
      expect(painted(), startsWith('￼'));
      await pump(followBook);
      expect(painted(), startsWith('第一段。'));
    });
  });

  group('引用块按书的表达分行分块', () {
    // P&P 书信的真实形状：header 右对齐，里面两个 p 是两行日期，正文段落跟着。
    // 旧实现把 header 摊平成一行、样式一律回落到引用块那份，抬头既没右对齐也不
    // 去缩进，两行还并成一行。
    const letterHtml =
        '<style>blockquote.z3998-letter { margin-bottom: 1em } '
        '.z3998-letter header { text-align: right } '
        '.z3998-letter p { text-indent: 0em; margin-bottom: 0em }</style>'
        '<blockquote class="z3998-letter">'
        '<header><p class="first-child">Hunsford, near Westerham, Kent,</p>'
        '<p>15th October.</p></header>'
        '<p>Body words.</p></blockquote>';

    test('抬头与正文对齐不同即另起一块，下边距只落在最后一块', () {
      final quotes =
          parseBlocks(letterHtml).whereType<BlockquoteBlock>().toList();
      expect(quotes.length, 2, reason: '一个 Text.rich 只带一个对齐，混在一起的两种版式必须分块');
      expect(quotes.first.lines.length, 2, reason: 'header 里两个 p 是两行');
      expect(quotes.first.style?.textAlign, TextAlign.right);
      expect(quotes.first.style?.paragraphSpacingScale, isNull);
      expect(quotes.last.style?.textAlign, isNull);
      expect(
        quotes.last.style?.paragraphSpacingScale,
        closeTo(1.0, 0.001),
        reason: '书把留白写在 blockquote 之后，整段只出现一次',
      );
      expect(quotes.first.lines.first.style?.firstLineIndentChars, 0);
      expect(quotes.last.lines.single.style?.firstLineIndentChars, 0);
    });

    testWidgets('开关关闭时引用块保持起始对齐，打开才接管', (tester) async {
      final quote = parseBlocks(letterHtml).whereType<BlockquoteBlock>().first;
      Future<TextAlign?> paintedAlign(ReaderViewSettings settings) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 360,
                  child: ReaderContentBlockItem(
                    block: quote,
                    settings: settings,
                    itemId: 'q',
                    chapterId: 'q',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        return tester.widget<Text>(find.byType(Text).last).textAlign;
      }

      expect(
        await paintedAlign(base),
        isNull,
        reason: '引用块一直是起始对齐，关掉开关的读者看到的版面不能变',
      );
      expect(
        await paintedAlign(followBook),
        TextAlign.right,
        reason: '跟随原书时书在 header 上写的右对齐要接管',
      );
    });

    test('引用块的下边距同时进块高与渲染', () {
      final quote = parseBlocks(letterHtml).whereType<BlockquoteBlock>().last;
      // 尾段只收自己那一侧：另一侧属于上一段（同一引用的前一段）或不存在。
      const chrome =
          ReaderContentBlockItem.blockquoteOuterBottomPadding +
          ReaderContentBlockItem.blockquoteInnerVerticalPadding;
      expect(
        ReaderContentBlockItem.blockTrailingChrome(quote, base),
        chrome,
        reason: '未跟随原书时引用块只有固定 padding',
      );
      expect(
        ReaderContentBlockItem.blockTrailingChrome(quote, followBook) - chrome,
        closeTo(followBook.fontSize, 0.001),
        reason: '书的 1em 下边距必须进测量，否则页底把它裁掉',
      );
    });

    test('拆块不重复收盒子的上下留白', () {
      // 一个引用按对齐拆成 N 块时，留白属于整个引用：首块带上、尾块带下，中间块两头都不带。
      // 按 N 份收会让书信的抬头与正文之间凭空多出整份盒留白。
      final quotes =
          parseBlocks(letterHtml).whereType<BlockquoteBlock>().toList();
      expect(quotes.length, 2);
      expect(quotes.first.hasTopPadding, isTrue);
      expect(quotes.first.hasBottomPadding, isFalse, reason: '与下一段相接的一侧不再留白');
      expect(quotes.last.hasTopPadding, isFalse);
      expect(quotes.last.hasBottomPadding, isTrue);
      const wholeBoxChrome =
          ReaderContentBlockItem.blockquoteOuterTopPadding +
          ReaderContentBlockItem.blockquoteOuterBottomPadding +
          ReaderContentBlockItem.blockquoteInnerVerticalPadding * 2;
      expect(
        quotes.fold<double>(
          0,
          (sum, quote) =>
              sum + ReaderContentBlockItem.blockChromeHeight(quote, base),
        ),
        closeTo(wholeBoxChrome, 0.001),
        reason: '两块合起来的留白必须等于未拆时的一块',
      );
    });
  });

  group('靠上边距分段的书', () {
    // pgdp 的写法是 `p { margin-top: 1em; margin-bottom: 0 }` 并在注释里明说
    // "use only top-margin for spacing"。只认下边距的话整章段距为 0。
    const topMarginHtml =
        '<style>p { margin-top: 1em; margin-bottom: 0 }</style>'
        '<div><p>第一段。</p>\n<p>第二段。</p>\n<p>第三段。</p></div>';

    const plainHtml = '<div><p>第一段。</p>\n<p>第二段。</p>\n<p>第三段。</p></div>';

    int charsOf(List<ContentBlock> blocks) => blocks.fold(
      0,
      (sum, block) => sum + BlockClipper.blockCharCount(block),
    );

    test('下一段的上边距折成前一段的尾间距，段与段不再合并', () {
      final blocks =
          parseBlocks(topMarginHtml).whereType<ParagraphBlock>().toList();
      expect(blocks, hasLength(3), reason: '书用段距分段时不能把三段并成一块');
      expect(blocks[0].style?.paragraphSpacingScale, closeTo(1.0, 0.001));
      expect(blocks[1].style?.paragraphSpacingScale, closeTo(1.0, 0.001));
      expect(
        blocks[2].style?.paragraphSpacingScale,
        closeTo(0.0, 0.001),
        reason: '最后一段后面没有兄弟，留白不该凭空出现',
      );
      expect(
        blocks[0].style?.topMarginScale,
        isNull,
        reason: '折进尾间距之后前间距即失效，两侧不能再各扣一次',
      );
    });

    test('折算只改留白，不改字符域', () {
      expect(
        charsOf(parseBlocks(topMarginHtml)),
        charsOf(parseBlocks(plainHtml)),
        reason: '样式与折叠都不许新增或吞掉源字符，偏移域永远是原文',
      );
    });

    test('开关关闭时段距不进高度，打开时每段各扣一次', () {
      for (final block
          in parseBlocks(topMarginHtml).whereType<ParagraphBlock>()) {
        expect(
          ReaderContentBlockItem.blockChromeHeight(block, base),
          0.0,
          reason: '未跟随原书时读者看到的版面一寸没动',
        );
      }
      final spaced = parseBlocks(
        topMarginHtml,
      ).whereType<ParagraphBlock>().take(2);
      for (final block in spaced) {
        expect(
          ReaderContentBlockItem.blockChromeHeight(block, followBook),
          closeTo(followBook.fontSize, 0.001),
          reason: '书的 1em 上边距必须进块高，否则页底把它裁掉',
        );
      }
    });
  });

  group('样式改动触发缓存失效', () {
    test('切换跟随原书会另起一份布局数据，偏移域不跟着动', () async {
      final loader = ReaderContentLoader(
        allChapters: [ReaderChapter(id: 'c1', chapterNumber: 1, title: '第一章')],
      );
      final content = ReaderChapterContent(
        title: '第一章',
        content:
            '<style>p { margin-bottom: 2.4em }</style>'
            '<p>${'正文内容 body words ' * 40}</p>',
      );

      Future<ChapterData> load(ReaderViewSettings settings) =>
          loader.loadChapter(
            chapterId: 'c1',
            content: content,
            pageWidth: 400,
            pageHeight: 700,
            settings: settings,
          );

      final readerDefault = await load(base);
      final bookDefault = await load(followBook);

      expect(
        identical(readerDefault, bookDefault),
        isFalse,
        reason: '开关换档仍复用同一份 ChapterData，版面就不会有任何反应',
      );
      expect(
        bookDefault.cumulativeHeights.last,
        greaterThan(readerDefault.cumulativeHeights.last),
        reason: '书用 margin 分段，打开后段距必须进高度表',
      );
      expect(
        bookDefault.totalChars,
        readerDefault.totalChars,
        reason: '排版只能改像素，偏移域永远是原文字符',
      );
    });
  });

  group('零块章节的兜底', () {
    test('封面章只剩样式表时，兜底不拿 CSS 当正文', () async {
      // 真书证据：西遊記 wrap0000.xhtml 的 body 只有 `<div><svg><image/></svg></div>`，
      // parseBlocks 出 0 块。样式表随正文一起进 body 之后，兜底若按裸剥标签取文本，
      // 封面就会整页显示这本书的 CSS 源码，并把本章字符数撑到五千多，进度分母跟着错。
      final loader = ReaderContentLoader(
        allChapters: [
          ReaderChapter(id: 'cover', chapterNumber: 1, title: '封面'),
        ],
      );
      final css = 'p { margin-bottom: 0; text-indent: 1em }';
      final data = await loader.loadChapter(
        chapterId: 'cover',
        content: ReaderChapterContent(
          title: '封面',
          content:
              '<div class="cover"><svg><image xlink:href="cover.png"/></svg>'
              '</div><style>$css</style>',
        ),
        pageWidth: 400,
        pageHeight: 700,
        settings: base,
      );
      final text =
          data.blocks
              .whereType<ParagraphBlock>()
              .expand((block) => block.lines)
              .expand((line) => line.spans)
              .map((span) => span.text)
              .join();
      expect(text, isNot(contains('margin-bottom')));
      expect(text, isNot(contains('text-indent')));
      expect(text, isNot(contains('svg')));
      expect(
        data.totalChars,
        lessThan(200),
        reason: '兜底文本进了 CSS 源码就会把这一章的字符域撑开',
      );
    });
  });

  group('默认档必须真的补出缩进', () {
    // 文件里没写缩进是常态（这份语料的段落就是裸 `<p>`）。开关关掉时读者看到的分段
    // 全靠阅读器自己补：每一段段首都得有默认的两个全角空格，少一段就是"开关没作用"。
    const shapes = <String, String>{
      '相邻 p 合并成一块': '<p>甲段正文一二三</p><p>乙段正文一二三</p>',
      'p 内相邻 br': '<p>甲段正文一二三<br><br>乙段正文一二三</p>',
      'div 包 p': '<div><p>甲段正文一二三</p><p>乙段正文一二三</p></div>',
      '容器裸文本空行分段': '<div>甲段正文一二三\n\n乙段正文一二三</div>',
      'body 直属裸文本空行分段': '甲段正文一二三\n\n乙段正文一二三',
      '源码自己写了全角缩进': '<p>　　甲段正文一二三</p><p>　　乙段正文一二三</p>',
    };

    for (final entry in shapes.entries) {
      test('${entry.key}：两段都带默认缩进', () {
        final blocks = parseBlocks(entry.value);
        final painted = blocks
            .map((block) => paintedBlock(block, base))
            .join('\u0000');
        expect(painted, contains('　　甲段正文'), reason: entry.key);
        expect(painted, contains('　　乙段正文'), reason: entry.key);
      });
    }
  });

  group('书的表达到段落的三条通路', () {
    int charsOf(List<ContentBlock> blocks) => blocks.fold(
      0,
      (sum, block) => sum + BlockClipper.blockCharCount(block),
    );

    test('整本写在 body 上的缩进落到每一个段落', () {
      // 真书证据：三体全书的缩进只有 `body { text-indent: 2em }` 这一条，
      // 没有一个 p 自己带样式。继承不通这一层，开关两头就都是默认档。
      final blocks = parseBlocks(
        '<style>body { text-indent: 2em; text-align: justify }</style>'
        '<p>第一段正文</p><p>第二段正文</p>',
      );
      final paragraph = blocks.whereType<ParagraphBlock>().single;
      expect(paragraph.style?.firstLineIndentChars, 2, reason: '祖先表达的缩进必须查得到');
      expect(paragraph.style?.textAlign, TextAlign.justify);
      expect(paintedBlock(paragraph, followBook), startsWith('　　第一段正文'));
      expect(paintedBlock(paragraph, followBook), contains('\n　　第二段正文'));
    });

    test('容器裸文本读容器自己的表达', () {
      // `<p>` 那条通路一直取样式表，裸文本这条不取，等于同一本书里带标签的段落
      // 跟随原书、写成裸文本的段落不跟随。
      final blocks = parseBlocks(
        '<style>.poem { text-indent: 0em; text-align: center }</style>'
        '<div class="poem">甲段正文一二三\n\n乙段正文一二三</div>',
      );
      final paragraph = blocks.whereType<ParagraphBlock>().single;
      expect(paragraph.style?.firstLineIndentChars, 0);
      expect(paragraph.style?.textAlign, TextAlign.center);
      expect(paintedBlock(paragraph, base), startsWith('　　甲段正文一二三'));
      expect(paintedBlock(paragraph, base), contains('\n　　乙段正文一二三'));
      expect(paintedBlock(paragraph, followBook), startsWith('甲段正文一二三'));
      expect(paintedBlock(paragraph, followBook), contains('\n乙段正文一二三'));
    });

    test('源文本用全角空格写的缩进按书的字数跟随，默认档不动', () {
      final blocks = parseBlocks('<p>　　　甲段正文一二三</p><p>　　　乙段正文一二三</p>');
      final paragraph = blocks.whereType<ParagraphBlock>().single;
      expect(paragraph.lines, hasLength(2));
      for (final line in paragraph.lines) {
        expect(line.style?.firstLineIndentChars, 3);
      }
      expect(paintedBlock(paragraph, base), startsWith('　　甲段正文一二三'));
      expect(
        paintedBlock(paragraph, followBook),
        startsWith('　　　甲段正文一二三'),
        reason: '书自己空了三个全角，跟随档就该是三个',
      );
      expect(paintedBlock(paragraph, followBook), contains('\n　　　乙段正文一二三'));
    });

    test('样式表明写的缩进压过源文本的字面空格', () {
      final blocks = parseBlocks(
        '<style>p { text-indent: 0em }</style><p>　　　甲段正文</p>',
      );
      final paragraph = blocks.whereType<ParagraphBlock>().single;
      expect(paragraph.style?.firstLineIndentChars, 0);
      expect(paragraph.lines.single.style?.firstLineIndentChars, 0);
      expect(paintedBlock(paragraph, followBook), startsWith('甲段正文'));
    });

    test('源码里的空白行不会被误读成缩进', () {
      // 空白行上常挂着源码缩进（`甲\n     \n乙`），只认最后一个换行之后的那一截，
      // 否则一本根本没有缩进的书会凭空报出「书要求缩进」。
      final blocks =
          parseBlocks(
            '<p>甲段正文一二三\n     \n乙段正文一二三</p>',
          ).whereType<ParagraphBlock>().toList();
      // 空行仍是段落边界（在这里切成两块），但它不构成缩进表达。
      expect(blocks, hasLength(2));
      for (final block in blocks) {
        for (final line in block.lines) {
          expect(
            line.style?.firstLineIndentChars,
            isNull,
            reason: '行首没有版式缩进，缩进那一格必须留空',
          );
        }
      }
      expect(paintedBlock(blocks.first, followBook), startsWith('　　甲段正文一二三'));
      expect(
        paintedBlock(blocks.last, followBook),
        startsWith('　　乙段正文一二三'),
        reason: '两档都按默认档补两个字，而不是把源码空格当成书的缩进',
      );
      expect(paintedBlock(blocks.last, base), startsWith('　　乙段正文一二三'));
    });

    test('成串的半角空格按两个字折一个全角', () {
      final blocks = parseBlocks('<p>      甲段正文一二三</p>');
      final paragraph = blocks.whereType<ParagraphBlock>().single;
      expect(paragraph.lines.single.style?.firstLineIndentChars, 3);
    });

    testWidgets('标题居中只在跟随原书时接管，关闭档保持起始对齐', (tester) async {
      // 中文书的章名几乎都写着 `h1 { text-align: center }`；标题这条通路不取样式表，
      // 开关对整章最显眼的那一行就没有任何作用。
      final heading =
          parseBlocks(
            '<style>h1 { text-align: center }</style><h1>第一回</h1><p>正文内容。</p>',
          ).whereType<HeadingBlock>().single;
      expect(heading.align, TextAlign.center);

      Future<TextAlign?> paintedAlign(ReaderViewSettings settings) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: ReaderContentBlockItem(
                  block: heading,
                  settings: settings,
                  itemId: 'h',
                  chapterId: 'h',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        return tester.widget<Text>(find.byType(Text).first).textAlign;
      }

      expect(await paintedAlign(base), isNull, reason: '关掉开关的读者看到的标题位置不能跟着变');
      expect(await paintedAlign(followBook), TextAlign.center);
    });

    test('标题不接管字号：书里的 font-size 仍只做像素折算基准', () {
      final blocks = parseBlocks(
        '<style>h1 { font-size: 3em; text-align: center }</style><h1>章名</h1>',
      );
      final heading = blocks.whereType<HeadingBlock>().single;
      expect(heading.align, TextAlign.center);
      // 混字号会让同一章出现多把尺（测量/装页/渲染三处），这条缺口是刻意留的。
      expect(
        ReaderContentBlockItem.headingFontSize(
          level: 1,
          fontSize: base.fontSize,
        ),
        closeTo(
          base.fontSize * ReaderContentBlockItem.headingLevel1Scale,
          0.001,
        ),
      );
    });

    test('样式与字面缩进只改版面，不改字符域', () {
      const body = '<div>　　甲段\n\n乙段</div><p>　　丙段正文</p>';
      expect(
        charsOf(
          parseBlocks(
            body,
            css:
                'p { text-indent: 2em; margin-bottom: 1em } body { text-indent: 2em }',
          ),
        ),
        charsOf(parseBlocks(body)),
        reason: '带不带样式，每个源字符都要在字符域里有一个位置',
      );
    });
  });

  group('书用段距分段时按顶格跟随', () {
    // 真书证据：果麦《故事新编》整本只有 `p { margin-bottom: 1em }`，一处
    // text-indent 都没写。浏览器里它的 text-indent 计算值就是 initial 0，
    // 所以「跟随原书」必须顶格；再补两个字就成了"又缩进又留白"的双重分段。
    int charsOf(List<ContentBlock> blocks) => blocks.fold(
      0,
      (sum, block) => sum + BlockClipper.blockCharCount(block),
    );

    test('只写段距、没写缩进：关闭档一寸不动，打开档顶格且留白仍在', () {
      final paragraphs =
          parseBlocks(
            '<style>p { margin-bottom: 1em }</style>'
            '<p>第一段正文一二三</p><p>第二段正文一二三</p>',
          ).whereType<ParagraphBlock>().toList();
      expect(paragraphs, hasLength(2));
      expect(paintedBlock(paragraphs.first, base), startsWith('　　第一段正文'));
      expect(
        paintedBlock(paragraphs.first, followBook),
        startsWith('第一段正文'),
        reason: '书选了"顶格 + 段距"这一型，跟随档就该照它',
      );
      expect(
        ReaderContentBlockItem.blockChromeHeight(paragraphs.first, followBook),
        closeTo(followBook.fontSize * 1.0, 0.001),
        reason: '推断只动缩进，不能把书要的段距一起抹掉',
      );
      expect(
        ReaderContentBlockItem.blockChromeHeight(paragraphs.first, base),
        0.0,
        reason: '关闭档不花书的留白这一份',
      );
    });

    test('靠上边距分段的书同样推断为顶格', () {
      final paragraphs =
          parseBlocks(
            '<style>p { margin-top: 1em; margin-bottom: 0 }</style>'
            '<div><p>第一段。</p>\n<p>第二段。</p></div>',
          ).whereType<ParagraphBlock>().toList();
      expect(paragraphs, hasLength(2));
      expect(paintedBlock(paragraphs.first, followBook), startsWith('第一段'));
      expect(paintedBlock(paragraphs.first, base), startsWith('　　第一段'));
    });

    test('源文本写了字面缩进时，压过段距推断', () {
      final paragraph =
          parseBlocks(
            '<style>p { margin-bottom: 1em }</style><p>　　甲段正文一二三</p>',
          ).whereType<ParagraphBlock>().single;
      expect(
        paintedBlock(paragraph, followBook),
        startsWith('　　甲段正文'),
        reason: '书在字里写了缩进，推断让位',
      );
    });

    test('样式表明写缩进（哪怕写 0）时不走推断', () {
      final paragraph =
          parseBlocks(
            '<style>p { text-indent: 3em; margin-bottom: 1em }</style><p>甲段正文</p>',
          ).whereType<ParagraphBlock>().single;
      expect(paintedBlock(paragraph, followBook), startsWith('　　　甲段正文'));
    });

    test('书连样式表都没有提供时不推断（TXT 那一型）', () {
      final paragraph =
          parseBlocks('<p>甲段正文一二三</p>').whereType<ParagraphBlock>().single;
      expect(paintedBlock(paragraph, base), startsWith('　　甲段正文'));
      expect(
        paintedBlock(paragraph, followBook),
        startsWith('　　甲段正文'),
        reason: '这本书什么都没说，交给阅读器默认档',
      );
    });

    test('推断只补样式槽，不改字符域', () {
      const body =
          '<style>p { margin-bottom: 1em }</style>'
          '<p>第一段正文</p><p>第二段正文</p>';
      expect(
        charsOf(parseBlocks(body, css: 'p { margin-bottom: 1em }')),
        charsOf(parseBlocks(body)),
      );
    });
  });

  group('作者留的空行在跟随档折成段距', () {
    int charsOf(List<ContentBlock> blocks) => blocks.fold(
      0,
      (sum, block) => sum + BlockClipper.blockCharCount(block),
    );

    // TXT 与裸文本的书用空行分段：那一行白就是作者的段距意图。折算只花"块尾一份"，
    // 口径与 margin-top 的折叠一致；关闭档一律不给，默认档不因此多出留白。
    test('裸文本空行分段：每一段之后拿到一行白', () {
      final blocks =
          parseBlocks(
            '<div>甲段正文一二三\n\n乙段正文一二三\n\n丙段正文一二三</div>',
          ).whereType<ParagraphBlock>().toList();
      expect(blocks, hasLength(3));
      expect(blocks[0].style?.paragraphBlankGapLines, 1);
      expect(blocks[1].style?.paragraphBlankGapLines, 1);
      expect(
        blocks[2].style?.paragraphBlankGapLines,
        isNull,
        reason: '最后一段之后没有下一段，留白不能凭空出现',
      );
      expect(
        ReaderContentBlockItem.blockLeadingChrome(blocks.first, followBook),
        closeTo(followBook.fontSize * followBook.lineHeight, 0.001),
      );
      expect(
        ReaderContentBlockItem.blockChromeHeight(blocks.first, base),
        0.0,
        reason: '关闭档不因为文件用不用空行分段而改变版面',
      );
    });

    test('连排的空行折到上限为止', () {
      // 抓取残留与畸形文件会连排十几个空行，不设上限就是章末凭空多出半页白。
      final blocks =
          parseBlocks(
            '<div>甲段正文一二三\n\n\n\n\n乙段正文一二三</div>',
          ).whereType<ParagraphBlock>().toList();
      expect(blocks, hasLength(2));
      expect(blocks.first.style?.paragraphBlankGapLines, 4);
      expect(
        ReaderContentBlockItem.blockLeadingChrome(blocks.first, followBook),
        closeTo(
          followBook.fontSize * followBook.lineHeight * maxBlankLineGapLines,
          0.001,
        ),
        reason: '源里记的是真实行数，折算在消费点收敛到上限',
      );
    });

    test('切块与留白都不改字符域：块字符总数等于源内容长度', () {
      const body = '<div>甲段正文\n\n乙段正文</div>';
      // 4 字 + 两个换行 + 4 字：空行折进后一行的折叠量，一格都不能少也不能重。
      expect(charsOf(parseBlocks(body)), '甲段正文\n\n乙段正文'.length);
    });
  });
}

/// 按渲染侧同一条装配规则拼出这一块的绘制文本（含行首分隔符）。
String paintedBlock(ContentBlock block, ReaderViewSettings settings) {
  if (block is! ParagraphBlock) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < block.lines.length; i++) {
    final line = block.lines[i];
    buffer.write(
      paragraphLineSeparator(
        isFirstLine: i == 0,
        isNewParagraph: line.isNewParagraph,
        previousLineIsEmpty: i > 0 && block.lines[i - 1].spans.isEmpty,
        isBlockContinuation: false,
        startsWithFullWidthIndent: lineStartsWithFullWidthIndent(line.spans),
        indentChars: settings.firstLineIndentChars(line.style),
        isSoftWrap: line.softWrap,
      ),
    );
    buffer.writeAll(line.spans.map((span) => span.text));
  }
  return buffer.toString();
}
