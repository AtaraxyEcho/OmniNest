import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_content.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：滚动范围必须与"当前构建了哪些项"无关。
///
/// 未提供确定高度时，SliverList 用已构建项的均值外推未构建项，同一章节在
/// 顶部与尾部量到的 maxScrollExtent 不同（实测量得 3877 对 1071）。深位置
/// 恢复按虚高范围 jumpTo 后，范围随构建收缩会把落点钳到目标之前。
void main() {
  final settings = ReaderViewSettings(
    fontFamily: 'sans',
    fontSize: 18,
    lineHeight: 1.6,
  );

  group('ChapterData.blockExtents', () {
    ChapterData chapterWith(List<double> heights, String html) {
      final data = ChapterData(
        chapterId: 'chapter_1',
        content: ReaderChapterContent(title: '第一章', content: html),
        blocks: parseBlocks(html),
      );
      data.updateCumulativeHeights(heights);
      return data;
    }

    test('整章测得时逐项反推确定高度', () {
      final data = chapterWith([100, 250], '<h2>t</h2><p>x</p>');
      expect(data.blocks.length, 2);
      expect(data.blockExtents, [100, 150]);
    });

    test('未覆盖整章时不给确定高度（列表继续估算）', () {
      final data = chapterWith([100], '<h2>t</h2><p>x</p>');
      expect(data.blocks.length, 2);
      expect(data.blockExtents, isNull);
    });
  });

  group('滚动范围稳定性', () {
    Widget host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: OmniNestTheme.from(AppThemePalette.dark),
      home: Scaffold(body: child),
    );

    Future<ScrollController> mount(
      WidgetTester tester,
      String html, {
      List<double>? blockExtents,
    }) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          ReaderViewContent(
            htmlContent: html,
            settings: settings,
            scrollController: controller,
            blockExtents: blockExtents,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump();
      return controller;
    }

    /// 标题块不与相邻段落合并，夹具才产生多个块（连续段落会被解析器合并）。
    const html = '<h2>Alpha</h2><p>gamma delta</p>';
    const blockExtent = 300.0;

    testWidgets('提供确定高度后，范围在顶部与尾部一致', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = await mount(
        tester,
        html,
        blockExtents: List.filled(parseBlocks(html).length, blockExtent),
      );
      final expected =
          blockExtent * parseBlocks(html).length +
          ReaderViewContent.trailingSpacerHeight +
          40 -
          600;

      final atTop = controller.position.maxScrollExtent;
      controller.jumpTo(atTop);
      await tester.pump();
      final atBottom = controller.position.maxScrollExtent;
      controller.jumpTo(0);
      await tester.pump();
      final backToTop = controller.position.maxScrollExtent;

      expect(parseBlocks(html).length, greaterThan(1), reason: '夹具应产生多个块');
      expect(atTop, greaterThan(0), reason: '夹具必须溢出视口');
      expect(atBottom, atTop, reason: '滚动推进后范围变化，说明仍有项在被估算');
      expect(backToTop, atTop);
      expect(atTop, closeTo(expected, 1.0), reason: '范围应等于确定高度之和加留白，减视口高');
    });

    testWidgets('未提供确定高度时范围会漂移（回归哨兵）', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = await mount(
        tester,
        '<p>${List<String>.filled(400, 'word').join(' ')}</p><h2>Tail</h2>',
      );
      final atTop = controller.position.maxScrollExtent;
      for (var step = 0; step < 8; step++) {
        controller.jumpTo(
          (controller.position.maxScrollExtent - 200).clamp(
            0.0,
            controller.position.maxScrollExtent,
          ),
        );
        await tester.pump();
      }
      final atBottom = controller.position.maxScrollExtent;

      expect(atBottom, lessThan(atTop), reason: '外推行为若已消失，应删除本哨兵并改为全覆盖断言');
    });
  });
}
