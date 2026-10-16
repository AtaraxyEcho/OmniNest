import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/reader/domain/reader_annotation.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_stylesheet.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_annotations.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_content.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：R2 的"测量 vs 渲染"差分矩阵。
///
/// 审查 R1 里 Lane A 有六条断言停在"未自证"，逐条对着读两侧代码容易各看一半；
/// 这里改成用渲染当裁判：块测量高度必须等于该块在真实树里占据的高度，
/// 红的那条才是真缺陷，绿的一律从清单上划掉。
void main() {
  final settings = ReaderViewSettings(
    fontFamily: 'sans',
    fontSize: 18,
    lineHeight: 1.6,
  );

  Widget host(Widget child, {double textScale = 1.0}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: OmniNestTheme.from(AppThemePalette.dark),
    home: Scaffold(
      body: Builder(
        builder:
            (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child,
            ),
      ),
    ),
  );

  Future<({double height, double width})> renderedBlock(
    WidgetTester tester,
    String html, {
    int index = 0,
    double viewWidth = 800,
    double textScale = 1.0,
    List<ReaderAnnotation> annotations = const [],
    String css = '',
    ReaderViewSettings? mode,
    List<ContentBlock>? visibleBlocks,
    bool isFirstBlockContinuation = false,
  }) async {
    tester.view.physicalSize = Size(viewWidth, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        ReaderViewContent(
          htmlContent: html,
          settings: mode ?? settings,
          scrollController: controller,
          annotations: annotations,
          stylesheetCss: css,
          visibleBlocks: visibleBlocks,
          isFirstBlockContinuation: isFirstBlockContinuation,
        ),
        textScale: textScale,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();
    final items = find.byType(ReaderContentBlockItem, skipOffstage: false);
    expect(
      items.evaluate().length,
      greaterThan(index),
      reason: '第 $index 个块没有渲染出来，夹具或测试自身失真',
    );
    final size = tester.getSize(items.at(index));
    return (height: size.height, width: size.width);
  }

  double measuredHeight(
    String html,
    double width, {
    int index = 0,
    double textScale = 1.0,
    List<ReaderAnnotation> annotations = const [],
    String css = '',
    ReaderViewSettings? mode,
  }) {
    var blocks = parseBlocks(html, css: css);
    if (annotations.isNotEmpty) {
      blocks = ReaderContentAnnotationProjector.apply(blocks, annotations);
    }
    expect(index, lessThan(blocks.length), reason: '夹具没有产出该块');
    return ReaderPaginationEngine.measureBlockHeight(
      blocks[index],
      width,
      mode ?? settings,
      textScale: textScale,
    );
  }

  /// 裁剪片段的高度：与引擎装页同一条口径（逐视觉行累加 + 块自身留白）。
  ///
  /// `measureBlockHeight` 不带续接标志，页模式的续页必须按 `isContinuation`
  /// 另测一份，否则首行缩进会被算进不该缩进的那一页。
  double sliceMeasure(
    ContentBlock slice,
    ReaderViewSettings mode,
    double width,
    bool continuation,
  ) {
    final lines = ReaderPaginationEngine.measureVisualLines(
      slice,
      width,
      mode,
      1.0,
      blockGlobalOffset: 0,
      isContinuation: continuation,
    );
    final text = lines.fold<double>(0.0, (sum, line) => sum + line.height);
    return text + ReaderContentBlockItem.blockChromeHeight(slice, mode);
  }

  const longCell = '第一列内容很长需要用空格分隔的英文单词来撑开宽度 alpha beta gamma delta';
  // 1x1 透明 PNG：data URI 走渲染侧的内存解码，不引网络与 provider。
  const kTinyPngDataUri =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
      'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
  final listHtml =
      '<ul><li>${List<String>.filled(6, '列表项内容 item text').join(' ')}</li>'
      '<li>第二项</li></ul><p>后续正文</p>';
  final tableHtml =
      '<table><tr><th>$longCell</th><th>乙列</th></tr>'
      '<tr><td>$longCell</td><td>值</td></tr></table><p>后续正文</p>';
  final quoteHtml =
      '<blockquote>${List<String>.filled(5, '引用内容 quote text words').join(' ')}</blockquote>'
      '<p>后续正文</p>';
  final supParagraphHtml =
      '<p>${'带上标的正文 ' * 12}<sup>注</sup>${'更多文字 more text ' * 12}</p>';
  final supListHtml =
      '<ul><li>${'列表里带上标 ' * 10}<sup>注</sup>${'尾巴 tail words ' * 10}</li></ul>';
  const emptyTableHtml = '<table></table><p>后续正文</p>';

  group('块测量与渲染等高（R2 矩阵）', () {
    test('夹具前提：各块型确实被解析出来', () {
      expect(parseBlocks(listHtml).first, isA<ListBlock>());
      expect(parseBlocks(tableHtml).first, isA<TableBlock>());
      expect(parseBlocks(quoteHtml).first, isA<BlockquoteBlock>());
      expect(parseBlocks(emptyTableHtml), isNot(contains(isA<TableBlock>())));
    });

    testWidgets('列表块：测量高度等于渲染高度', (tester) async {
      final rendered = await renderedBlock(tester, listHtml);
      final measured = measuredHeight(listHtml, rendered.width);
      expect(
        measured,
        closeTo(rendered.height, 2.0),
        reason: '列表的块级间距与首项缩进若在两侧口径不同，差值即落位偏移',
      );
    });

    testWidgets('表格块：测量高度等于渲染高度', (tester) async {
      final rendered = await renderedBlock(tester, tableHtml);
      final measured = measuredHeight(tableHtml, rendered.width);
      expect(
        measured,
        closeTo(rendered.height, 2.0),
        reason: '渲染把表格放进横向滚动容器，单元格不折行；按列宽折行的测量会多算行',
      );
    });

    testWidgets('引用块：测量高度等于渲染高度', (tester) async {
      final rendered = await renderedBlock(tester, quoteHtml);
      final measured = measuredHeight(quoteHtml, rendered.width);
      expect(measured, closeTo(rendered.height, 2.0));
    });

    testWidgets('图片块：测量高度等于渲染高度', (tester) async {
      // 槽位高度与题注只在渲染侧算时，页框会把下一块顶下去：这里逼两侧同口径。
      final html =
          '<figure><img src="$kTinyPngDataUri"><figcaption>图注一行</figcaption></figure>'
          '<p>后续正文</p>';
      expect(parseBlocks(html).first, isA<ImageBlock>(), reason: '夹具没产出图片块');

      final rendered = await renderedBlock(tester, html);
      final measured = measuredHeight(html, rendered.width);
      expect(measured, closeTo(rendered.height, 2.0));
    });

    testWidgets('批注投影后的段落：测量高度等于渲染高度', (tester) async {
      // 投影会重建每一行；少复制一个字段（样式、行尾折叠记账）就会让测量与
      // 渲染分成两种行高，固定 itemExtent 下表现为页底裁字。
      final html =
          '<p>${'带批注的正文段落 annotation target text ' * 8}</p>'
          '<p>后续正文</p>';
      const annotation = ReaderAnnotation(
        id: 'a1',
        readerItemId: 'item-1',
        startOffset: 2,
        endOffset: 24,
        color: '#FFEB3B',
        createdAt: null,
      );

      final rendered = await renderedBlock(
        tester,
        html,
        annotations: const [annotation],
      );
      final measured = measuredHeight(
        html,
        rendered.width,
        annotations: const [annotation],
      );
      expect(measured, closeTo(rendered.height, 2.0));
    });

    testWidgets('上标段落：测量高度等于渲染高度', (tester) async {
      final rendered = await renderedBlock(tester, supParagraphHtml);
      final measured = measuredHeight(supParagraphHtml, rendered.width);
      expect(
        measured,
        closeTo(rendered.height, 2.0),
        reason: '上标/下标与小标题字号在测量侧被统一字号覆盖时，行数会两侧不一致',
      );
    });

    testWidgets('含上标的列表项：测量高度等于渲染高度', (tester) async {
      final rendered = await renderedBlock(tester, supListHtml);
      final measured = measuredHeight(supListHtml, rendered.width);
      expect(measured, closeTo(rendered.height, 2.0));
    });

    testWidgets('标题在 1.5 缩放下：测量高度等于渲染高度', (tester) async {
      const html = '<h2>标题样例</h2><p>正文</p>';
      final rendered = await renderedBlock(
        tester,
        html,
        viewWidth: 320,
        textScale: 1.5,
      );
      final measured = measuredHeight(html, rendered.width, textScale: 1.5);
      expect(measured, closeTo(rendered.height, 2.0));
    });

    testWidgets('正文在 1.5 缩放下：测量与渲染折同一套行', (tester) async {
      // 框架的 TextStyle.getTextStyle 只把 textScaler 乘到 fontSize 上，字距与词距原样
      // 透传；测量若按缩放后的字号推字距，一行能放下的字数就比渲染少。
      // 只看总高会漏掉这种"容量差 1"：文本长度不是容量整数倍时两边行数可能相同。
      // 先探一次实际宽度，按测量侧的行容量取整数倍造文本，容量再差 1 就多折一整行。
      final probeHtml = '<p>${'汉' * 200}</p><p>后续正文</p>';
      final probe = await renderedBlock(
        tester,
        probeHtml,
        viewWidth: 420,
        textScale: 1.5,
      );
      final probeLines = ReaderPaginationEngine.measureVisualLines(
        parseBlocks(probeHtml).first,
        probe.width,
        settings,
        1.5,
        blockGlobalOffset: 0,
      );
      expect(probeLines, hasLength(greaterThan(2)));
      final capacity = probeLines[1].globalEnd - probeLines[1].globalStart;
      expect(capacity, greaterThan(2));

      final html = '<p>${'汉' * (capacity * 3)}</p><p>后续正文</p>';
      final rendered = await renderedBlock(
        tester,
        html,
        viewWidth: 420,
        textScale: 1.5,
      );
      final measured = measuredHeight(html, rendered.width, textScale: 1.5);
      expect(
        measured,
        closeTo(rendered.height, 2.0),
        reason:
            '测量一行放 $capacity 字，渲染若按另一种字距口径就会改行数：'
            '测量 $measured 渲染 ${rendered.height}',
      );
    });

    testWidgets('行内代码在 1.5 缩放下：测量高度等于渲染高度', (tester) async {
      final html =
          '<p>${'说明文字 ' * 20}<code>npm install --save-exact pkg name</code>'
          '${'更多文字 more words ' * 20}</p><p>后续正文</p>';
      final rendered = await renderedBlock(
        tester,
        html,
        viewWidth: 460,
        textScale: 1.5,
      );
      final measured = measuredHeight(html, rendered.width, textScale: 1.5);
      expect(measured, closeTo(rendered.height, 2.0));
    });

    testWidgets('列表里的行内代码：测量高度等于渲染高度', (tester) async {
      final html =
          '<ul><li>说明文字 ${'word ' * 30}'
          '<code>npm install --save-exact some long package name</code></li>'
          '</ul><p>后续正文</p>';
      final rendered = await renderedBlock(tester, html);
      final measured = measuredHeight(html, rendered.width);
      expect(
        measured,
        closeTo(rendered.height, 2.0),
        reason:
            '行内代码的字号与字族若只在段落渲染侧表达，列表按正文宽度测量、'
            '按等宽字体绘制，同一项在两侧折出不同行数',
      );
    });

    testWidgets('列表首项不注入首行缩进：测量高度等于渲染高度', (tester) async {
      // 先读一次条目可用宽度，再把首项长度取到"正好差两个字宽"：注入缩进必然
      // 多折一行，容差之内没有第二条路，不必靠猜字号构造边界。
      final probe = await renderedBlock(
        tester,
        '<ul><li>探针</li></ul><p>正文</p>',
      );
      final textWidth =
          probe.width - ReaderContentBlockItem.listMarkerColumnWidth;
      final advance = settings.fontSize * 1.025; // 全角字宽 + .025em 字距
      final fit = (textWidth / advance).floor() - 1;
      final html = '<ul><li>${'字' * fit}</li></ul><p>正文</p>';

      final rendered = await renderedBlock(tester, html);
      final measured = measuredHeight(html, rendered.width);
      expect(
        measured,
        closeTo(rendered.height, 2.0),
        reason:
            '列表项的缩进位是符号列：测量再注入两个全角空格会多折一行，'
            '条目按一行绘制却按两行占槽',
      );
    });
  });

  group('跟随书籍行高的测绘差分（T2、T11）', () {
    // 17/17 本实测语料的样式表都写了行距：倍率只进一侧时，同一块在高度表与
    // 绘制里得到两种行盒，固定条目高度下就是页底裁字。闸门按文档口径收到 0.5px。
    final follow = settings.copyWith(followBookTypesetting: true);
    const bookCss =
        'p { line-height: 2; text-indent: 2em } '
        'blockquote { line-height: 2 } '
        'ul { line-height: 2 } '
        'pre { line-height: 2 } '
        'table { line-height: 2 } '
        'h2 { line-height: 2 }';
    final preHtml =
        '<pre>${List<String>.filled(6, 'int main() { return 0; }').join('\n')}</pre>'
        '<p>后续正文</p>';

    Future<void> expectBothModes(
      WidgetTester tester,
      String html, {
      int index = 0,
    }) async {
      for (final mode in [settings, follow]) {
        final rendered = await renderedBlock(
          tester,
          html,
          index: index,
          mode: mode,
          css: bookCss,
        );
        final measured = measuredHeight(
          html,
          rendered.width,
          index: index,
          mode: mode,
          css: bookCss,
        );
        expect(
          measured,
          closeTo(rendered.height, 0.5),
          reason:
              '${mode.followBookTypesetting ? '跟随' : '默认'}档：'
              '测量 $measured，渲染 ${rendered.height}',
        );
      }
    }

    test('夹具前提：行距与缩进确实被样式表表达出来', () {
      final paragraph = parseBlocks('<p>段</p>', css: bookCss).first;
      expect(
        (paragraph as ParagraphBlock).style!.lineHeightScale,
        closeTo(2 / BookStyleSheet.baseBookLineHeight, 0.001),
      );
      expect(
        parseBlocks(preHtml, css: bookCss).first is ParagraphBlock,
        isTrue,
        reason: 'pre 走的必须是段落通路，行高才有地方存',
      );
    });

    testWidgets('段落（含 WidgetSpan 首行缩进）：两档等高', (tester) async {
      await expectBothModes(
        tester,
        '<p>${'正文内容 body words ' * 30}</p><p>后续正文</p>',
      );
    });

    testWidgets('pre 里的空行要一起进高度表', (tester) async {
      // 空白视觉行没有字符可映射，测量侧以前直接跳过整行：块高少一行，
      // 固定条目高度下就是 RenderFlex overflow，翻页模式页底还会裁字。
      await expectBothModes(
        tester,
        '<pre>int main() {\n\n  return 0;\n}</pre><p>后续正文</p>',
      );
    });

    testWidgets('引用块：两档等高', (tester) async {
      await expectBothModes(
        tester,
        '<blockquote>${'引用内容 quote text words ' * 12}</blockquote><p>后续正文</p>',
      );
    });

    testWidgets('列表块：两档等高', (tester) async {
      await expectBothModes(tester, listHtml, index: 0);
    });

    testWidgets('表格块：两档等高', (tester) async {
      await expectBothModes(tester, tableHtml, index: 0);
    });

    testWidgets('pre 块：两档等高', (tester) async {
      await expectBothModes(tester, preHtml, index: 0);
    });

    testWidgets('标题块：两档等高', (tester) async {
      await expectBothModes(tester, '<h2>章标题</h2><p>正文</p>', index: 0);
    });

    testWidgets('书的行距只在跟随档进版面', (tester) async {
      // 关掉开关必须严格用读者的行距，打开才乘书自己的倍率：两档等高说明
      // 倍率根本没进渲染，两侧同错时测绘差分看不出问题。
      final html = '<p>${'正文内容 body words ' * 30}</p><p>后续正文</p>';
      final off = await renderedBlock(
        tester,
        html,
        mode: settings,
        css: bookCss,
      );
      final on = await renderedBlock(tester, html, mode: follow, css: bookCss);
      expect(
        on.height,
        greaterThan(off.height),
        reason: '跟随档没把 line-height 乘进行高：两档高度一样',
      );
    });

    testWidgets('pre 的书行距在跟随档进版面', (tester) async {
      final off = await renderedBlock(
        tester,
        preHtml,
        mode: settings,
        css: bookCss,
      );
      final on = await renderedBlock(
        tester,
        preHtml,
        mode: follow,
        css: bookCss,
      );
      expect(
        on.height,
        greaterThan(off.height),
        reason: '代码块的行距仍按读者的行距算，书的表达整本丢失',
      );
    });

    testWidgets('跨页裁剪出的两个片段：测量等于渲染（T6）', (tester) async {
      final html = '<p>${'正文内容 body words ' * 60}</p><p>后续正文</p>';
      for (final mode in [settings, follow]) {
        final blocks = parseBlocks(html, css: bookCss);
        final whole = blocks.first as ParagraphBlock;
        final total = BlockClipper.blockCharCount(whole);
        final cut = (total / 2).floor();
        final head = BlockClipper.trimBlockByCharRange(whole, 0, cut)!;
        final tail = BlockClipper.trimBlockByCharRange(whole, cut, total)!;

        // 两片合起来必须正好等于整块：多一格或少一格都会在页链上重复或漏字。
        expect(
          BlockClipper.blockCharCount(head) + BlockClipper.blockCharCount(tail),
          total,
          reason: '裁剪片段的字符域不闭合',
        );

        final headRender = await renderedBlock(
          tester,
          html,
          mode: mode,
          css: bookCss,
          visibleBlocks: [head],
        );
        final tailRender = await renderedBlock(
          tester,
          html,
          mode: mode,
          css: bookCss,
          visibleBlocks: [tail],
          isFirstBlockContinuation: true,
        );
        expect(
          sliceMeasure(head, mode, headRender.width, false),
          closeTo(headRender.height, 0.5),
          reason: '页首片段的缩进或段距在两侧口径不同',
        );
        expect(
          sliceMeasure(tail, mode, tailRender.width, true),
          closeTo(tailRender.height, 0.5),
          reason: '续页片段重复收了首行缩进或段尾间距',
        );
      }
    });

    testWidgets('两端对齐下首行缩进盒子仍占两个整字宽（T1）', (tester) async {
      // 缩进曾经是注入在行首的全角空格：两端对齐把行首空白算进可压缩空间，
      // 一整行被拉开时空格折成零宽，读者看到的首行就顶格了。盒子不可拉伸。
      final html = '<p>${'正文内容 body words ' * 40}</p><p>后续正文</p>';
      for (final mode in [settings, follow]) {
        await renderedBlock(tester, html, mode: mode, css: bookCss);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byType(RichText).first,
        );
        // 排版文本的第 0 格是缩进盒子的对象替换字符，第 1 格才是正文首字。
        final boxes = paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 1, extentOffset: 2),
        );
        expect(boxes, isNotEmpty, reason: '取不到首字的选择框');
        expect(
          boxes.first.left,
          greaterThanOrEqualTo(mode.fontSize * 2),
          reason:
              '${mode.followBookTypesetting ? '跟随' : '默认'}档的首行缩进被两端对齐压掉了：'
              '首字左边缘 ${boxes.first.left}',
        );
      }
    });
  });

  group('装页预算与块自身间距', () {
    const pageWidth = 360.0;
    const pageHeight = 640.0;

    test('逐页累加的块高不超过页高', () {
      final blocks = parseBlocks(
        [
          '<h2>章标题</h2>',
          '<p>${'正文内容 body text ' * 40}</p>',
          '<blockquote>${'引用内容 quote text ' * 12}</blockquote>',
          '<h3>小节标题</h3>',
          '<ul>'
              '${List<String>.filled(6, '列表项 list item text').map((t) => '<li>$t</li>').join()}'
              '</ul>',
          '<p>${'再续一段 more body words ' * 40}</p>',
          '<blockquote>短句引用。</blockquote>',
          '<h3>又一节</h3>',
          '<p>${'收尾正文 trailing text ' * 40}</p>',
        ].join(),
      );
      final totalChars = blocks.fold<int>(
        0,
        (sum, block) => sum + BlockClipper.blockCharCount(block),
      );

      var offset = 0;
      var pageCount = 0;
      while (pageCount < 60) {
        final slice = ReaderPaginationEngine.computePage(
          blocks,
          pageWidth,
          pageHeight,
          settings,
          offset,
        );
        if (slice == null) break;
        final visible =
            slice.endCharOffset > slice.startCharOffset
                ? BlockClipper.clipBlocksByCharRange(
                  blocks,
                  slice.startCharOffset,
                  slice.endCharOffset,
                )
                : BlockClipper.clipBlocksByIndexRange(
                  blocks,
                  slice.startIndex,
                  slice.endIndex,
                );
        final used = visible.fold<double>(
          0.0,
          (sum, block) =>
              sum +
              ReaderPaginationEngine.measureBlockHeight(
                block,
                pageWidth,
                settings,
              ),
        );
        expect(
          used,
          lessThanOrEqualTo(pageHeight + 2.0),
          reason:
              '第 $pageCount 页（起于字符 $offset）实际占据 $used px，页高只有 '
              '$pageHeight px：块自身的间距漏在预算外，多出的部分会被静默裁掉',
        );
        // 引擎自己的算术也不能算出超页的高度：整块放不下时那份间距属于下一页。
        // 真书语料里 walden 有 11 页"渲染侧没超、引擎自算超页一个引用块间距"，
        // 说明间距被预扣进了并不画这一块的那一页。
        expect(
          slice.accountedHeight,
          lessThanOrEqualTo(pageHeight + 2.0),
          reason:
              '第 $pageCount 页引擎自算 ${slice.accountedHeight} px > 页高 $pageHeight px，'
              '而本页实际只占 $used px：额度里留着下一页才画的间距',
        );
        final next =
            slice.cursorEnd >= 0 ? slice.cursorEnd : slice.endCharOffset;
        expect(next, greaterThan(offset), reason: '页链出现零宽页，无法推进');
        offset = next;
        pageCount++;
      }

      expect(pageCount, greaterThan(2), reason: '夹具太短，断不到多页场景');
      expect(offset, totalChars, reason: '页链没有覆盖整章字符');
    });

    test('下一页才画的块间距不进本页额度', () {
      // 页高取"正文一行放得下、正文一行加引用块间距放不下"这一档：块间距是渲染条目
      // 画在块首的，但整块被推到下一页时这一份不该留在本页的算术里。真书语料里
      // walden 有 11 页正是这样超出的（渲染侧 595，引擎自算 643.15）。
      const width = 360.0;
      const shortPage = 61.0;
      final blocks = parseBlocks('<p>短正文。</p><blockquote>引用内容。</blockquote>');

      final first = ReaderPaginationEngine.computePage(
        blocks,
        width,
        shortPage,
        settings,
        0,
      );
      expect(first, isNotNull);
      expect(
        first!.accountedHeight,
        lessThanOrEqualTo(shortPage + 2.0),
        reason: '本页只画了正文一行，引用块的 48px 间距不该记进来',
      );
      // 页链必须仍从引用块起头，一个字都不能漏。
      final second = ReaderPaginationEngine.computePage(
        blocks,
        width,
        shortPage,
        settings,
        first.cursorEnd >= 0 ? first.cursorEnd : first.endCharOffset,
      );
      expect(second, isNotNull);
      expect(
        second!.startCharOffset,
        greaterThan(first.startCharOffset),
        reason: '整块推页不能停在原处',
      );
    });

    test('表格高于页面时按行拆到下一页，行不丢不重', () {
      const width = 360.0;
      const tallPage = 640.0;
      final rowsHtml =
          List<String>.generate(
            30,
            (index) => '<tr><td>第 $index 行内容</td><td>乙列</td></tr>',
          ).join();
      final blocks = parseBlocks('<table>$rowsHtml</table>');
      final table = blocks.single as TableBlock;
      final total = BlockClipper.blockCharCount(table);
      expect(
        ReaderPaginationEngine.measureBlockHeight(table, width, settings),
        greaterThan(tallPage),
        reason: '夹具得真的高于一页，否则断不到拆分',
      );

      var offset = 0;
      var pages = 0;
      final paintedRows = <String>[];
      while (pages < 20) {
        final slice = ReaderPaginationEngine.computePage(
          blocks,
          width,
          tallPage,
          settings,
          offset,
        );
        if (slice == null) break;
        final visible = BlockClipper.clipBlocksByCharRange(
          blocks,
          slice.startCharOffset,
          slice.endCharOffset,
        );
        final fragment = visible.single as TableBlock;
        for (final row in fragment.rows) {
          paintedRows.add(row.cells.first.first.text);
        }
        expect(
          ReaderPaginationEngine.measureBlockHeight(fragment, width, settings),
          lessThanOrEqualTo(tallPage + 2.0),
          reason: '第 $pages 页的表格片段仍超页：按行拆分没有生效',
        );
        expect(
          slice.accountedHeight,
          lessThanOrEqualTo(tallPage + 2.0),
          reason: '第 $pages 页引擎自算 ${slice.accountedHeight} > 页高',
        );
        final next =
            slice.cursorEnd >= 0 ? slice.cursorEnd : slice.endCharOffset;
        expect(next, greaterThan(offset), reason: '页链在表格内部停住了');
        offset = next;
        pages++;
        if (offset >= total) break;
      }

      expect(pages, greaterThan(1), reason: '整张表一页装下，夹具失效');
      expect(offset, total, reason: '页链没有走完这张表');
      expect(
        paintedRows,
        table.rows.map((row) => row.cells.first.first.text).toList(),
        reason: '跨页以后每一行必须恰好出现一次，不丢不重',
      );
    });

    test('表格行裁剪保住列数与表头标记', () {
      final blocks = parseBlocks(
        '<table><tr><th>甲</th><th>乙</th></tr>'
        '<tr><td>数</td><td></td></tr><tr><td>据</td><td>值</td></tr></table>',
      );
      final table = blocks.single as TableBlock;
      final prefix = <int>[0];
      var total = 0;
      for (final row in table.rows) {
        total += row.cells.fold<int>(
          0,
          (sum, cell) => sum + cell.fold(0, (s, span) => s + span.text.length),
        );
        prefix.add(total);
      }

      // 切在第 2 行之后：前半两张、后半一张，列数与表头标记都要保住。
      final head = BlockClipper.clipBlocksByCharRange(blocks, 0, prefix[2]);
      final tail = BlockClipper.clipBlocksByCharRange(blocks, prefix[2], total);
      final headTable = head.single as TableBlock;
      final tailTable = tail.single as TableBlock;
      expect(headTable.rows, hasLength(2));
      expect(tailTable.rows, hasLength(1));
      expect(headTable.rows.first.cells, hasLength(2));
      expect(
        headTable.rows.last.cells,
        hasLength(2),
        reason: '空单元格也是列：丢掉它之后列宽与表头底色都会错位',
      );
      expect(
        BlockClipper.blockCharCount(headTable) +
            BlockClipper.blockCharCount(tailTable),
        total,
        reason: '裁剪前后字符必须守恒',
      );
      expect(tailTable.rows.first.cells.last.first.text, '值');
    });
  });

  group('测量基准样式与渲染同源', () {
    test('文字缩放只放大字号，字距按框架口径保持未缩放值', () {
      // 框架的 TextStyle.getTextStyle 只把 textScaler 乘到 fontSize 上。测量另算一份
      // 字距时，每字不到 0.3px 的差在行高容差里看不见，只会以"页底少一行"的形式
      // 在真机上出现，所以这条按表达式本身断言，而不是按高度断言。
      final scaled = settings.measurementBaseStyle(textScale: 1.5);
      expect(scaled.fontSize, settings.fontSize * 1.5);
      expect(scaled.letterSpacing, settings.bodyStyle.letterSpacing);
      expect(scaled.height, settings.bodyStyle.height);
      expect(scaled.fontFamily, settings.bodyStyle.fontFamily);
      expect(
        settings.measurementBaseStyle(),
        settings.bodyStyle,
        reason: 'textScale=1 时测量基准样式必须与渲染样式同一份值',
      );
    });
  });

  group('确定高度下的图片槽位', () {
    testWidgets('条目被高度表定死后，槽位仍按宽度公式而非反向钳制', (tester) async {
      const html = '<p>图前正文。</p><img src="https://example.invalid/a.png"/>';
      expect(parseBlocks(html), contains(isA<ImageBlock>()));
      final controller = ScrollController();
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(600, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final slot = ReaderPaginationEngine.imageSlotHeight(600);
      // 表里给这条图片的确定高度 = 槽位 + 上下内边距 48 + 容器边框 2。
      final extents = List<double>.filled(parseBlocks(html).length, slot);
      for (var i = 0; i < extents.length; i++) {
        extents[i] = parseBlocks(html)[i] is ImageBlock ? slot + 50 : 100;
      }
      await tester.pumpWidget(
        host(
          ReaderViewContent(
            htmlContent: html,
            settings: settings,
            scrollController: controller,
            blockExtents: extents,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == slot,
        ),
        findsWidgets,
        reason:
            '渲染把条目高度反向钳成 extent-54，图片就比高度表记的矮一截，'
            '题注还会在紧约束里被裁；带确定高度时槽位必须仍按宽度公式',
      );
    });
  });
}
