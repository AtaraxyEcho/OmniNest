import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';

/// 段落合并分块上限回归测试（N-01/D-08）。
///
/// 修复前 `_mergeConsecutiveParagraphs` 无上限，整章连续段落会合并成单个块：
/// 测高分批（40 块/批）、逐页懒分页与远跳分批全部退化为单批，
/// 数 MB 文本进入一次 TextPainter 全量 layout。
void main() {
  String paragraphText(ParagraphBlock block) =>
      block.lines
          .map((line) => line.spans.map((span) => span.text).join())
          .join();

  List<ParagraphBlock> paragraphsOf(List<ContentBlock> blocks) =>
      blocks.whereType<ParagraphBlock>().toList();

  group('合并块行数上限', () {
    test('200 个短段落不再合并为单块', () {
      final html = List.generate(200, (index) => '<p>段落内容</p>').join();

      final blocks = parseBlocks(html);
      final paragraphs = paragraphsOf(blocks);

      expect(paragraphs, isNotEmpty);
      expect(paragraphs.length, lessThan(200), reason: '仍应合并以降低 Column 行数');
      expect(paragraphs.length, greaterThan(1), reason: '必须有上限，否则整章退化为单块');
      for (final block in paragraphs) {
        expect(block.lines.length, lessThanOrEqualTo(48));
      }
    });

    test('分块后字符总量守恒，块边界不改变累积偏移', () {
      final html = List.generate(137, (index) => '<p>第$index段正文内容。</p>').join();

      final blocks = parseBlocks(html);
      final renderedChars = blocks.whereType<ParagraphBlock>().fold(
        0,
        (total, block) => total + BlockClipper.blockCharCount(block),
      );

      final sourceChars = RegExp(r'<p>(.*?)</p>')
          .allMatches(html)
          .fold(0, (total, match) => total + match.group(1)!.length);

      expect(renderedChars, sourceChars);
    });

    test('按字符数上限切块，单块不超过 4000 字符', () {
      final longLine = List.generate(150, (_) => '长').join();
      final html = List.generate(60, (_) => '<p>$longLine</p>').join();

      final paragraphs = paragraphsOf(parseBlocks(html));

      expect(paragraphs.length, greaterThan(1));
      for (final block in paragraphs) {
        expect(BlockClipper.blockCharCount(block), lessThanOrEqualTo(4000));
      }
    });
  });

  group('切块语义保真', () {
    test('每块首行不标记新段落，续行为新段落', () {
      final html = List.generate(60, (index) => '<p>段落$index</p>').join();

      final paragraphs = paragraphsOf(parseBlocks(html));

      for (final block in paragraphs) {
        expect(block.lines.first.isNewParagraph, isFalse);
        for (final line in block.lines.skip(1)) {
          expect(line.isNewParagraph, isTrue);
        }
      }
    });

    test('段距标记保留在携带它的那个块上', () {
      final spaced = <String>[];
      for (var index = 0; index < 60; index++) {
        spaced.add(
          index == 30
              // 相邻两个 <br> 才是作者留出的空行（语义细节见下一组的专项用例）。
              ? '<p>甲<br><br>乙</p>'
              : '<p>段落$index</p>',
        );
      }

      final paragraphs = paragraphsOf(parseBlocks(spaced.join()));

      expect(
        paragraphs.where((block) => block.hasTrailingSpacing),
        hasLength(1),
        reason: '段距标记必须落在承载该段的那个块上，不得因切块丢失或扩散',
      );
    });

    test('非段落块打断合并并保持顺序', () {
      const html = '<p>甲</p><h2>标题</h2><p>乙</p>';

      final blocks = parseBlocks(html);

      expect(blocks.whereType<HeadingBlock>().toList(), hasLength(1));
      expect(paragraphsOf(blocks), hasLength(2));
      expect(paragraphText(blocks[0] as ParagraphBlock), '甲');
      expect(paragraphText(blocks[2] as ParagraphBlock), '乙');
    });
  });

  group('换行与缩进分隔规则', () {
    String separator({
      bool isFirstLine = false,
      bool isNewParagraph = false,
      bool previousLineIsEmpty = false,
      bool isBlockContinuation = false,
      bool startsWithFullWidthIndent = false,
    }) => paragraphLineSeparator(
      isFirstLine: isFirstLine,
      isNewParagraph: isNewParagraph,
      previousLineIsEmpty: previousLineIsEmpty,
      isBlockContinuation: isBlockContinuation,
      startsWithFullWidthIndent: startsWithFullWidthIndent,
    );

    test('首行注入缩进，跨章续接的块首行不注入', () {
      expect(separator(isFirstLine: true), '　　');
      expect(separator(isFirstLine: true, isBlockContinuation: true), '');
      expect(separator(isFirstLine: true, startsWithFullWidthIndent: true), '');
    });

    test('仅段首行注入缩进，已带缩进或空行之后的行不重复注入', () {
      expect(separator(isNewParagraph: true), '\n　　');
      expect(
        separator(isNewParagraph: true, startsWithFullWidthIndent: true),
        '\n',
      );
      expect(separator(isNewParagraph: true, previousLineIsEmpty: true), '\n');
      expect(separator(), '\n');
    });

    test('行首缩进判定只看首个非空 span', () {
      expect(
        lineStartsWithFullWidthIndent([
          ReaderInlineSpan(text: ''),
          ReaderInlineSpan(text: '　　正文'),
        ]),
        isTrue,
      );
      expect(
        lineStartsWithFullWidthIndent([ReaderInlineSpan(text: '　 正文')]),
        isFalse,
      );
    });
  });

  group('相邻 br 才是空行', () {
    test('被文本隔开的两个 br 不产生段距', () {
      final paragraphs = paragraphsOf(parseBlocks('<p>甲<br>乙<br>丙</p>'));

      expect(paragraphs, hasLength(1));
      expect(paragraphs.single.hasTrailingSpacing, isFalse);
      expect(paragraphText(paragraphs.single), '甲乙丙');
    });

    test('相邻的两个 br 产生段距', () {
      final paragraphs = paragraphsOf(parseBlocks('<p>甲<br><br>乙</p>'));

      expect(paragraphs, hasLength(1));
      expect(paragraphs.single.hasTrailingSpacing, isTrue);
    });

    test('段距标记不跨段残留', () {
      final paragraphs = paragraphsOf(parseBlocks('<p>甲<br><br>乙</p><p>丙</p>'));

      expect(paragraphs, hasLength(1), reason: '连续段落仍合并为一块');
      expect(paragraphs.single.hasTrailingSpacing, isTrue);

      final secondRun = paragraphsOf(
        parseBlocks('<p>甲<br><br>乙</p><h2>标题</h2><p>丙</p>'),
      );

      expect(secondRun, hasLength(2));
      expect(secondRun.last.hasTrailingSpacing, isFalse);
    });
  });
}
