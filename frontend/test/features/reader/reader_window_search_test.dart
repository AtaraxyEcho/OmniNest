import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_window_search.dart';

void main() {
  group('ReaderWindowSearchIndex', () {
    test('resolves hits across chapter boundaries', () {
      final index = ReaderWindowSearchIndex([
        WindowSearchChapter(
          chapterId: 'c0',
          title: '第一章',
          plainText: '开头寻找目标甲。',
        ),
        WindowSearchChapter(
          chapterId: 'c1',
          title: '第二章',
          plainText: '这里也有目标乙。',
        ),
      ]);

      final combined = index.combinedText;
      expect(combined, contains('目标甲'));
      expect(combined, contains('目标乙'));

      final hitA = index.resolve(combined.indexOf('目标甲'));
      expect(hitA!.chapterId, 'c0');
      expect(hitA.localOffset, '开头寻找目标甲。'.indexOf('目标甲'));
      expect(hitA.chapterTitle, '第一章');

      final hitB = index.resolve(combined.indexOf('目标乙'));
      expect(hitB!.chapterId, 'c1');
      expect(hitB.localOffset, '这里也有目标乙。'.indexOf('目标乙'));
      expect(index.titleOf(combined.indexOf('目标乙')), '第二章');
    });

    test('fromBlocks builds searchable text', () {
      final chapter = WindowSearchChapter.fromBlocks(
        chapterId: 'c0',
        title: 'T',
        blocks: [
          ParagraphBlock(
            lines: [
              LineData(spans: [ReaderInlineSpan(text: '关键内容')]),
            ],
          ),
        ],
      );
      expect(chapter.plainText, '关键内容');
      final index = ReaderWindowSearchIndex([chapter]);
      expect(index.resolve(0)!.chapterId, 'c0');
    });
  });
}
