import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
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
          settings: settings,
          scrollController: controller,
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
  }) {
    final blocks = parseBlocks(html);
    expect(index, lessThan(blocks.length), reason: '夹具没有产出该块');
    return ReaderPaginationEngine.measureBlockHeight(
      blocks[index],
      width,
      settings,
      textScale: textScale,
    );
  }

  const longCell = '第一列内容很长需要用空格分隔的英文单词来撑开宽度 alpha beta gamma delta';
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
