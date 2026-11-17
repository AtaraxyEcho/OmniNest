import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = ReaderViewSettings(
    fontFamily: 'sans',
    fontSize: 18,
    lineHeight: 1.6,
  );

  test('懒分页从上一页结束字符继续推进', () {
    final text = List<String>.filled(240, 'pagination content').join(' ');
    final blocks = parseBlocks('<p>$text</p>');

    final first = ReaderPaginationEngine.computePage(
      blocks,
      180,
      140,
      settings,
      0,
    );

    expect(first, isNotNull);
    expect(first!.endCharOffset, greaterThan(first.startCharOffset));
    expect(first.endCharOffset, lessThan(text.length));

    final second = ReaderPaginationEngine.computePage(
      blocks,
      180,
      140,
      settings,
      first.endCharOffset,
    );

    expect(second, isNotNull);
    expect(second!.startCharOffset, first.endCharOffset);
    expect(second.endCharOffset, greaterThan(second.startCharOffset));
  });

  test('视觉行字符范围保持单调且包含全局偏移', () {
    final blocks = parseBlocks(
      '<p>${List<String>.filled(40, 'visual line').join(' ')}</p>',
    );
    final paragraph = blocks.single;

    final lines = ReaderPaginationEngine.measureVisualLines(
      paragraph,
      160,
      settings,
      1,
      blockGlobalOffset: 32,
    );

    expect(lines.length, greaterThan(1));
    expect(lines.first.globalStart, greaterThanOrEqualTo(32));
    for (var index = 0; index < lines.length; index++) {
      expect(lines[index].globalEnd, greaterThan(lines[index].globalStart));
      if (index > 0) {
        expect(
          lines[index].globalStart,
          greaterThanOrEqualTo(lines[index - 1].globalStart),
        );
        expect(
          lines[index].globalEnd,
          greaterThanOrEqualTo(lines[index - 1].globalEnd),
        );
      }
    }
  });

  test('文本块高度与字符内偏移高度保持有效范围', () {
    final block =
        parseBlocks(
          '<p>${List<String>.filled(30, 'height sample').join(' ')}</p>',
        ).single;
    final totalHeight = ReaderPaginationEngine.measureBlockHeight(
      block,
      200,
      settings,
    );
    final partialHeight = ReaderPaginationEngine.measureHeightToCharOffset(
      block,
      200,
      settings,
      24,
    );

    expect(totalHeight, greaterThan(0));
    expect(partialHeight, greaterThanOrEqualTo(0));
    expect(partialHeight, lessThanOrEqualTo(totalHeight));
  });
  test('分页切片的实际排版高度不会超过可用视口', () {
    const pageWidth = 320.0;
    const pageHeight = 360.0;
    final text = List<String>.filled(260, '桌面窗口变化后分页内容仍需完整衔接').join();
    final blocks = parseBlocks('<p>$text</p>');
    var startOffset = 0;
    var pageCount = 0;

    while (startOffset < text.length && pageCount < 200) {
      final slice = ReaderPaginationEngine.computePage(
        blocks,
        pageWidth,
        pageHeight,
        settings,
        startOffset,
      );
      expect(slice, isNotNull);
      expect(slice!.endCharOffset, greaterThan(startOffset));

      final visibleBlocks = BlockClipper.clipBlocksByCharRange(
        blocks,
        slice.startCharOffset,
        slice.endCharOffset,
      );
      final renderedHeight = visibleBlocks.fold<double>(
        0,
        (height, block) =>
            height +
            ReaderPaginationEngine.measureBlockHeight(
              block,
              pageWidth,
              settings,
            ),
      );
      expect(renderedHeight, lessThanOrEqualTo(pageHeight));

      startOffset = slice.endCharOffset;
      pageCount++;
    }

    expect(startOffset, text.length);
    expect(pageCount, greaterThan(1));
  });

  test('窗口高度变化后分页末行始终完整落在底部安全区内', () {
    const pageWidth = 320.0;
    final text = List<String>.filled(180, '窗口缩放时最后一行不能只显示一半').join();
    final blocks = parseBlocks('<p>$text</p>');
    final lines = ReaderPaginationEngine.measureVisualLines(
      blocks.single,
      pageWidth,
      settings,
      1,
      blockGlobalOffset: 0,
    );

    for (final pageHeight in <double>[241.5, 317.25, 463.75]) {
      final slice = ReaderPaginationEngine.computePage(
        blocks,
        pageWidth,
        pageHeight,
        settings,
        0,
      );
      expect(slice, isNotNull);
      final fittedHeight = lines
          .where((line) => line.globalEnd <= slice!.endCharOffset)
          .fold<double>(0, (height, line) => height + line.height);
      final usableHeight = ReaderPaginationEngine.usablePageHeight(
        pageHeight,
        settings,
        1,
      );
      final renderedLineHeight = settings.fontSize * settings.lineHeight;

      expect(fittedHeight, lessThanOrEqualTo(usableHeight + 0.01));
      expect(pageHeight - usableHeight, greaterThan(renderedLineHeight));
    }
  });

  test('整章只有图片时按块逐页出，一章的图片不会只露第一张', () {
    // 零字符块在字符轴上没有宽度：旧写法在 `_totalChars == 0` 时把整章压成一页，
    // 游标推不动，第二页永远不会出现，读者看到的就是"导入成功但只有一张图"。
    final blocks = <ContentBlock>[
      for (var i = 0; i < 6; i++) ImageBlock(src: 'images/$i.png'),
    ];

    final covered = <int>[];
    var cursor = 0;
    var pages = 0;
    while (pages < 20) {
      final slice = ReaderPaginationEngine.computePage(
        blocks,
        320,
        100,
        settings,
        cursor,
      );
      if (slice == null) break;
      expect(slice.endIndex, greaterThan(slice.startIndex), reason: '一页不放任何块');
      covered.addAll(
        List.generate(
          slice.endIndex - slice.startIndex,
          (i) => slice.startIndex + i,
        ),
      );
      cursor = slice.cursorEnd >= 0 ? slice.cursorEnd : slice.endCharOffset;
      pages++;
    }

    expect(pages, greaterThan(1), reason: '$pages 页放不下 6 张图');
    covered.sort();
    expect(
      covered,
      List<int>.generate(blocks.length, (i) => i),
      reason: '每块图片要恰好出现一次',
    );
  });

  group('零宽图片组的页高预算', () {
    /// 沿生产页链走完整章：`computeNextPage` 就是翻页导航器用的那条推进规则，
    /// 测试自己另写一份游标算法就只能验到测试自己的假设。
    List<PageSlice> walk(List<ContentBlock> blocks, double pageHeight) {
      final layout = ReaderPaginationEngine.preparePageLayout(
        blocks,
        320,
        pageHeight,
        settings,
      );
      final pages = <PageSlice>[];
      PageSlice? previous;
      for (var page = 0; page < 24; page++) {
        final slice = layout.computeNextPage(previous);
        if (slice == null) break;
        if (pages.isNotEmpty) {
          expect(
            slice.startCharOffset,
            pages.last.endCharOffset,
            reason: '第 ${pages.length} 页与上一页的字符窗口不接续',
          );
        }
        pages.add(slice);
        previous = slice;
      }
      return pages;
    }

    /// 每块图片落在哪一页：图片是原子块，一页要么整块画要么不画。
    Map<int, int> imagePageIndexes(
      List<ContentBlock> blocks,
      List<PageSlice> pages,
    ) {
      final result = <int, int>{};
      for (var page = 0; page < pages.length; page++) {
        for (
          var index = pages[page].startIndex;
          index < pages[page].endIndex;
          index++
        ) {
          if (blocks[index] is ImageBlock) result[index] = page;
        }
      }
      return result;
    }

    test('两张连图放不下在一页时按页高切开，一张也不许静默看不见', () {
      final blocks = parseBlocks(
        '<p>图前的正文一段。</p>'
        '<img src="images/a.png"/><img src="images/b.png"/>'
        '<p>图后的正文一段。</p>',
      );
      final images = [
        for (var i = 0; i < blocks.length; i++)
          if (blocks[i] is ImageBlock) i,
      ];
      expect(images, hasLength(2));
      final singleImageHeight = ReaderPaginationEngine.measureBlockHeight(
        blocks[images.first],
        320,
        settings,
      );
      // 夹具自检：页高必须小于单张图，否则这条用例没在验切开。
      expect(singleImageHeight, greaterThan(300));

      final pages = walk(blocks, 300);
      final placement = imagePageIndexes(blocks, pages);
      expect(placement.keys.toList()..sort(), images);
      expect(
        placement.values.toSet().length,
        images.length,
        reason: '两张图被挤在同一页时，翻页内容层不可滚，第二张就是丢给读者的空白',
      );
      expect(
        pages.any(
          (slice) =>
              slice.endIndex > images.last &&
              images.last >= slice.startIndex &&
              slice.startIndex <= images.first,
        ),
        isFalse,
        reason: '链里两张图不能同时出现在一页',
      );
    });

    test('一页装得下整条链时不硬拆，链画完游标照常推进', () {
      final blocks = parseBlocks(
        '<img src="images/a.png"/><img src="images/b.png"/><p>图后的正文一段。</p>',
      );
      final images = [
        for (var i = 0; i < blocks.length; i++)
          if (blocks[i] is ImageBlock) i,
      ];
      final chainHeight = images.fold<double>(
        0,
        (sum, index) =>
            sum +
            ReaderPaginationEngine.measureBlockHeight(
              blocks[index],
              320,
              settings,
            ),
      );

      final pages = walk(blocks, 1200);
      final packed = pages.where(
        (slice) =>
            slice.startIndex <= images.first &&
            slice.endIndex >= images.last + 1,
      );
      expect(packed, hasLength(1), reason: '链高 $chainHeight，页高 1200 放得下就别拆');
      expect(packed.first.chainContinueBlock, lessThan(0));
      expect(
        packed.first.accountedHeight,
        closeTo(chainHeight, 0.5),
        reason: '链页也要把装到的高度算出来，回归才知道预算是谁超的',
      );
    });

    test('分隔线与图片混成一条链时逐块覆盖，后面的正文不被吞', () {
      final blocks = parseBlocks(
        '<hr/><img src="images/a.png"/><hr/><img src="images/b.png"/><p>链后的正文一段。</p>',
      );
      final zeroWidth = [
        for (var i = 0; i < blocks.length; i++)
          if (BlockClipper.blockCharCount(blocks[i]) == 0) i,
      ];
      expect(zeroWidth, hasLength(4));

      final pages = walk(blocks, 300);
      final covered = <int>[];
      for (final slice in pages) {
        if (slice.endCharOffset > slice.startCharOffset) continue;
        covered.addAll(
          List.generate(
            slice.endIndex - slice.startIndex,
            (i) => slice.startIndex + i,
          ),
        );
      }
      covered.sort();
      expect(covered, zeroWidth, reason: '链里每块要恰好出现一次，不多画也不漏画');

      final textIndex = blocks.length - 1;
      expect(
        pages.any(
          (slice) =>
              slice.endCharOffset > slice.startCharOffset &&
              slice.endIndex > textIndex,
        ),
        isTrue,
        reason: '链画完后正文必须重新起一页，第一个字符不能被链吃掉',
      );
    });

    test('章末以分隔线收尾时，与正文同页也要把分隔线画出来', () {
      // 渲染侧按字符区间裁剪（`_sliceVisibleBlocks`），而分隔线在字符轴上是零宽：
      // 起点等于本页 endCharOffset 的零宽块会被区间裁剪当成"下一页的块"丢掉，
      // 引擎明明把它装进了这一页（endIndex 覆盖到），读者看到的却是少了那道线。
      final blocks = parseBlocks('<p>正文一段。</p><hr/>');
      final layout = ReaderPaginationEngine.preparePageLayout(
        blocks,
        320,
        600,
        settings,
      );
      final slice = layout.computePage(0);
      expect(slice, isNotNull);
      expect(slice!.endIndex, blocks.length, reason: '引擎把末尾的分隔线装进了这一页');
      expect(slice.endCharOffset, greaterThan(slice.startCharOffset));

      final visible = BlockClipper.clipBlocksByPageRange(blocks, slice);
      expect(
        visible.whereType<DividerBlock>(),
        hasLength(1),
        reason: '引擎算了高度的块，渲染侧不能不画',
      );
      expect(
        visible.whereType<ParagraphBlock>(),
        hasLength(1),
        reason: '补尾不能把正文补成两份',
      );
    });

    test('比一页还高的图片按页高收缩，引擎不再把它记成超预算', () {
      // 渲染侧的槽位本来就按页框收缩（clampSlotToConstraints），测量侧过去只看
      // 宽度公式：一张 482 的图在 300 高的页上被记成 482，链装页与预算对账都按
      // 放不下的那一页算，而读者看到的其实是一张收缩后放得下的图。
      const html = '<img src="images/a.png"/><p>正文一段。</p>';
      final blocks = parseBlocks(html);
      expect(
        ReaderPaginationEngine.measureBlockHeight(blocks.first, 320, settings),
        greaterThan(300),
        reason: '夹具要真的高过页，否则这条断不到收缩',
      );
      final layout = ReaderPaginationEngine.preparePageLayout(
        blocks,
        320,
        300,
        settings,
      );
      final slice = layout.computePage(0);
      expect(slice, isNotNull);
      expect(
        slice!.accountedHeight,
        lessThanOrEqualTo(300),
        reason: '一页只放这张图，预算必须算得下',
      );
      // 滚动高度表不传上界：那里的渲染同样拿到无界约束，钳了就会比表里矮。
      expect(
        ReaderPaginationEngine.measureBlockHeight(blocks.first, 320, settings),
        greaterThan(
          ReaderPaginationEngine.measureBlockHeight(
            blocks.first,
            320,
            settings,
            availableHeight: 300,
          ),
        ),
      );
    });
  });

  test('一行比页还高时页链仍然逐字覆盖，不重复不吞字', () {
    // 页高 5px 时任何一行都放不下：引擎必须强制收下每一行并继续推进，
    // 而不是靠"多占一格游标"来脱身 —— 那样下一页会从同一格起头，字被画两次。
    final blocks = parseBlocks('<p>第一段正文</p><p>第二段正文</p>');
    final total = blocks.fold<int>(
      0,
      (sum, block) => sum + BlockClipper.blockCharCount(block),
    );

    final windows = <List<int>>[];
    var cursor = 0;
    for (var page = 0; page < 12; page++) {
      final slice = ReaderPaginationEngine.computePage(
        blocks,
        320,
        5,
        settings,
        cursor,
      );
      if (slice == null) break;
      expect(
        slice.endCharOffset,
        greaterThan(slice.startCharOffset),
        reason: '第 $page 页不放任何字符',
      );
      expect(slice.startCharOffset, cursor, reason: '第 $page 页与上一页之间有空洞或重叠');
      windows.add([slice.startCharOffset, slice.endCharOffset]);
      cursor = slice.cursorEnd >= 0 ? slice.cursorEnd : slice.endCharOffset;
    }

    expect(cursor, total, reason: '页链没有走到本章末尾：$windows');
    expect(windows.length, greaterThan(1));
  });

  test('引用块的盒留白分两头收取', () {
    // 跨页引用的续页只画下半截盒子：整份留白预扣进每一页，会让续页白丢一份盒留白
    // （加上段距更多），翻页内容层不可滚，白丢的就是被挤到下一页的行。
    final quote =
        parseBlocks(
              '<blockquote>${'引用内容 quote text ' * 40}</blockquote>',
            ).single
            as BlockquoteBlock;
    final total = BlockClipper.blockCharCount(quote);

    expect(
      ReaderContentBlockItem.blockChromeHeight(quote, settings),
      ReaderContentBlockItem.blockLeadingChrome(quote, settings) +
          ReaderContentBlockItem.blockTrailingChrome(quote, settings),
    );
    expect(
      ReaderContentBlockItem.blockLeadingChrome(quote, settings),
      ReaderContentBlockItem.blockquoteOuterTopPadding +
          ReaderContentBlockItem.blockquoteInnerVerticalPadding,
    );
    expect(
      ReaderContentBlockItem.blockTrailingChrome(quote, settings),
      ReaderContentBlockItem.blockquoteOuterBottomPadding +
          ReaderContentBlockItem.blockquoteInnerVerticalPadding,
    );

    // 稿子 `.article-column blockquote` 的字档：比正文大 1px、行高固定 1.75。
    // 测量与渲染必须读同一份，否则引用块每页行数与装页算出的不一致，页底直接裁字。
    final quoteStyle = settings.blockquoteStyle();
    expect(
      quoteStyle.fontSize,
      settings.bodyStyle.fontSize! + blockquoteFontDeltaPx,
    );
    expect(quoteStyle.height, blockquoteLineHeight);
    expect(
      settings.blockquoteStrutStyle().fontSize,
      quoteStyle.fontSize,
      reason: 'strut 与文字样式不同源就会折出另一种行数',
    );
    expect(
      settings.blockquoteStyle(textScale: 1.5).fontSize,
      quoteStyle.fontSize! * 1.5,
    );

    final continuation =
        BlockClipper.trimBlockByCharRange(quote, 1, total)! as BlockquoteBlock;
    expect(continuation.hasTopPadding, isFalse);
    expect(
      ReaderContentBlockItem.blockLeadingChrome(continuation, settings),
      0.0,
    );

    final head =
        BlockClipper.trimBlockByCharRange(quote, 0, total - 1)!
            as BlockquoteBlock;
    expect(head.hasTopPadding, isTrue);
    expect(head.hasBottomPadding, isFalse);
    expect(ReaderContentBlockItem.blockTrailingChrome(head, settings), 0.0);
  });

  test('页首零宽块与放不下首行并存时不重复绘制', () {
    // 分隔线没有字符宽度：页首回退把它纳进本页后，如果紧随的第一行放不下，
    // 引擎只能"多走一格"来推进游标。那一格如果同时属于下一页，就是重复绘制。
    final blocks = parseBlocks(
      '<p>${'甲段正文内容一二三' * 12}</p><hr><p>${'乙段正文内容一二三' * 12}</p>',
    );
    const width = 320.0;
    final total = blocks.fold<int>(
      0,
      (sum, block) => sum + BlockClipper.blockCharCount(block),
    );
    expect(total, greaterThan(0));

    for (final height in <double>[40, 48, 60, 88, 120, 240]) {
      final windows = <List<int>>[];
      var cursor = 0;
      var expected = 0;
      for (var page = 0; page < (total ~/ 10) + 16; page++) {
        final slice = ReaderPaginationEngine.computePage(
          blocks,
          width,
          height,
          settings,
          cursor,
        );
        if (slice == null) break;
        expect(
          slice.startCharOffset,
          expected,
          reason:
              '页高 $height 第 $page 页与上一页不接续：'
              '起点 ${slice.startCharOffset}，上一页写到 $expected',
        );
        windows.add([slice.startCharOffset, slice.endCharOffset]);
        expected = slice.endCharOffset;
        final next =
            slice.cursorEnd >= 0 ? slice.cursorEnd : slice.endCharOffset;
        if (next <= cursor) break;
        cursor = next;
      }
      expect(cursor, total, reason: '页高 $height 的页链没有走到本章末尾：$windows');
    }
  });

  group('PageNavigator 缓存窗口（R1）', () {
    // 淘汰切掉前缀页时，_findCachedPage 的二分会落进空洞并返回 null，
    // findPageByCharOffset 便把整段已算页当成没算过、一路冲到章尾；
    // 递归取前一页则会让用户回跳时在一帧内从目标页重算到第 0 页。
    const charsPerPage = 10;
    const pageCount = 700;

    PageNavigator buildNavigator(List<int> computed) {
      final blocks = parseBlocks('<p>${'x' * (pageCount * charsPerPage)}</p>');
      return PageNavigator(
        blocks: blocks,
        computeFn: (previous) {
          final start = previous == null ? 0 : previous.endCharOffset;
          computed.add(start);
          if (start >= pageCount * charsPerPage) return null;
          return PageSlice(
            startIndex: 0,
            endIndex: blocks.length,
            startCharOffset: start,
            endCharOffset: start + charsPerPage,
            cursorEnd: start + charsPerPage,
          );
        },
      );
    }

    test('回跳到前缀页不重算，淘汰只裁远端尾部', () {
      final computed = <int>[];
      final navigator = buildNavigator(computed);

      expect(navigator.getSlice(600), isNotNull);
      expect(computed, hasLength(601), reason: '向前推进必须逐页递推，一页只算一次');

      computed.clear();
      expect(navigator.getSlice(5), isNotNull);
      expect(computed, isEmpty, reason: '前缀还在缓存里就重算，等于把回跳变成整章重排');
      // 超限时裁掉 hi 之后的远端页，并把已算游标同步回拨。
      expect(navigator.readablePageCount, 5 + 64 + 1);
    });

    test('淘汰之后按字符偏移定位不再误跳章尾', () async {
      final computed = <int>[];
      final navigator = buildNavigator(computed);
      navigator.getSlice(600);
      navigator.getSlice(5);

      expect(
        await navigator.findPageByCharOffset(45),
        4,
        reason: '第 4 页仍在连续前缀里，二分不该因为远处有空洞就整段放弃',
      );
      expect(
        await navigator.findPageByCharOffset(105 * charsPerPage + 3),
        105,
        reason: '被淘汰的远端页应当向前重算到位，而不是返回最后一页',
      );
    });
  });
}
