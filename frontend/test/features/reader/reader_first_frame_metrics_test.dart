import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：小章首帧一次测完整章，不再经过"估算尾部"窗口。
///
/// 估算与精测在 #47 之后已是同一高度来源，差别只剩覆盖范围：旧实现首帧只测
/// 头部 12 块、尾部按块型均值填充，深位置首落因此按均值偏一次，再由恢复监控
/// 期重新对齐；而条目确定高度（#50）本来也要等整章精测才可用。
void main() {
  final settings = ReaderViewSettings(
    fontFamily: 'sans',
    fontSize: 18,
    lineHeight: 1.6,
  );
  const pageWidth = 400.0;

  final chapters = [
    ReaderChapter(id: 'chapter_1', chapterNumber: 1, title: '第一章'),
    ReaderChapter(id: 'chapter_2', chapterNumber: 2, title: '第二章'),
    ReaderChapter(id: 'chapter_3', chapterNumber: 3, title: '第三章'),
  ];

  /// 标题不与相邻段落合并，交替排版才能稳定产出多于头部批次的块数。
  ReaderChapterContent chapterContent({required int sections}) {
    final html =
        List<String>.generate(
          sections,
          (index) => '<h3>小节 $index</h3><p>第 $index 段正文内容。</p>',
        ).join();
    return ReaderChapterContent(title: '第一章', content: html);
  }

  Future<ChapterData> load(
    ReaderContentLoader loader, {
    required String chapterId,
    required int sections,
  }) {
    return loader.loadChapter(
      chapterId: chapterId,
      content: chapterContent(sections: sections),
      pageWidth: pageWidth,
      pageHeight: 700,
      settings: settings,
    );
  }

  group('首帧滚动度量', () {
    test('当前章块数在同步预算内时，首帧即整章精测', () async {
      final loader = ReaderContentLoader(allChapters: chapters);
      loader.setActive('chapter_1');
      final data = await load(loader, chapterId: 'chapter_1', sections: 40);

      expect(data.blocks.length, greaterThan(_phaseOneHint));
      expect(data.blocks.length, lessThanOrEqualTo(_syncHint));
      expect(data.hasPreciseHeights, isTrue);
      expect(data.blockExtents, hasLength(data.blocks.length));
    });

    test('整章表的高度含标题后的层间距', () async {
      final loader = ReaderContentLoader(allChapters: chapters);
      final data = await load(loader, chapterId: 'chapter_1', sections: 8);

      final extents = data.blockExtents;
      expect(extents, hasLength(data.blocks.length));
      for (var i = 0; i < data.blocks.length; i++) {
        final block = data.blocks[i];
        final expected =
            ReaderPaginationEngine.measureBlockHeight(
              block,
              pageWidth,
              settings,
            ) +
            scrollBlockExtraSpacing(block);
        expect(
          extents![i],
          closeTo(expected, 0.01),
          reason: '第 $i 块（${block.runtimeType}）应与真实条目高度一致',
        );
      }
    });

    test('邻章预取仍停在估算，不为一章多跑两章的全量测量', () async {
      final loader = ReaderContentLoader(allChapters: chapters);
      loader.setActive('chapter_1');
      final data = await load(loader, chapterId: 'chapter_3', sections: 40);

      expect(data.blocks.length, greaterThan(_phaseOneHint));
      expect(data.hasPreciseHeights, isFalse);
      expect(data.blockExtents, isNull);
    });
  });
}

/// 与 loader 内部常量对齐的阈值提示：块数必须大于头部批次、小于同步预算。
const _phaseOneHint = 12;
const _syncHint = 200;
