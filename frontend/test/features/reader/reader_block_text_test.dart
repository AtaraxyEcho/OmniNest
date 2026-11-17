import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_block_text.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';

void main() {
  group('plainTextFromBlocks', () {
    test('extracts paragraph and heading text', () {
      final blocks = [
        HeadingBlock(text: '标题', level: 1),
        ParagraphBlock(
          lines: [
            LineData(
              spans: [
                ReaderInlineSpan(text: '第一段'),
                ReaderInlineSpan(text: '续'),
              ],
            ),
          ],
        ),
      ];
      expect(plainTextFromBlocks(blocks), '标题\n第一段续');
    });

    test('extracts list and ignores image blocks', () {
      final blocks = [
        ImageBlock(src: 'a.png'),
        ListBlock(
          items: [
            ListItemData(spans: [ReaderInlineSpan(text: '条目一')]),
            ListItemData(spans: [ReaderInlineSpan(text: '条目二')]),
          ],
          isOrdered: false,
        ),
        DividerBlock(),
      ];
      final text = plainTextFromBlocks(blocks);
      expect(text, contains('条目一'));
      expect(text, contains('条目二'));
      expect(text, isNot(contains('a.png')));
    });
  });

  group('ChapterSearchCorpus', () {
    // 夹具与解析器口径保持一致：span.startOffset 是块源字符域里的绝对位置，
    // 行的 sourceChars = 可绘制 + 行首折叠 + 行尾折叠。
    List<ContentBlock> indentedChapter() => [
      ParagraphBlock(
        lines: [
          LineData(
            spans: [ReaderInlineSpan(text: '第一段正文', startOffset: 2)],
            collapsedChars: 2,
            trailingCollapsedChars: 4,
          ),
          LineData(
            spans: [
              ReaderInlineSpan(text: '第二段', startOffset: 13),
              ReaderInlineSpan(text: '目标词', startOffset: 16, isBold: true),
            ],
            isNewParagraph: true,
            collapsedChars: 2,
          ),
        ],
      ),
    ];

    test('maps a hit back to the span source offset', () {
      final corpus = ChapterSearchCorpus.fromBlocks(indentedChapter());

      expect(corpus.plainText, '第一段正文\n第二段目标词');
      final hit = corpus.plainText.indexOf('目标词');
      expect(hit, 9);
      // 检索串里"目标词"紧跟在"第二段"后面；源域里它的起点是 16。
      expect(corpus.toCharOffset(hit), 16);
      expect(corpus.toCharOffsetEnd(hit + '目标词'.length - 1), 19);
    });

    test('maps separators onto the following text position', () {
      final corpus = ChapterSearchCorpus.fromBlocks(indentedChapter());

      // 行分隔符在源文本里不存在，落到下一行可绘制文本之前的位置（含该行行首缩进）。
      expect(corpus.toCharOffset('第一段正文'.length), 11);
      expect(corpus.toCharOffset(0), 2);
    });

    test(
      'maps heading and paragraph boundaries into the block prefix domain',
      () {
        final blocks = [
          ParagraphBlock(
            lines: [
              LineData(spans: [ReaderInlineSpan(text: '正文', startOffset: 0)]),
            ],
          ),
          HeadingBlock(text: '标题', level: 2, startOffset: 2),
        ];
        final corpus = ChapterSearchCorpus.fromBlocks(blocks);

        expect(corpus.plainText, '正文\n标题');
        expect(corpus.toCharOffset(2), 2);
        expect(corpus.toCharOffset(3), 2);
        expect(corpus.toCharOffset(4), 3);
      },
    );

    test('stays inside the chapter for out-of-range indices', () {
      final corpus = ChapterSearchCorpus.fromBlocks(indentedChapter());

      expect(corpus.toCharOffset(-5), 2);
      expect(corpus.toCharOffset(corpus.plainText.length + 10), 18);
      expect(ChapterSearchCorpus.fromBlocks(const []).plainText, isEmpty);
      expect(ChapterSearchCorpus.fromBlocks(const []).toCharOffset(3), 0);
    });
  });

  group('matchCorpusRange', () {
    // 两个自然段里各有一个"然而"，第二个段还带行首缩进：选区必须按源域算，
    // 并且重复词要能落在用户真正选中的那一处。
    List<ContentBlock> twoParagraphs() => [
      ParagraphBlock(
        lines: [
          LineData(
            spans: [
              ReaderInlineSpan(text: '甲段', startOffset: 0),
              ReaderInlineSpan(text: '然而', startOffset: 2),
              ReaderInlineSpan(text: '乙', startOffset: 4),
            ],
          ),
        ],
      ),
      ParagraphBlock(
        lines: [
          LineData(
            spans: [
              ReaderInlineSpan(text: '丙段', startOffset: 6),
              ReaderInlineSpan(text: '然而', startOffset: 8),
              ReaderInlineSpan(text: '丁', startOffset: 10),
            ],
            collapsedChars: 1,
          ),
        ],
      ),
    ];

    test('matches a word that lives inside a single span', () {
      final corpus = ChapterSearchCorpus.fromBlocks(twoParagraphs());

      // 第一处"然而"：源域 [2,4)
      expect(matchCorpusRange(corpus, '然而'), (2, 4));
    });

    test('prefers the occurrence nearest the viewport anchor', () {
      final corpus = ChapterSearchCorpus.fromBlocks(twoParagraphs());

      // 旧实现逐 span indexOf，永远命中章内第一次出现，用户在第二段点高亮却涂到第一段。
      expect(matchCorpusRange(corpus, '然而', anchorCharOffset: 9), (8, 10));
      expect(matchCorpusRange(corpus, '然而', anchorCharOffset: 0), (2, 4));
    });

    test('matches across block boundaries and folded whitespace', () {
      final corpus = ChapterSearchCorpus.fromBlocks(twoParagraphs());

      // 选区跨了两个自然段：中间那个换行是合成的分隔符，源域里"乙"与"丙"之间
      // 还夹着第二段的行首缩进，起止必须落在真实字符上。
      // 选区里多出来的空白要容错；没有空白的写法跨不过块之间的分隔符，仍按未命中处理。
      expect(matchCorpusRange(corpus, '乙 丙段 然而'), (4, 10));
      expect(matchCorpusRange(corpus, '乙丙段然而'), isNull);
    });

    test('returns null when the selection is not in this chapter', () {
      final corpus = ChapterSearchCorpus.fromBlocks(twoParagraphs());

      expect(matchCorpusRange(corpus, '查无此词'), isNull);
      expect(
        matchCorpusRange(ChapterSearchCorpus.fromBlocks(const []), '然而'),
        isNull,
      );
    });
  });
}
