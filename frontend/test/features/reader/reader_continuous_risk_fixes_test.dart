import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_selection_range.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  group('P1 estimate height', () {
    test('uses estimateHeight for unready neighbor instead of 240', () {
      final controller = ReaderContinuousScrollController();
      controller.rebuild(
        anchorChapterId: 'c0',
        allChapterIds: const ['c0', 'c1'],
        resolve: (id) {
          if (id != 'c0') return null;
          return ContinuousChapterEntry(
            chapterId: 'c0',
            title: 'A',
            blockCount: 1,
            cumulativeHeights: const [100],
            totalHeight: 100,
            totalChars: 10,
            isReady: true,
            blocks: [
              ParagraphBlock(
                lines: [
                  LineData(spans: [ReaderInlineSpan(text: 'hello')]),
                ],
              ),
            ],
            blockCharPrefixes: const [0, 10],
          );
        },
        estimateHeight: (_) => 400,
      );
      expect(controller.entryFor('c1')!.totalHeight, 400);
      expect(controller.entryFor('c1')!.isReady, isFalse);
    });
  });

  group('P2 block-level char mapping', () {
    test('maps into text block by height ratio within block', () {
      final blocks = [
        ParagraphBlock(
          lines: [
            LineData(spans: [ReaderInlineSpan(text: 'A' * 50)]),
          ],
        ),
        ImageBlock(src: 'x.png'),
        ParagraphBlock(
          lines: [
            LineData(spans: [ReaderInlineSpan(text: 'B' * 50)]),
          ],
        ),
      ];
      final controller = ReaderContinuousScrollController();
      // 三块高度 100/80/100；chars 50/0/50；prefix 0,50,50,100
      controller.rebuild(
        anchorChapterId: 'c0',
        allChapterIds: const ['c0'],
        resolve:
            (_) => ContinuousChapterEntry(
              chapterId: 'c0',
              title: 'A',
              blockCount: 3,
              cumulativeHeights: const [100, 180, 280],
              totalHeight: 280,
              totalChars: 100,
              isReady: true,
              blocks: blocks,
              blockCharPrefixes: const [0, 50, 50, 100],
            ),
      );
      // 章体起点 = 章头 36；块内 Y 需加 chrome 偏移。
      // 落在第一块中点：char ≈ 25
      final midFirst = controller.resolver.resolveContentY(36 + 50)!;
      expect(midFirst.chapterId, 'c0');
      expect(midFirst.logical.charOffset, 25);
      // 落在图片块：char 固定在块起点 50
      final onImage = controller.resolver.resolveContentY(36 + 140)!;
      expect(onImage.logical.charOffset, 50);
      // 落在第三块中点：50 + 25
      final midThird = controller.resolver.resolveContentY(36 + 230)!;
      expect(midThird.logical.charOffset, 75);
    });
  });

  group('P3 selection range', () {
    test('resolves selection in paragraph blocks', () {
      final blocks = [
        ParagraphBlock(
          lines: [
            LineData(
              spans: [
                ReaderInlineSpan(text: 'hello ', startOffset: 0),
                ReaderInlineSpan(text: 'world', startOffset: 6),
              ],
            ),
          ],
        ),
      ];
      final range = resolveSelectionRangeInBlocks(blocks, 'world');
      expect(range, (6, 11));
    });

    test('returns null when selection missing', () {
      final blocks = [
        ParagraphBlock(
          lines: [
            LineData(spans: [ReaderInlineSpan(text: 'abc')]),
          ],
        ),
      ];
      expect(resolveSelectionRangeInBlocks(blocks, 'zzz'), isNull);
      expect(blocksContainSelection(blocks, 'abc'), isTrue);
    });
  });

  group('P4 neighbor HTML retention', () {
    test('±2 邻章保留 HTML 供切章直达，更远章节被驱逐', () async {
      final loader = ReaderContentLoader(
        allChapters: [
          ReaderChapter(id: 'c0', title: 'A'),
          ReaderChapter(id: 'c1', title: 'B'),
          ReaderChapter(id: 'c2', title: 'C'),
          ReaderChapter(id: 'c3', title: 'D'),
        ],
      );
      final settings = ReaderViewSettings();
      for (final chapter in loader.allChapters) {
        await loader.loadChapter(
          chapterId: chapter.id,
          content: ReaderChapterContent(
            title: chapter.title,
            content: '<p>${chapter.title}内容</p>',
          ),
          pageWidth: 400,
          pageHeight: 0,
          settings: settings,
          prepareScrollLayout: true,
        );
      }
      loader.setActive('c0');
      loader.dropHtmlForNeighbors('c0');

      final neighbor = loader.getByChapterId('c1');
      expect(neighbor, isNotNull);
      expect(neighbor!.blocks, isNotEmpty);
      expect(neighbor.content.content, isNotEmpty);
      expect(neighbor.content.title, 'B');
      expect(neighbor.blockCharPrefixes.length, neighbor.blocks.length + 1);
      expect(loader.contentFor('c1'), isNotNull);

      final active = loader.getByChapterId('c0');
      expect(active!.content.content, isNotEmpty);

      // ±2 窗口内章节保留。
      expect(loader.getByChapterId('c2'), isNotNull);
      expect(loader.contentFor('c2'), isNotNull);

      // 超出 ±2 的章节被整体驱逐，不再占用内存。
      expect(loader.getByChapterId('c3'), isNull);
      expect(loader.contentFor('c3'), isNull);
    });
  });
}
