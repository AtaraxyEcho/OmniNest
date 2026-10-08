import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_content.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：块测量高度必须等于该块在真实渲染里占据的高度。
///
/// 高度表决定滚动位置↔字符偏移的映射，也决定退出时记录的 charOffset。
/// 表与渲染不符，落位与记录就按差值系统性偏移；英文源文本的硬换行会让
/// "逐逻辑行测量"与"合并渲染"的行数不同，偏差随换行数累积。
void main() {
  final settings = ReaderViewSettings(
    fontFamily: 'sans',
    fontSize: 18,
    lineHeight: 1.6,
  );

  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: OmniNestTheme.from(AppThemePalette.dark),
    home: Scaffold(body: child),
  );

  /// 渲染正文块，返回第一个块的盒高与其折行宽度。
  Future<({double height, double width})> renderedFirstBlock(
    WidgetTester tester,
    String html,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        ReaderViewContent(
          htmlContent: html,
          settings: settings,
          scrollController: controller,
        ),
      ),
    );
    // compute() 在 isolate 中解析，fake async 下不会自行完成。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();
    final items = find.byType(ReaderContentBlockItem, skipOffstage: false);
    expect(items, findsWidgets, reason: '正文块未渲染，测试自身失真');
    final size = tester.getSize(items.first);
    return (height: size.height, width: size.width);
  }

  double measuredHeight(String html, double width) {
    final blocks = parseBlocks(html);
    return ReaderPaginationEngine.measureBlockHeight(
      blocks.first,
      width,
      settings,
      textScale: 1,
    );
  }

  final hardWrapped =
      '<p>${List<String>.filled(40, 'alpha beta gamma delta epsilon zeta eta').join('\n    ')}</p>';
  final singleLongLine = '<p>${List<String>.filled(400, 'word').join(' ')}</p>';

  group('块测量与渲染等高', () {
    testWidgets('硬换行英文段落：测量高度等于渲染高度', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final rendered = await renderedFirstBlock(tester, hardWrapped);
      final measured = measuredHeight(hardWrapped, rendered.width);

      expect(
        measured,
        closeTo(rendered.height, 2.0),
        reason:
            '测量 ${measured.toStringAsFixed(1)} 对渲染 ${rendered.height.toStringAsFixed(1)}，'
            '差值即落位与退出记录的系统性偏移',
      );
    });

    testWidgets('单行长段落：测量高度等于渲染高度', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final rendered = await renderedFirstBlock(tester, singleLongLine);
      final measured = measuredHeight(singleLongLine, rendered.width);

      expect(measured, closeTo(rendered.height, 2.0));
    });

    test('夹具前提：连续段落被合并为一块且字符计数可用', () {
      final blocks = parseBlocks('<p>one two three</p><p>four five</p>');
      // 解析器按中文排版合并连续段落（_mergeConsecutiveParagraphs）。
      expect(blocks, hasLength(1));
      final paragraph = blocks.single as ParagraphBlock;
      expect(paragraph.lines.length, greaterThanOrEqualTo(2));
      expect(BlockClipper.blockCharCount(paragraph), greaterThan(0));
    });
  });
}
