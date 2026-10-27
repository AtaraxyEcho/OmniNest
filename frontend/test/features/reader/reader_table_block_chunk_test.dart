import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_table_block_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：超大表格分帧建行，首帧只承担预算内的行，整表占据的高度全程不变。
///
/// 审查 PERF-05 记的是"整表一次构建"的首帧风险：500 行表在 DEBUG 下一次构建实测
/// 772ms。分帧之后首帧只建 32 行，未构建的行按测量侧行高预留空位，因此滚动高度表
/// 与字符偏移↔像素映射都不受影响——这两条是这里断言的重点，耗时只做量级对照。
/// 首帧行预算钉成字面量：改组件常量必须同步改这里，改动才会被用例看见。
const int _firstFrameRows = 32;

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
    home: Scaffold(body: SizedBox(width: 800, height: 1200, child: child)),
  );

  TableBlock table(int rows) => TableBlock(
    rows: List.generate(
      rows,
      (index) => TableRowData(
        cells: [
          [ReaderInlineSpan(text: 'row-$index-a')],
          [ReaderInlineSpan(text: 'row-$index-b')],
        ],
        isHeader: index == 0,
      ),
    ),
  );

  Widget blockItem(TableBlock block) => ReaderContentBlockItem(
    block: block,
    settings: settings,
    itemId: 'item',
    chapterId: 'chapter',
  );

  /// 已建行数：一行两个单元格，按单元格文本数比首帧预算更稳。
  int builtRows(WidgetTester tester) =>
      find.textContaining('-a', skipOffstage: false).evaluate().length;

  group('表格分帧建行', () {
    testWidgets('无高度表（松约束）：首帧只建预算行，预留位保住整表高度', (tester) async {
      final block = table(500);
      final measured = ReaderPaginationEngine.measureBlockHeight(
        block,
        800,
        settings,
      );
      final firstFrame = Stopwatch()..start();
      await tester.pumpWidget(
        host(SingleChildScrollView(child: blockItem(block))),
      );
      firstFrame.stop();

      expect(builtRows(tester), _firstFrameRows, reason: '首帧只应构建预算内的行');
      expect(
        tester.getSize(find.byType(ReaderContentBlockItem)).height,
        closeTo(measured, 0.01),
        reason: '预留空位后整表占据的高度必须与测量一致，否则字符偏移映射会漂',
      );

      final fill = Stopwatch()..start();
      await tester.pumpAndSettle();
      fill.stop();

      expect(builtRows(tester), 500, reason: '补齐后每一行都要在树里');
      expect(
        tester.getSize(find.byType(ReaderContentBlockItem)).height,
        closeTo(measured, 0.01),
        reason: '补行不得改变块高',
      );
      // 首帧承担的工作量必须显著小于一遍建完整表；DEBUG 实测约 211ms 对 1893ms。
      expect(
        firstFrame.elapsedMilliseconds * 2,
        lessThan(fill.elapsedMilliseconds),
        reason: '首帧耗时应是整表建行的一小部分，否则分帧没有生效',
      );
    });

    testWidgets('定高槽位（滚动高度表）：槽位已留空位，不再测行高也不溢出', (tester) async {
      final block = table(500);
      final measured = ReaderPaginationEngine.measureBlockHeight(
        block,
        800,
        settings,
      );
      await tester.pumpWidget(
        host(
          ListView.builder(
            itemCount: 1,
            itemExtentBuilder: (index, creator) => measured,
            itemBuilder: (context, index) => blockItem(block),
          ),
        ),
      );

      expect(builtRows(tester), _firstFrameRows);
      expect(
        tester.getSize(find.byType(ReaderContentBlockItem)).height,
        closeTo(measured, 0.01),
        reason: '条目高度由高度表定死，与整表测量同值',
      );
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(builtRows(tester), 500);
      expect(tester.takeException(), isNull);
    });

    testWidgets('预算内的表一次建完，且不插布局节点', (tester) async {
      final block = table(_firstFrameRows);
      await tester.pumpWidget(
        host(SingleChildScrollView(child: blockItem(block))),
      );

      expect(builtRows(tester), _firstFrameRows);
      expect(
        find.byType(LayoutBuilder),
        findsNothing,
        reason: '不需要预留时控件树应与改动前逐层一致',
      );
      await tester.pumpAndSettle();
      expect(builtRows(tester), _firstFrameRows);
    });

    testWidgets('空表不占位', (tester) async {
      await tester.pumpWidget(
        host(SingleChildScrollView(child: blockItem(table(0)))),
      );

      expect(find.byType(ReaderTableBlockView), findsOneWidget);
      expect(
        tester.getSize(find.byType(ReaderContentBlockItem)).height,
        isZero,
        reason: '空表不能占行位，块宽仍由宿主给',
      );
    });

    testWidgets('行表长度变了才重来，补帧途中批注更新不回收首帧预算', (tester) async {
      final block = table(120);
      await tester.pumpWidget(
        host(SingleChildScrollView(child: blockItem(block))),
      );
      await tester.pump();
      expect(builtRows(tester), greaterThan(_firstFrameRows));

      // 同长度但换了行对象（批注投影的重建）：进度保留，不回到首帧预算。
      await tester.pumpWidget(
        host(SingleChildScrollView(child: blockItem(table(120)))),
      );
      expect(builtRows(tester), greaterThan(_firstFrameRows));
      await tester.pumpAndSettle();
      expect(builtRows(tester), 120);
    });
  });
}
