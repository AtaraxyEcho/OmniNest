import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：高度表必须随列宽与文字缩放失效。
///
/// 高度表缓存键只含章节与字号/行高/字体，视口宽度变化后旧表被当作有效值继续
/// 使用：条目实际高度与表不符，字符偏移↔像素映射整章偏；而自 #97f93772 起
/// 这份表还直接决定滚动范围。
void main() {
  final settings = ReaderViewSettings(
    fontFamily: 'sans',
    fontSize: 18,
    lineHeight: 1.6,
  );
  final content = ReaderChapterContent(
    title: '第一章',
    content: '<p>${List<String>.filled(240, 'word').join(' ')}</p>',
  );
  final chapters = [
    ReaderChapter(id: 'chapter_1', chapterNumber: 1, title: '第一章'),
  ];

  Future<double> totalHeightOnce({
    required double pageWidth,
    double textScale = 1.0,
  }) async {
    final loader = ReaderContentLoader(allChapters: chapters);
    final data = await loader.loadChapter(
      chapterId: 'chapter_1',
      content: content,
      pageWidth: pageWidth,
      pageHeight: 600,
      settings: settings,
      textScale: textScale,
    );
    return data.cumulativeHeights.isEmpty ? 0.0 : data.cumulativeHeights.last;
  }

  /// 先按 firstWidth 测得，再按 secondWidth 重新加载同一章。
  Future<double> totalHeightAfterReload({
    required double firstWidth,
    required double secondWidth,
    double secondTextScale = 1.0,
  }) async {
    final loader = ReaderContentLoader(allChapters: chapters);
    await loader.loadChapter(
      chapterId: 'chapter_1',
      content: content,
      pageWidth: firstWidth,
      pageHeight: 600,
      settings: settings,
    );
    final data = await loader.loadChapter(
      chapterId: 'chapter_1',
      content: content,
      pageWidth: secondWidth,
      pageHeight: 600,
      settings: settings,
      textScale: secondTextScale,
    );
    return data.cumulativeHeights.isEmpty ? 0.0 : data.cumulativeHeights.last;
  }

  group('高度表失效', () {
    test('前提：更窄的列显著更高', () async {
      final wide = await totalHeightOnce(pageWidth: 700);
      final narrow = await totalHeightOnce(pageWidth: 300);
      expect(wide, greaterThan(0));
      expect(narrow, greaterThan(wide * 1.5));
    });

    test('列宽变化后重新加载必须按新宽度重算', () async {
      final narrow = await totalHeightOnce(pageWidth: 300);
      final resized = await totalHeightAfterReload(
        firstWidth: 700,
        secondWidth: 300,
      );
      expect(
        resized,
        closeTo(narrow, 1.0),
        reason: '先按 700 宽测得再按 300 宽重载，仍得到旧表：$resized 对 $narrow',
      );
    });

    test('文字缩放变化后必须按新缩放重算', () async {
      final scaled = await totalHeightOnce(pageWidth: 500, textScale: 1.4);
      final resized = await totalHeightAfterReload(
        firstWidth: 500,
        secondWidth: 500,
        secondTextScale: 1.4,
      );
      expect(
        resized,
        closeTo(scaled, 1.0),
        reason: '1.0 缩放的旧表被 1.4 复用：$resized 对 $scaled',
      );
    });

    test('同参数重复加载保持同一结果', () async {
      final stable = await totalHeightAfterReload(
        firstWidth: 600,
        secondWidth: 600,
      );
      final single = await totalHeightOnce(pageWidth: 600);
      expect(stable, closeTo(single, 1.0));
    });

    test('亚像素宽度抖动不作废高度表', () async {
      final loader = ReaderContentLoader(allChapters: chapters);
      final data = await loader.loadChapter(
        chapterId: 'chapter_1',
        content: content,
        pageWidth: 320,
        pageHeight: 600,
        settings: settings,
      );
      await Future<void>.delayed(Duration.zero);

      await loader.loadChapter(
        chapterId: 'chapter_1',
        content: content,
        pageWidth: 320.3,
        pageHeight: 600,
        settings: settings,
      );
      expect(
        data.scrollLayoutPageWidth,
        320,
        reason:
            '桌面自由缩放窗口时每帧零点几像素的抖动都会整表作废；'
            '小章等于每帧一次整章同步测量，翻页导航器早就是 0.5 容差',
      );

      await loader.loadChapter(
        chapterId: 'chapter_1',
        content: content,
        pageWidth: 300,
        pageHeight: 600,
        settings: settings,
      );
      expect(data.scrollLayoutPageWidth, 300, reason: '真正的列宽变化仍必须作废重排');
    });
    test('跨列宽的已精测章节不参与邻章估算基线', () async {
      // 章 A 在 700 宽下已是精测表，章 B 在 300 宽下取估算：
      // 沿用 A 的块型均值会把 B 的尾部整体压低（同一段文字在 300 宽下更高）。
      Future<double> totalWithWarmChapter({required bool warmOther}) async {
        final loader = ReaderContentLoader(
          allChapters: const [
            ReaderChapter(id: 'chapter_1', chapterNumber: 1, title: '第一章'),
            ReaderChapter(id: 'chapter_2', chapterNumber: 2, title: '第二章'),
          ],
        );
        final wide = ReaderChapterContent(
          title: '章',
          content:
              List<String>.generate(
                60,
                (index) =>
                    '<h3>小节 $index</h3><p>第 $index 段正文内容 words text。</p>',
              ).join(),
        );
        if (warmOther) {
          loader.setActive('chapter_1');
          final other = await loader.loadChapter(
            chapterId: 'chapter_1',
            content: wide,
            pageWidth: 700,
            pageHeight: 600,
            settings: settings,
          );
          expect(
            other.hasPreciseHeights,
            isTrue,
            reason: '前置条件：邻章已是精测表，才会被估算基线取用',
          );
        }
        loader.setActive('chapter_2');
        final data = await loader.loadChapter(
          // 240 块超出同步预算，确保走估算尾部。
          chapterId: 'chapter_2',
          content: ReaderChapterContent(
            title: '第二章',
            content:
                List<String>.generate(
                  120,
                  (index) =>
                      '<h3>小节 $index</h3><p>第 $index 段正文内容 words text。</p>',
                ).join(),
          ),
          pageWidth: 300,
          pageHeight: 600,
          settings: settings,
        );
        expect(data.blocks.length, greaterThan(200));
        expect(data.hasPreciseHeights, isFalse, reason: '本例看的是估算尾部');
        return data.cumulativeHeights.last;
      }

      final withNeighbour = await totalWithWarmChapter(warmOther: true);
      final alone = await totalWithWarmChapter(warmOther: false);
      expect(
        withNeighbour,
        closeTo(alone, 1.0),
        reason: '邻章的块型均值来自别的列宽，拿它当基线会让本章估算整体偏小',
      );
    });
  });

  group('scrollMetricsStale', () {
    test('宽度按 0.5 容差、文字缩放按 0.01 容差判定', () {
      expect(
        scrollMetricsStale(
          tablePageWidth: 320,
          tableTextScale: 1.0,
          pageWidth: 320.3,
          textScale: 1.0,
        ),
        isFalse,
      );
      expect(
        scrollMetricsStale(
          tablePageWidth: 320,
          tableTextScale: 1.0,
          pageWidth: 319.4,
          textScale: 1.0,
        ),
        isTrue,
      );
      expect(
        scrollMetricsStale(
          tablePageWidth: 320,
          tableTextScale: 1.0,
          pageWidth: 320,
          textScale: 1.005,
        ),
        isFalse,
        reason: '缩放是倍率而非像素，容差必须比宽度小一个量级',
      );
      expect(
        scrollMetricsStale(
          tablePageWidth: 320,
          tableTextScale: 1.0,
          pageWidth: 320,
          textScale: 1.2,
        ),
        isTrue,
      );
    });
  });

  group('坐标换算与缓存键（R6）', () {
    // 同一章在缓存里按排版参数各留一份，块顶留白又画在第一行文字之前：
    // 换算取错那一份、或者从块顶而不是首行起算，保存的进度就会落到别的行上。
    final quoteContent = ReaderChapterContent(
      title: '第一章',
      content:
          '<p>${'第一段正文 word ' * 40}</p>'
          '<blockquote>${'引用内容 quote ' * 120}</blockquote>'
          '<p>${'收尾正文 tail ' * 40}</p>',
    );

    test('切换跟随原书排版必须重建翻页导航器', () async {
      final follow = settings.copyWith(followBookTypesetting: true);
      final loader = ReaderContentLoader(allChapters: chapters);
      final data = await loader.loadChapter(
        chapterId: 'chapter_1',
        content: content,
        pageWidth: 320,
        pageHeight: 600,
        settings: settings,
      );

      final off = data.getOrCreatePageNavigator(320, 600, settings);
      final on = data.getOrCreatePageNavigator(320, 600, follow);
      expect(identical(off, on), isFalse, reason: '书的段距与行高改了页的切法，同一份页链不能接着用');
      expect(
        identical(on, data.getOrCreatePageNavigator(320, 600, follow)),
        isTrue,
        reason: '同参数反复重建等于每帧重算整章布局',
      );
    });

    test('块顶留白计入像素换算的两头', () async {
      final loader = ReaderContentLoader(allChapters: chapters);
      final data = await loader.loadChapter(
        chapterId: 'chapter_1',
        content: quoteContent,
        pageWidth: 320,
        pageHeight: 600,
        settings: settings,
      );
      final quoteIndex = data.blocks.indexWhere(
        (block) => block is BlockquoteBlock,
      );
      expect(quoteIndex, greaterThan(0), reason: '夹具里引用块前要有正文');

      final blockStart =
          quoteIndex == 0 ? 0.0 : data.cumulativeHeights[quoteIndex - 1];
      final quoteStartChar = data.blockCharPrefixes[quoteIndex];
      final leading = ReaderContentBlockItem.blockLeadingChrome(
        data.blocks[quoteIndex],
        settings,
      );
      expect(leading, greaterThan(0));

      final pixel = loader.charOffsetToPixelOffset(
        'chapter_1',
        quoteStartChar,
        pageWidth: 320,
        settings: settings,
      );
      expect(
        pixel,
        closeTo(blockStart + leading, 0.5),
        reason: '首行之前那一份块顶留白没计进像素换算',
      );
      expect(
        loader.contentYToCharOffset(
          'chapter_1',
          blockStart + leading,
          pageWidth: 320,
          settings: settings,
        ),
        quoteStartChar,
        reason: 'contentY 落在首行起点却换回上一块的字符：行号整体向下错一格',
      );
    });

    test('换算必须按当前排版命中缓存，不拿旧字号的高度表', () async {
      final bigger = settings.copyWith(fontSize: 30);
      final loader = ReaderContentLoader(allChapters: chapters);
      await loader.loadChapter(
        chapterId: 'chapter_1',
        content: quoteContent,
        pageWidth: 320,
        pageHeight: 600,
        settings: settings,
      );
      final bigData = await loader.loadChapter(
        chapterId: 'chapter_1',
        content: quoteContent,
        pageWidth: 320,
        pageHeight: 600,
        settings: bigger,
      );

      final lastBlock = bigData.blocks.length - 1;
      final target = bigData.blockCharPrefixes[lastBlock] + 5;
      final bigBlockStart =
          lastBlock == 0 ? 0.0 : bigData.cumulativeHeights[lastBlock - 1];
      final pixel = loader.charOffsetToPixelOffset(
        'chapter_1',
        target,
        pageWidth: 320,
        settings: bigger,
      );
      expect(
        pixel,
        greaterThanOrEqualTo(bigBlockStart),
        reason:
            '按 30px 换算却落在 18px 表的块起点之前，说明取到旧字号的高度表：'
            '$pixel 对 $bigBlockStart',
      );
    });
  });
}
