import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_annotation.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_stylesheet.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_annotations.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';

void main() {
  test('批注投影按边界切分文本并保留行内样式', () {
    final blocks = [
      ParagraphBlock(
        lines: const [
          LineData(
            spans: [ReaderInlineSpan(text: 'Hello world', isBold: true)],
          ),
        ],
      ),
    ];
    final annotations = [
      const ReaderAnnotation(
        id: 'annotation-1',
        readerItemId: 'item-1',
        startOffset: 0,
        endOffset: 5,
        color: '#FFEB3B',
        createdAt: null,
      ),
    ];

    final result = ReaderContentAnnotationProjector.apply(blocks, annotations);
    final paragraph = result.single as ParagraphBlock;
    final spans = paragraph.lines.single.spans;

    expect(spans.map((span) => span.text), ['Hello', ' world']);
    expect(spans.first.backgroundColor, isNotNull);
    expect(spans.first.isBold, isTrue);
    expect(spans.last.backgroundColor, isNull);
  });

  test('投影重建行必须带全书样式与行尾折叠记账', () {
    // apply() 只要章节存在任一注解就重建每个块（注解甚至可以落在别的块上）。
    // 重建时丢 style 会让绘制侧 firstLineIndentChars(line.style) 退回默认缩进，
    // 而测量侧仍用带样式的原块 ⇒ 固定 itemExtent 下裁行、页预算偏一行；
    // 丢 trailingCollapsedChars 会改 sourceChars，批注偏移与页裁剪落到不同字符位置。
    const style = ParagraphStyleSpec(firstLineIndentChars: 0);
    final blocks = [
      ParagraphBlock(
        style: style,
        lines: const [
          LineData(
            spans: [ReaderInlineSpan(text: '第一段正文', startOffset: 2)],
            isNewParagraph: true,
            collapsedChars: 2,
            trailingCollapsedChars: 3,
            style: style,
          ),
        ],
      ),
    ];
    final annotations = [
      const ReaderAnnotation(
        id: 'annotation-far',
        readerItemId: 'item-1',
        startOffset: 900,
        endOffset: 990,
        color: '#FFEB3B',
        createdAt: null,
      ),
    ];

    final projected = ReaderContentAnnotationProjector.apply(
      blocks,
      annotations,
    );
    final line = (projected.single as ParagraphBlock).lines.single;

    expect(identical(line.style, style), isTrue, reason: '书给的缩进档位不得在投影中被抹平');
    expect(line.trailingCollapsedChars, 3);
    expect(line.sourceChars, '第一段正文'.length + 2 + 3);
    expect(line.collapsedChars, 2);
    expect(line.isNewParagraph, isTrue);
    expect(line.spans.single.startOffset, 2);
  });

  test('硬换行段落里的批注落在选中的那几个字上', () {
    // 折叠会把一个源文本节点切成多行。切片若照抄原 span 的 startOffset，第二行以后
    // 的偏移全指回段首：按源位置存的批注会涂到别的行为，重新选中也删不干净。
    final source = '<p>alpha beta\n    gamma delta</p>';
    final blocks = parseBlocks(source);
    final paragraph = blocks.single as ParagraphBlock;
    expect(paragraph.lines, hasLength(2));

    // `alpha beta` 占 0..10，换行与缩进占 10..15，`gamma` 从 15 开始。
    final projected = ReaderContentAnnotationProjector.apply(blocks, [
      const ReaderAnnotation(
        id: 'a-1',
        readerItemId: 'i-1',
        startOffset: 15,
        endOffset: 20,
        color: '#FFEB3B',
        createdAt: null,
      ),
    ]);
    final marked =
        (projected.single as ParagraphBlock).lines
            .expand((line) => line.spans)
            .where((span) => span.backgroundColor != null)
            .toList();
    expect(marked.map((span) => span.text), ['gamma']);
    expect(marked.single.startOffset, 15);
  });

  test('没有批注时复用原内容块列表', () {
    final blocks = <ContentBlock>[
      ParagraphBlock(
        lines: const [
          LineData(spans: [ReaderInlineSpan(text: 'Text')]),
        ],
      ),
    ];

    final result = ReaderContentAnnotationProjector.apply(blocks, const []);

    expect(identical(result, blocks), isTrue);
  });
}
