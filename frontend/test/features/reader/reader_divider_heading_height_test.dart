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

/// 摘要：分割线与标题的测量高度必须等于渲染高度。
///
/// 审查 R1 的两条确认缺陷：`dividerHeight = 48.5` 只算了那条 0.5 的细线，
/// 渲染却是 `Padding(24/24)` + 带 16px 图标的 Stack；`headingHeight` 收下
/// textScale 却完全不参与计算，而标题 `Text` 吃环境 textScaler。
/// 整章测得后这些值会作为条目确定高度下发（itemExtentBuilder 给的是紧约束），
/// 于矮于真实的高度处被裁字。
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
      // copyWith 保留尺寸与内边距：裸 MediaQueryData 会把视口清成零尺寸。
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

  Future<({double height, double width})> renderedFirstBlock(
    WidgetTester tester,
    String html, {
    required double viewWidth,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(viewWidth, 900);
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
    expect(items, findsWidgets, reason: '正文块未渲染，测试自身失真');
    final size = tester.getSize(items.first);
    return (height: size.height, width: size.width);
  }

  /// 单个标题条目在**未被确定高度约束**时的自然高度。
  Future<double> naturalHeadingHeight(
    WidgetTester tester,
    String html, {
    required double viewWidth,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(viewWidth, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        Center(
          child: SizedBox(
            width: viewWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReaderContentBlockItem(
                  block: parseBlocks(html).first,
                  settings: settings,
                  itemId: 'b',
                  chapterId: 'c0',
                ),
              ],
            ),
          ),
        ),
        textScale: textScale,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();
    return tester.getSize(find.byType(ReaderContentBlockItem)).height;
  }

  group('分割线与标题测量', () {
    test('块级常量：分割线等于上下留白加字形高度', () {
      expect(
        ReaderPaginationEngine.dividerHeight,
        ReaderContentBlockItem.dividerVerticalPadding * 2 +
            ReaderContentBlockItem.dividerGlyphSize,
        reason: '测量与渲染必须引用同一组常量，否则改一侧就会静默漂移',
      );
    });

    testWidgets('分割线测量高度等于渲染高度', (tester) async {
      const html = '<hr/><p>分割线之后的正文。</p>';
      final rendered = await renderedFirstBlock(tester, html, viewWidth: 600);
      final block = parseBlocks(html).first;
      final measured = ReaderPaginationEngine.measureBlockHeight(
        block,
        rendered.width,
        settings,
      );
      expect(
        measured,
        closeTo(rendered.height, 2.0),
        reason: '分割线矮于真实高度会在确定高度约束下裁掉字形',
      );
    });

    testWidgets('标题在 1.5 缩放下测量高度等于渲染高度', (tester) async {
      const html = '<h2>标题文字样例</h2><p>标题之后的正文。</p>';
      final rendered = await renderedFirstBlock(
        tester,
        html,
        viewWidth: 600,
        textScale: 1.5,
      );
      final block = parseBlocks(html).first;
      final measured = ReaderPaginationEngine.measureBlockHeight(
        block,
        rendered.width,
        settings,
        textScale: 1.5,
      );
      expect(
        measured,
        closeTo(rendered.height, 2.0),
        reason: 'headingHeight 收下 textScale 却不用，大字体下标题条目被裁',
      );
    });

    testWidgets('一档标题收紧行高后测量等于渲染，且不溢出确定高度', (tester) async {
      // 稿子把 h1 的行高压到 1.25、字距收到 -.04em，两者都小于字体自身行盒。
      // 这里不走列表条目：itemExtent 会把子项压成确定高度，量到的就是自己下发的值，
      // 等于用结论验结论；直接用最外层无约束的条目高度跟测量对拍才有信号。
      const cases = [
        '<h1>第一回 灵根育源 心性圆明</h1>',
        '<h1>很长的标题用来验证折行后的块高与渲染一致：第一回 灵根育源 心性圆明 参合万象 造化会元</h1>',
      ];
      for (final html in cases) {
        for (final textScale in <double>[1.0, 1.5]) {
          final rendered = await naturalHeadingHeight(
            tester,
            html,
            viewWidth: 600,
            textScale: textScale,
          );
          final measured = ReaderPaginationEngine.measureBlockHeight(
            parseBlocks(html).first,
            600,
            settings,
            textScale: textScale,
          );
          expect(
            measured,
            closeTo(rendered, ReaderViewContent.headingSlotSlack),
            reason:
                'h1（字号缩放 $textScale）测量 $measured / 渲染 $rendered：'
                '测量偏矮会在确定高度下裁字，偏高则白丢一页的行',
          );
        }
      }
    });
  });
}
