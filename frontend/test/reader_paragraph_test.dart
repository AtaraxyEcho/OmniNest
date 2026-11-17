import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';

void main() {
  group('Paragraph merging and line breaks', () {
    test(
      'A<br><br>B within single <p> produces single paragraph with indent',
      () {
        const html = '<p>A<br/><br/>B</p>';
        final blocks = parseBlocks(html);
        expect(blocks.length, 1);
        final block = blocks.first as ParagraphBlock;
        // Should have 2 lines: "A" and "B"
        expect(block.lines.length, 2);
        expect(block.lines[0].spans.map((s) => s.text).join(), 'A');
        expect(block.lines[1].spans.map((s) => s.text).join(), 'B');
        expect(block.lines[1].isNewParagraph, true);
      },
    );

    test('<p>A</p><br><br><p>B</p> merges into single paragraph', () {
      const html = '<p>A</p><br/><br/><p>B</p>';
      final blocks = parseBlocks(html);
      expect(blocks.length, 1);
      final block = blocks.first as ParagraphBlock;
      expect(block.lines.length, 2);
      expect(block.lines[0].spans.map((s) => s.text).join(), 'A');
      expect(block.lines[1].spans.map((s) => s.text).join(), 'B');
      expect(block.lines[1].isNewParagraph, true);
    });

    test('<p>A</p><br><p>B</p> merges into single paragraph', () {
      const html = '<p>A</p><br/><p>B</p>';
      final blocks = parseBlocks(html);
      expect(blocks.length, 1);
      final block = blocks.first as ParagraphBlock;
      expect(block.lines.length, 2);
      expect(block.lines[0].spans.map((s) => s.text).join(), 'A');
      expect(block.lines[1].spans.map((s) => s.text).join(), 'B');
      expect(block.lines[1].isNewParagraph, true);
    });

    test('consecutive <p> tags merge into single paragraph', () {
      const html = '<p>First paragraph.</p><p>Second paragraph.</p>';
      final blocks = parseBlocks(html);
      expect(blocks.length, 1);
      final block = blocks.first as ParagraphBlock;
      expect(block.lines.length, 2);
      expect(
        block.lines[0].spans.map((s) => s.text).join(),
        'First paragraph.',
      );
      expect(
        block.lines[1].spans.map((s) => s.text).join(),
        'Second paragraph.',
      );
      expect(block.lines[1].isNewParagraph, true);
    });

    test('A<br><br><br>B produces single paragraph break (not double)', () {
      const html = '<p>A<br/><br/><br/>B</p>';
      final blocks = parseBlocks(html);
      expect(blocks.length, 1);
      final block = blocks.first as ParagraphBlock;
      // Should have exactly 2 lines, not 3
      expect(block.lines.length, 2);
      expect(block.lines[0].spans.map((s) => s.text).join(), 'A');
      expect(block.lines[1].spans.map((s) => s.text).join(), 'B');
    });

    test('three consecutive paragraphs merge correctly', () {
      const html = '<p>One.</p><p>Two.</p><p>Three.</p>';
      final blocks = parseBlocks(html);
      expect(blocks.length, 1);
      final block = blocks.first as ParagraphBlock;
      expect(block.lines.length, 3);
      expect(block.lines[0].isNewParagraph, false);
      expect(block.lines[1].isNewParagraph, true);
      expect(block.lines[2].isNewParagraph, true);
    });

    test('heading followed by paragraphs does not merge', () {
      const html = '<h1>Title</h1><p>Para 1.</p><p>Para 2.</p>';
      final blocks = parseBlocks(html);
      expect(blocks.length, 2);
      expect(blocks[0], isA<HeadingBlock>());
      expect(blocks[1], isA<ParagraphBlock>());
      final para = blocks[1] as ParagraphBlock;
      expect(para.lines.length, 2);
    });

    test('real EPUB structure with br between p tags', () {
      // Simulate actual EPUB: <p>text</p><br><br><p>text</p>
      const html =
          '<div>'
          '<p>释，它体现的是批评家自身的睿智和素养。文学研究却比批评要稍稍显得客观。</p>'
          '<br/>'
          '<br/>'
          '<p>关于陀思妥耶夫斯基的批评和研究话题早已超越了陀氏本身。</p>'
          '</div>';
      final blocks = parseBlocks(html);
      // Should produce 1 merged paragraph block
      expect(blocks.length, 1);
      final block = blocks.first as ParagraphBlock;
      // Should have exactly 2 lines, no empty lines
      expect(block.lines.length, 2);
      expect(block.lines[0].spans.isEmpty, false);
      expect(block.lines[1].spans.isEmpty, false);
      expect(block.lines[1].isNewParagraph, true);
    });

    test('EPUB with single br between p tags', () {
      const html =
          '<div>'
          '<p>Paragraph one.</p>'
          '<br/>'
          '<p>Paragraph two.</p>'
          '</div>';
      final blocks = parseBlocks(html);
      expect(blocks.length, 1);
      final block = blocks.first as ParagraphBlock;
      expect(block.lines.length, 2);
      expect(block.lines[1].isNewParagraph, true);
    });

    test('no extra empty lines in output', () {
      const html = '<p>A</p><br/><br/><p>B</p><br/><br/><p>C</p>';
      final blocks = parseBlocks(html);
      expect(blocks.length, 1);
      final block = blocks.first as ParagraphBlock;
      // 3 paragraphs, no empty lines
      expect(block.lines.length, 3);
      for (final line in block.lines) {
        expect(line.spans.isEmpty, false, reason: 'No empty lines expected');
      }
    });

    test('whitespace-only lines between paragraphs are filtered', () {
      // EPUB often has whitespace text nodes between <p> tags
      const html =
          '<div><p>First paragraph.</p> \n <p>Second paragraph.</p></div>';
      final blocks = parseBlocks(html);
      expect(blocks.length, 1);
      final block = blocks.first as ParagraphBlock;
      expect(block.lines.length, 2);
      expect(block.lines[0].spans.isEmpty, false);
      expect(block.lines[1].spans.isEmpty, false);
      expect(block.lines[1].isNewParagraph, true);
    });

    test('real EPUB whitespace structure', () {
      // Simulate actual EPUB: whitespace between <p> tags
      const html =
          '<div>'
          '<p>Paragraph one content.</p>'
          ' \n '
          '<p>Paragraph two content.</p>'
          '</div>';
      final blocks = parseBlocks(html);
      expect(blocks.length, 1);
      final block = blocks.first as ParagraphBlock;
      // Should have 2 lines, whitespace line filtered out
      expect(block.lines.length, 2);
      expect(block.lines[1].isNewParagraph, true);
    });
  });
}
