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
}
