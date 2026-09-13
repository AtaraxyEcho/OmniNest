import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：本文件覆盖翻页模式图片独占一页、页链推进与滚动测高一致性。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = ReaderViewSettings(
    fontFamily: 'sans',
    fontSize: 18,
    lineHeight: 1.6,
  );

  const pageWidth = 200.0;
  const pageHeight = 400.0;
  const chapterId = 'chapter-1';

  Future<ChapterData> load(
    ReaderContentLoader loader,
    String html, {
    String title = '第一章',
  }) {
    return loader.loadChapter(
      chapterId: chapterId,
      content: ReaderChapterContent(title: title, content: html),
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      settings: settings,
      prepareScrollLayout: false,
    );
  }

  /// 连续滚动模式加载：需要累积块高度，故开启滚动测高。
  Future<ChapterData> loadForScroll(ReaderContentLoader loader, String html) {
    return loader.loadChapter(
      chapterId: chapterId,
      content: ReaderChapterContent(title: '第一章', content: html),
      pageWidth: pageWidth,
      pageHeight: 0,
      settings: settings,
    );
  }

  /// 构造 N 个段落与分隔线交错的 HTML（防止解析期合并相邻段落）。
  String paragraphsWithDividers(int count) {
    return List.generate(count, (i) => '<p>第 $i 段正文内容。</p><hr/>').join();
  }

  /// 按生产路径走完整页链：PageNavigator.getSlice 直到 null。
  List<PageSlice> walkPages(ChapterData data) {
    final navigator = data.getOrCreatePageNavigator(
      pageWidth,
      pageHeight,
      settings,
    );
    final slices = <PageSlice>[];
    for (var index = 0; index < 500; index++) {
      final slice = navigator.getSlice(index);
      if (slice == null) break;
      slices.add(slice);
    }
    return slices;
  }

  String paragraphText(ContentBlock block) {
    if (block is! ParagraphBlock) return '';
    return block.lines
        .expand((line) => line.spans)
        .map((span) => span.text)
        .join();
  }

  test('图片独占一页且与上下正文不共页', () async {
    final loader = ReaderContentLoader(
      allChapters: [ReaderChapter(id: chapterId, title: '第一章')],
    );
    final data = await load(
      loader,
      '<p>${List<String>.filled(10, '图片之前的正文内容').join()}</p>'
      '<img src="plate.png"/>'
      '<p>${List<String>.filled(10, '图片之后的正文内容').join()}</p>',
    );

    final imageIndex = data.blocks.indexWhere((b) => b is ImageBlock);
    expect(imageIndex, greaterThan(0), reason: '测试数据必须包含图片块');

    final pages = walkPages(data);
    expect(pages.length, greaterThanOrEqualTo(3));

    final imagePages =
        pages
            .where((p) => p.startIndex <= imageIndex && imageIndex < p.endIndex)
            .toList();
    expect(imagePages.length, 1, reason: '图片必须且只能出现一次');
    expect(imagePages.single.startIndex, imageIndex);
    expect(imagePages.single.endIndex, imageIndex + 1);

    for (final page in pages) {
      final clipped = BlockClipper.clipBlocksByIndexRange(
        data.blocks,
        page.startIndex,
        page.endIndex,
      );
      final isImagePage = identical(page, imagePages.single);
      if (isImagePage) {
        expect(clipped.whereType<ImageBlock>().length, 1);
      } else {
        expect(clipped.whereType<ImageBlock>(), isEmpty, reason: '非图片页不得包含图片块');
      }
    }
  });

  test('图片页之后的正文首字符不被裁掉', () async {
    final loader = ReaderContentLoader(
      allChapters: [ReaderChapter(id: chapterId, title: '第一章')],
    );
    final tailText = List<String>.filled(10, '后置正文段落内容').join();
    final data = await load(
      loader,
      '<p>${List<String>.filled(10, '前置正文段落内容').join()}</p>'
      '<img src="plate.png"/>'
      '<p>$tailText</p>',
    );

    final imageIndex = data.blocks.indexWhere((b) => b is ImageBlock);
    final tailIndex = imageIndex + 1;
    final pages = walkPages(data);
    final imagePageIndex = pages.indexWhere(
      (p) => p.startIndex <= imageIndex && imageIndex < p.endIndex,
    );
    expect(imagePageIndex, greaterThanOrEqualTo(0));

    final nextPage = pages[imagePageIndex + 1];
    expect(nextPage.startIndex, tailIndex, reason: '图片之后必须从后一段正文开始');
    expect(
      nextPage.startCharOffset,
      data.blockCharPrefixes[tailIndex],
      reason: '起点必须回退到块首，不能吃掉首字符',
    );

    final clipped = BlockClipper.clipBlocksByIndexRange(
      data.blocks,
      nextPage.startIndex,
      nextPage.endIndex,
    );
    final firstText = clipped
        .map(paragraphText)
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    expect(firstText, isNotEmpty);
    expect(
      tailText.startsWith(firstText),
      isTrue,
      reason: '页首文本必须是段落原文的前缀（未被裁剪首字符）',
    );
  });

  test('页链覆盖全部内容块且游标严格推进', () async {
    final loader = ReaderContentLoader(
      allChapters: [ReaderChapter(id: chapterId, title: '第一章')],
    );
    // 首块为分隔线：零字符块相连的边界情况不能卡死页链。
    final data = await load(
      loader,
      '<hr/>'
      '<img src="a.png"/>'
      '<p>${List<String>.filled(12, '正文内容片段').join()}</p>'
      '<img src="b.png"/>'
      '<p>${List<String>.filled(12, '结尾正文内容').join()}</p>',
    );

    final pages = walkPages(data);
    expect(pages.length, greaterThan(1));

    final covered = <int>{};
    for (final page in pages) {
      expect(
        page.nextCursor,
        greaterThan(page.startCharOffset),
        reason: '每页游标必须严格推进，否则页链会卡死',
      );
      for (var i = page.startIndex; i < page.endIndex; i++) {
        covered.add(i);
      }
    }
    for (var i = 0; i < data.blocks.length; i++) {
      expect(covered.contains(i), isTrue, reason: '块 $i 必须至少出现在一页中');
    }
    // 图片必须都出现。
    final imageIndices = <int>[];
    for (var i = 0; i < data.blocks.length; i++) {
      if (data.blocks[i] is ImageBlock) imageIndices.add(i);
    }
    expect(imageIndices.length, 2);
    for (final index in imageIndices) {
      expect(covered.contains(index), isTrue);
    }
  });

  test('分批精测期间尾部高度不归零', () async {
    final loader = ReaderContentLoader(
      allChapters: [ReaderChapter(id: chapterId, title: '第一章')],
    );
    final data = await loadForScroll(
      loader,
      [
        paragraphsWithDividers(45),
        '<img src="late-figure.png"/>',
        for (var i = 0; i < 5; i++) '<p>第 $i 段后置正文。</p>',
      ].join(),
    );

    expect(data.blocks.length, greaterThan(80));
    final afterFirstBatch = data.cumulativeHeights;
    expect(afterFirstBatch.length, data.blocks.length);
    expect(
      afterFirstBatch.last,
      greaterThan(0),
      reason: '精测未收敛前 cumulative.last 不能为 0，否则窗口高度塌陷导致进度跳变',
    );

    for (var turn = 0; turn < 200 && !data.hasPreciseHeights; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(data.hasPreciseHeights, isTrue);

    var cumulative = 0.0;
    for (var i = 0; i < data.blocks.length; i++) {
      cumulative += ReaderPaginationEngine.measureBlockHeight(
        data.blocks[i],
        pageWidth,
        settings,
      );
      expect(
        (data.cumulativeHeights[i] - cumulative).abs(),
        lessThan(0.01),
        reason: '收敛后 index $i 必须等于全量精确测高',
      );
    }
  });

  test('图片高度使用宽度公式而非类型均值估算', () async {
    final loader = ReaderContentLoader(
      allChapters: [ReaderChapter(id: chapterId, title: '第一章')],
    );
    final data = await loadForScroll(
      loader,
      [
        paragraphsWithDividers(45),
        '<img src="plate-1.png"/>',
        '<p>图后正文。</p>',
      ].join(),
    );

    final imageIndex = data.blocks.indexWhere((b) => b is ImageBlock);
    expect(imageIndex, greaterThan(12), reason: '图片需位于 phase-one 头部之外');

    // 首批（80 块）尚未覆盖图片，此处读到的就是估算值。
    final baseline = data.cumulativeHeights;
    final estimatedImageHeight =
        baseline[imageIndex] - baseline[imageIndex - 1];
    final expectedImageHeight = ReaderPaginationEngine.measureBlockHeight(
      data.blocks[imageIndex],
      pageWidth,
      settings,
    );
    expect(
      estimatedImageHeight,
      closeTo(expectedImageHeight, 0.01),
      reason: '图片高度必须由宽度公式得出，不能被文本行高均值替代',
    );
  });

  test('字符偏移落在图片边界时恢复定位到图片起点', () async {
    final loader = ReaderContentLoader(
      allChapters: [ReaderChapter(id: chapterId, title: '第一章')],
    );
    final data = await loadForScroll(
      loader,
      '<p>前置段落正文。</p><img src="mid.png"/><p>后置段落正文。</p>',
    );

    final imageIndex = data.blocks.indexWhere((b) => b is ImageBlock);
    expect(imageIndex, greaterThan(0));

    final imageStartOffset = data.blockCharPrefixes[imageIndex];
    final imageTopPixel = loader.charOffsetToPixelOffset(
      chapterId,
      imageStartOffset,
      pageWidth: pageWidth,
      settings: settings,
    );
    final expectedPixel = data.cumulativeHeights[imageIndex - 1];
    expect(
      imageTopPixel,
      closeTo(expectedPixel, 0.01),
      reason: '图片起点的 charOffset 必须映射回图片顶部，而不是跳到后一段正文',
    );

    final afterImageOffset = data.blockCharPrefixes[imageIndex + 1] + 1;
    final afterImagePixel = loader.charOffsetToPixelOffset(
      chapterId,
      afterImageOffset,
      pageWidth: pageWidth,
      settings: settings,
    );
    expect(
      afterImagePixel,
      greaterThan(imageTopPixel + 1),
      reason: '图片之后的正文必须定位到图片下方',
    );
  });
}
