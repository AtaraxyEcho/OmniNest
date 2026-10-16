import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  testWidgets('renders heading and paragraph with indent', (tester) async {
    final settings = ReaderViewSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ReaderContentBlockItem(
                block: HeadingBlock(text: '章标题', level: 1),
                settings: settings,
                itemId: 'b',
                chapterId: 'c0',
              ),
              ReaderContentBlockItem(
                block: ParagraphBlock(
                  lines: [
                    LineData(spans: [ReaderInlineSpan(text: '正文内容')]),
                  ],
                ),
                settings: settings,
                itemId: 'b',
                chapterId: 'c0',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('章标题'), findsOneWidget);
    expect(find.textContaining('正文内容'), findsOneWidget);
    // 首行缩进：两端对齐会把行首的全角空格折成零宽，缩进只有定宽盒子才站得住。
    final painted = paintedSpan(tester, '正文内容');
    expect(painted.toPlainText(), '\uFFFC正文内容');
    expect(indentBoxWidths(painted), [
      settings.fontSize * defaultFirstLineIndentChars,
    ]);
  });

  testWidgets('已带全角缩进的续行不再重复注入缩进', (tester) async {
    final settings = ReaderViewSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderContentBlockItem(
            block: ParagraphBlock(
              lines: [
                LineData(spans: [ReaderInlineSpan(text: '第一段')]),
                LineData(
                  spans: [ReaderInlineSpan(text: '　　已缩进段落')],
                  isNewParagraph: true,
                ),
              ],
            ),
            settings: settings,
            itemId: 'b',
            chapterId: 'c0',
          ),
        ),
      ),
    );

    // 源文本自带的字面缩进留在文本里，装配侧只给首行补一个盒子，不再叠第二个。
    final indented = paintedSpan(tester, '已缩进段落');
    expect(indented.toPlainText(), '\uFFFC第一段\n　　已缩进段落');
    expect(indentBoxWidths(indented), [settings.fontSize * 2]);
  });

  testWidgets('continuation paragraph skips indent', (tester) async {
    final settings = ReaderViewSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderContentBlockItem(
            block: ParagraphBlock(
              lines: [
                LineData(spans: [ReaderInlineSpan(text: '续接段落')]),
              ],
            ),
            settings: settings,
            itemId: 'b',
            chapterId: 'c0',
            isFirstBlockContinuation: true,
          ),
        ),
      ),
    );
    expect(find.textContaining('续接段落'), findsOneWidget);
    // 续接页的首行既不补换行也不补缩进盒子。
    expect(indentBoxWidths(paintedSpan(tester, '续接段落')), isEmpty);
  });

  testWidgets('一档标题按稿子的 h1 排，绘制与测量取同一份样式', (tester) async {
    // 稿子 `.article-column h1`：clamp(31px, 8vw, 43px) 在手机基线取下界 31px、
    // 正文默认 19px → 1.63 倍；line-height 1.25、font-weight 600、字距 -.04em、
    // margin 14/32。倍率进常量，改档位只能改这一处。
    final settings = ReaderViewSettings(fontSize: 19);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderContentBlockItem(
            block: HeadingBlock(text: '第一回', level: 1),
            settings: settings,
            itemId: 'b',
            chapterId: 'c0',
          ),
        ),
      ),
    );

    final expected = ReaderContentBlockItem.headingStyle(settings, 1);
    expect(
      tester.widget<Text>(find.text('第一回')).style,
      expected,
      reason: '渲染必须直接消费 headingStyle，另写一份就让测量侧静默失配',
    );
    expect(
      expected.fontSize,
      closeTo(19 * ReaderContentBlockItem.headingLevel1Scale, 0.001),
    );
    expect(
      ReaderContentBlockItem.headingLevel1Scale,
      closeTo(31 / 19, 0.01),
      reason: '倍率必须由稿子的 31px/19px 折算而来',
    );
    expect(expected.height, ReaderContentBlockItem.headingLevel1LineHeight);
    expect(expected.fontWeight, FontWeight.w600);
    expect(expected.letterSpacing, closeTo(expected.fontSize! * -0.04, 0.001));

    // 稿子只规定了 h1，更深的层级维持阅读器既有档位，不被这次对齐改动。
    final deeper = ReaderContentBlockItem.headingStyle(settings, 2);
    expect(deeper.fontSize, closeTo(19 * 1.25, 0.001));
    expect(deeper.height, ReaderContentBlockItem.headingLineHeight);
    expect(deeper.fontWeight, FontWeight.w700);
    expect(deeper.letterSpacing, 0.0);

    // margin: 14px 0 32px —— 下侧由 8 + 24 合成，两侧都只能经由常量表达。
    expect(ReaderContentBlockItem.headingTopPadding, 14.0);
    expect(
      ReaderContentBlockItem.headingBottomPadding +
          ReaderContentBlockItem.headingBottomSpacing,
      32.0,
    );
  });
}

/// 绘制侧装配出来的富文本根 span。
///
/// 缩进改成 WidgetSpan 之后不再出现在文本里，只能从 span 树上量。
TextSpan paintedSpan(WidgetTester tester, String fragment) {
  final matches =
      tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (text) => text.textSpan?.toPlainText().contains(fragment) ?? false,
          )
          .toList();
  expect(matches, hasLength(1));
  return matches.single.textSpan! as TextSpan;
}

/// span 树里所有缩进盒子的宽度，按出现顺序。
///
/// 断言宽度而不是个数：既盯住"该缩进的地方缩了"，也盯住"缩的是两个字宽"。
List<double> indentBoxWidths(InlineSpan span) {
  final widths = <double>[];
  span.visitChildren((node) {
    final child = node is WidgetSpan ? node.child : null;
    if (child is SizedBox) {
      widths.add(child.width ?? 0);
    }
    return true;
  });
  return widths;
}
