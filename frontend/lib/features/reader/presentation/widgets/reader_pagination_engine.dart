import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_content.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

export 'package:omninest/features/reader/presentation/widgets/reader_pagination_models.dart';

part 'reader_pagination_metrics.dart';
part 'reader_pagination_text_layout.dart';

/// 分页引擎：连续排版 + 按像素精确切割。
///
/// 将章节文本行拼成带样式的 TextSpan，用 TextPainter 统一排版，
/// 通过 getPositionForOffset 找到精确切割点。
class ReaderPaginationEngine {
  /// 图片固定槽位高度：渲染（ReaderContentImage）与测高共用。
  ///
  /// 槽位在图片解码前后保持不变，保证真实布局与累积测高零漂移。
  static double imageSlotHeight(double effectiveWidth) =>
      _ReaderPaginationMetrics.imageSlotHeight(effectiveWidth);

  /// 图片题注的行高倍率：渲染与测量共用一条口径。
  static const double imageCaptionLineHeight =
      _ReaderPaginationMetrics.captionLineHeight;

  /// 图片槽位收进可用高度的唯一一条规则：渲染（ReaderContentImage）与测量共用。
  static double clampImageSlot({
    required double slot,
    required double availableHeight,
    required bool hasCaption,
  }) => _ReaderPaginationMetrics.clampImageSlot(
    slot: slot,
    availableHeight: availableHeight,
    hasCaption: hasCaption,
  );

  /// 懒计算单页：从指定字符偏移开始，按像素累积填充一页。
  ///
  /// [startCharOffset] 是章节全文中的字符偏移，用于精确定位续接点。
  /// 内部自动将字符偏移转换为 block 索引和视觉行位置。
  /// [chainContinueBlock] 只在续接一条没画完的零宽块链时给出（见
  /// [PageSlice.chainContinueBlock]），按字符偏移随机访问时留负值。
  /// 返回 null 表示已到达内容末尾。
  static PageSlice? computePage(
    List<ContentBlock> blocks,
    double pageWidth,
    double pageHeight,
    ReaderViewSettings settings,
    int startCharOffset, {
    double textScale = 1.0,
    int chainContinueBlock = -1,
  }) {
    return preparePageLayout(
      blocks,
      pageWidth,
      pageHeight,
      settings,
      textScale: textScale,
    ).computePage(startCharOffset, chainContinueBlock: chainContinueBlock);
  }

  /// 创建可复用的章节分页布局。
  ///
  /// 同一章节翻页时复用字符偏移、块高度与视觉行测量结果，避免在每次翻页时
  /// 重复测量整个长段落。
  static ReaderPageLayout preparePageLayout(
    List<ContentBlock> blocks,
    double pageWidth,
    double pageHeight,
    ReaderViewSettings settings, {
    double textScale = 1.0,
  }) {
    return ReaderPageLayout._(
      blocks: blocks,
      pageWidth: pageWidth,
      pageHeight: usablePageHeight(pageHeight, settings, textScale),
      settings: settings,
      textScale: textScale,
    );
  }

  /// 返回扣除完整行底部安全区后的分页高度。
  ///
  /// Flutter 在不同窗口缩放比例下会产生小数像素，保留部分行高可避免
  /// 最后一行的字形下降部或底部被视口裁切。
  static double usablePageHeight(
    double pageHeight,
    ReaderViewSettings settings,
    double textScale,
  ) {
    final renderedLineHeight =
        settings.fontSize * settings.lineHeight * textScale;
    final safetyInset = math.min(
      renderedLineHeight.ceilToDouble() + 2,
      math.max(1, pageHeight - 1),
    );
    return math.max(1.0, pageHeight - safetyInset);
  }

  /// 测量文本块的视觉行，返回每行的字符范围和高度。
  ///
  /// 供 [ReaderContentLoader.scrollOffsetToCharOffset] 使用，
  /// 实现与 [charOffsetToPixelOffset] 互为逆运算的精确测量。
  static List<VisualLineInfo> measureVisualLines(
    ContentBlock block,
    double pageWidth,
    ReaderViewSettings settings,
    double textScale, {
    required int blockGlobalOffset,
    bool isContinuation = false,
  }) {
    return _ReaderPaginationTextLayout.measureVisualLines(
      block,
      pageWidth,
      settings,
      textScale,
      blockGlobalOffset: blockGlobalOffset,
      isContinuation: isContinuation,
    );
  }

  /// 分割线块的块高，与渲染共用同一组常量（供对照测试引用）。
  static const double dividerHeight = _ReaderPaginationMetrics.dividerHeight;

  /// 表格逐行高度：装页、滚动高度表与渲染分块预留共用这一份。
  ///
  /// 渲染侧首帧只构建一批行，未构建的行按这里的行高预留空位，整表占据的高度才
  /// 与 `measureBlockHeight(TableBlock)` 恒等；两处各写一份就会在补行的那一帧跳动。
  static List<double> tableRowHeights(
    List<TableRowData> rows,
    ReaderViewSettings settings,
    double textScale,
  ) => _ReaderPaginationMetrics.tableRowHeights(rows, settings, textScale);

  /// 计算单个 block 实际占据的高度（像素）：文字行 + 块自身的 padding/段间距。
  ///
  /// 这是块高的唯一来源，滚动高度表、翻页装页与渲染条目三处都必须取这一份；
  /// 渲染条目不再在块外另加间距（标题的 24px 已进块内下内边距），任何"包装层
  /// 再加一点"的写法都会让测量按短了的口径塞页，页底报 RenderFlex 溢出。
  ///
  /// [availableHeight] 是这一页能留给该块的总高度：翻页装页必须传，图片槽位才会
  /// 像渲染那样收缩；滚动高度表留 0（那里的渲染同样拿到无界约束）。
  static double measureBlockHeight(
    ContentBlock block,
    double effectiveWidth,
    ReaderViewSettings settings, {
    double textScale = 1.0,
    double availableHeight = 0.0,
  }) {
    return switch (block) {
      HeadingBlock(:final text, :final level) =>
        _ReaderPaginationMetrics.headingHeight(
          text,
          level,
          effectiveWidth,
          settings,
          textScale,
        ),
      ParagraphBlock() || BlockquoteBlock() || ListBlock() =>
        _flowBlockHeight(block, effectiveWidth, settings, textScale) +
            ReaderContentBlockItem.blockChromeHeight(block, settings),
      ImageBlock(:final caption) => _ReaderPaginationMetrics.imageHeight(
        effectiveWidth,
        caption,
        textScale: textScale,
        availableHeight: availableHeight,
      ),
      DividerBlock() => _ReaderPaginationMetrics.dividerHeight,
      TableBlock(:final rows) => _ReaderPaginationMetrics.tableHeight(
        rows,
        settings,
        textScale,
      ),
    };
  }

  /// 段落、引用块与列表的文字行高度：直接累加共享视觉行结果。
  ///
  /// 逐逻辑行测量会把源文本里的硬换行当成排版换行，与合并渲染的行盒不符：
  /// 同一块在高度表里和块内 charOffset 插值里得到两个高度，差值随硬换行数
  /// 累积（4 行硬换行样例实测 232 对 174 像素）。滚动与翻页共用这一份行盒，
  /// 块自身的 padding/段间距一律由 `blockChromeHeight` 另加，不掺进行高。
  static double _flowBlockHeight(
    ContentBlock block,
    double effectiveWidth,
    ReaderViewSettings settings,
    double textScale,
  ) {
    final visualLines = _ReaderPaginationTextLayout.measureVisualLinesInternal(
      block,
      effectiveWidth,
      settings,
      textScale,
      blockGlobalOffset: 0,
    );
    return visualLines.fold<double>(0.0, (sum, line) => sum + line.height);
  }

  /// 计算从块起始到 [charOffset] 的渲染高度（像素）。
  ///
  /// 文本块使用 TextPainter 精确测量（与分页引擎同一套逻辑），
  /// 非文本块使用线性插值。
  static double measureHeightToCharOffset(
    ContentBlock block,
    double effectiveWidth,
    ReaderViewSettings settings,
    int charOffsetInBlock, {
    double textScale = 1.0,
    int blockGlobalOffset = 0,
    bool isContinuation = false,
  }) {
    // 非文本块：不可分割，返回整块高度或 0
    if (block is HeadingBlock ||
        block is ImageBlock ||
        block is DividerBlock ||
        block is TableBlock ||
        block is ListBlock) {
      // 列表按项渲染（Column + 每项 4px 间隙），视觉行模型把项当作连排文本，
      // 两者不可混用：块高与块内定位统一走整块口径，项内偏移按线性处理。
      return charOffsetInBlock > 0
          ? measureBlockHeight(
            block,
            effectiveWidth,
            settings,
            textScale: textScale,
          )
          : 0;
    }

    // 文本块：使用统一视觉行测量结果计算精确高度
    final visualLines = _ReaderPaginationTextLayout.measureVisualLinesInternal(
      block,
      effectiveWidth,
      settings,
      textScale,
      blockGlobalOffset: blockGlobalOffset,
      isContinuation: isContinuation,
    );

    if (visualLines.isEmpty) return 0;

    var accumulated = 0.0;
    for (final vl in visualLines) {
      // vl.globalEnd 是该视觉行结束字符的全局偏移（不含）
      // 如果 charOffsetInBlock 在该行范围内，说明目标位置在该行内
      final vlLocalEnd = vl.globalEnd - blockGlobalOffset;
      if (charOffsetInBlock <= vlLocalEnd) {
        // 目标在当前视觉行内，按行内比例插值
        final vlLocalStart = vl.globalStart - blockGlobalOffset;
        final lineChars = vlLocalEnd - vlLocalStart;
        if (lineChars > 0) {
          final ratio = ((charOffsetInBlock - vlLocalStart) / lineChars).clamp(
            0.0,
            1.0,
          );
          return accumulated + ratio * vl.height;
        }
        return accumulated;
      }
      accumulated += vl.height;
    }
    return accumulated;
  }

  // ── Step 1：展开 ContentBlock 为 PaginationLineRef 列表 ──

  // ── Step 2：构建带样式的 TextSpan ──

  // ── Step 4：按像素切割 ──
}

/// 单章可复用分页布局。
///
/// 该对象只在视口尺寸或排版设置变化时重建。分页导航过程中会缓存每个文本块
/// 的视觉行和固定块高度，使下一页计算只执行偏移定位与高度累加。
class ReaderPageLayout {
  factory ReaderPageLayout._({
    required List<ContentBlock> blocks,
    required double pageWidth,
    required double pageHeight,
    required ReaderViewSettings settings,
    required double textScale,
  }) {
    final charOffsets =
        _ReaderPaginationTextLayout.computeCumulativeCharOffsets(blocks);
    return ReaderPageLayout._withOffsets(
      blocks: blocks,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      settings: settings,
      textScale: textScale,
      charOffsets: charOffsets,
    );
  }

  ReaderPageLayout._withOffsets({
    required this.blocks,
    required this.pageWidth,
    required this.pageHeight,
    required this.settings,
    required this.textScale,
    required List<int> charOffsets,
  }) : _charOffsets = charOffsets,
       _totalChars =
           blocks.isEmpty
               ? 0
               : charOffsets.last +
                   _ReaderPaginationTextLayout.blockCharCount(blocks.last);

  final List<ContentBlock> blocks;
  final double pageWidth;
  final double pageHeight;
  final ReaderViewSettings settings;
  final double textScale;
  final List<int> _charOffsets;
  final int _totalChars;
  final Map<int, List<PaginationVisualLine>> _regularVisualLines = {};
  final Map<int, List<PaginationVisualLine>> _continuationVisualLines = {};
  final Map<int, double> _fixedBlockHeights = {};

  /// 每块的字符数：`_charOffsets` 的相邻差。
  ///
  /// 二分定位、零字符组判定与图片组回退每页都要问几十次，每次重算一遍块的折行
  /// 记账（逐行 fold 字符数）是白花的；差表一次算好，同域性由前缀表本身保证。
  late final List<int> _blockCharCounts = List<int>.generate(
    blocks.length,
    (index) =>
        index + 1 < blocks.length
            ? _charOffsets[index + 1] - _charOffsets[index]
            : _totalChars - _charOffsets[index],
  );

  int _blockChars(int index) => _blockCharCounts[index];

  /// 已执行的文本布局测量次数，用于性能回归测试。
  int get visualLineMeasurementCount =>
      _regularVisualLines.length + _continuationVisualLines.length;

  /// 上一页之后的一页；[previous] 为空即取本章第一页。
  ///
  /// "页链还能不能继续"只在这里表达一次：游标不前进就算到底，**唯一的例外**是上一页
  /// 把一条零宽块链切到了下一页（那种页靠 [PageSlice.chainContinueBlock] 接着画）。
  /// 翻页导航器与回归语料都必须走这里，两侧各写一份就会一个判成结束、另一个死循环。
  PageSlice? computeNextPage(PageSlice? previous) {
    if (previous == null) return computePage(0);
    if (previous.nextCursor <= previous.startCharOffset &&
        previous.chainContinueBlock < 0) {
      return null;
    }
    return computePage(
      previous.nextCursor,
      chainContinueBlock: previous.chainContinueBlock,
    );
  }

  /// 从章节字符偏移计算一页内容。
  PageSlice? computePage(int startCharOffset, {int chainContinueBlock = -1}) {
    if (blocks.isEmpty) return null;

    if (_totalChars == 0) {
      // 整章都是零字符块（图片、分隔线）：字符轴推不动游标，改按"已画到第几个块"
      // 寻址。旧写法把整章压成一页并按索引裁到末尾，第二页永远不会出现，
      // 读者只看到第一张图，其余的既不出页也不报错。
      if (startCharOffset >= blocks.length) return null;
      final zeroBudget = pageHeight - 1;
      var usedZeroHeight = 0.0;
      var zeroEnd = startCharOffset;
      while (zeroEnd < blocks.length) {
        final height = _fixedBlockHeights.putIfAbsent(
          zeroEnd,
          () => ReaderPaginationEngine.measureBlockHeight(
            blocks[zeroEnd],
            pageWidth,
            settings,
            textScale: textScale,
            availableHeight: pageHeight,
          ),
        );
        if (zeroEnd > startCharOffset && usedZeroHeight + height > zeroBudget) {
          break;
        }
        usedZeroHeight += height;
        zeroEnd++;
      }
      return PageSlice(
        startIndex: startCharOffset,
        endIndex: zeroEnd,
        startCharOffset: 0,
        endCharOffset: 0,
        cursorEnd: zeroEnd,
        accountedHeight: usedZeroHeight,
      );
    }

    // 图片页寻址：零字符图片块在字符轴上宽度为 0，普通二分定位会跳过它，
    // 导致放不下整页的图片被静默丢弃。游标落在图片块起点时单独产出一页。
    final imagePage = _imagePageAt(startCharOffset, chainContinueBlock);
    if (imagePage != null) {
      return imagePage;
    }

    // 游标紧跟在图片页之后时，真实起点需回退到图片后一段正文的块首，
    // 否则该页会裁掉正文的第一个字符（图片页游标 +1 与首字符偏移重合）。
    final effectiveStart = _snapAfterZeroWidthRun(startCharOffset);

    if (effectiveStart >= _totalChars) return null;

    final budget = pageHeight - 1;
    var usedHeight = 0.0;
    var blockIndex = _findStartBlockIndex(effectiveStart);
    blockIndex = _pageHeadBlockIndex(
      blockIndex,
      effectiveStart,
      snappedBack: effectiveStart != startCharOffset,
    );
    if (blockIndex >= blocks.length) return null;
    final startBlockIndex = blockIndex;

    while (blockIndex < blocks.length) {
      final block = blocks[blockIndex];
      if (block is TableBlock) {
        final tableStart = _charOffsets[blockIndex];
        final rowPrefix = _tableRowPrefix(block);
        final rowHeights = _ReaderPaginationMetrics.tableRowHeights(
          block.rows,
          settings,
          textScale,
        );
        final localStart = math.min(
          math.max(effectiveStart - tableStart, 0),
          rowPrefix.last,
        );
        var rowIndex = _rowIndexAtRowStart(rowPrefix, localStart);
        if (rowIndex >= block.rows.length) {
          blockIndex++;
          continue;
        }
        // 片段的外边距同样先确认这一行能在本页起头才扣，口径同正文块。
        final tableChrome = ReaderContentBlockItem.tableVerticalPadding * 2;
        if (blockIndex > startBlockIndex &&
            usedHeight + tableChrome + rowHeights[rowIndex] > budget) {
          return PageSlice(
            startIndex: startBlockIndex,
            endIndex: blockIndex,
            startCharOffset: effectiveStart,
            endCharOffset: tableStart,
            accountedHeight: usedHeight,
          );
        }
        var isFirstRowOfPage = usedHeight <= 0;
        usedHeight += tableChrome;
        while (rowIndex < block.rows.length) {
          final rowHeight = rowHeights[rowIndex];
          if (usedHeight + rowHeight > budget &&
              (blockIndex > startBlockIndex || !isFirstRowOfPage)) {
            return PageSlice(
              startIndex: startBlockIndex,
              endIndex: blockIndex + 1,
              startCharOffset: effectiveStart,
              endCharOffset: tableStart + rowPrefix[rowIndex],
              accountedHeight: usedHeight,
            );
          }
          if (isFirstRowOfPage && rowHeight > budget) {
            // 单行比一整页还高：行是不可分的最小单位，只能让它独占一页。
            return PageSlice(
              startIndex: startBlockIndex,
              endIndex: blockIndex + 1,
              startCharOffset: effectiveStart,
              endCharOffset: tableStart + rowPrefix[rowIndex + 1],
              accountedHeight: usedHeight + rowHeight,
            );
          }
          usedHeight += rowHeight;
          isFirstRowOfPage = false;
          rowIndex++;
        }
        blockIndex++;
        continue;
      }
      if (_isAtomicBlock(block)) {
        if (_blockChars(blockIndex) > 0 &&
            _charOffsets[blockIndex] < effectiveStart) {
          blockIndex++;
          continue;
        }

        final height = _fixedBlockHeights.putIfAbsent(
          blockIndex,
          () => ReaderPaginationEngine.measureBlockHeight(
            block,
            pageWidth,
            settings,
            textScale: textScale,
            availableHeight: pageHeight,
          ),
        );
        // 图片独占一页：当前页已有正文时先收尾，图片由下一页单独渲染。
        final imageGroupStart = _imageGroupStart(blockIndex);
        if (imageGroupStart != null) {
          if (imageGroupStart > startBlockIndex) {
            return PageSlice(
              startIndex: startBlockIndex,
              endIndex: imageGroupStart,
              startCharOffset: effectiveStart,
              endCharOffset: _charOffsets[imageGroupStart],
              accountedHeight: usedHeight,
            );
          }
          // 当前页的页头就是这条链（正常情况下由 _imagePageAt 处理）：
          // 按页高装一页，靠块区间渲染，装不下的接着下一页画。
          return _chainPage(
            _charOffsets[imageGroupStart],
            imageGroupStart,
            _imageGroupEnd(blockIndex),
          );
        }
        if (usedHeight + height > budget && blockIndex > startBlockIndex) {
          return PageSlice(
            startIndex: startBlockIndex,
            endIndex: blockIndex,
            startCharOffset: effectiveStart,
            endCharOffset: _charOffsets[blockIndex],
            accountedHeight: usedHeight,
          );
        }
        if (usedHeight + height > budget && blockIndex == startBlockIndex) {
          final endOffset =
              blockIndex + 1 < blocks.length
                  ? _charOffsets[blockIndex + 1]
                  : _charOffsets[blockIndex] + _blockChars(blockIndex);
          // 零字符块（分隔线）比整页还高时，字符窗口是零宽的：不额外推进游标就会
          // 原地产出一页空窗口，本章剩下的内容再也够不到。按图片组同一约定多走一格，
          // 下一页因此不再回退纳这一块（回退只服务"上一页没画过它"的情形）。
          final zeroWidthRun = _blockChars(blockIndex) == 0;
          return PageSlice(
            startIndex: startBlockIndex,
            endIndex: blockIndex + 1,
            startCharOffset: effectiveStart,
            endCharOffset: endOffset,
            cursorEnd: zeroWidthRun ? endOffset + 1 : -1,
            accountedHeight: usedHeight + height,
          );
        }
        usedHeight += height;
        blockIndex++;
        continue;
      }

      final isContinuation = _charOffsets[blockIndex] < effectiveStart;
      final visualLines = _visualLinesFor(
        blockIndex,
        isContinuation: isContinuation,
      );
      if (visualLines.isEmpty) {
        blockIndex++;
        continue;
      }

      var visualLineIndex = _findVisualLineIndex(visualLines, effectiveStart);
      // 块自身的 padding/段间距先占额度，再逐行判预算：渲染条目每页都把这一份画在块首，
      // 而逐行塞满之后才补加会让整页超出预算正好一个间距（引用块 48、段距 1.35em）。
      // 翻页内容层不可滚，超出的部分不是报错而是被静默裁掉，真书语料里每章都会碰上几页。
      //
      // 预扣之前先确认这一块能在本页起头：连间距带首行都塞不下时整块该推到下一页，
      // 否则这份间距留在本页额度里，而本页并没有画它——引擎自算超页正好一个间距
      // （真书语料里 walden 的 48.15）就是这么来的。
      final blockChrome = ReaderContentBlockItem.blockLeadingChrome(
        block,
        settings,
      );
      // 引用盒的下留白与段距画在块的最后一行之后：只有把这一行放进来那一页才扣，
      // 续页不再画它，收整份就是白丢一截预算（跨页引用每次多出 24 + 段距）。
      final blockTrailingChrome = ReaderContentBlockItem.blockTrailingChrome(
        block,
        settings,
      );
      if (visualLineIndex < visualLines.length &&
          blockIndex > startBlockIndex &&
          usedHeight + blockChrome + visualLines[visualLineIndex].height >
              budget) {
        // 页首回退纳进来的零字符块已经花掉本页额度，而这一块一行都放不下：
        // 此时窗口会退回 effectiveStart（零宽）。必须按图片组同一约定多走一格，
        // 否则这一页什么都不写、游标也不动，本章剩余内容永远翻不到。
        final stalledAtZeroWidth =
            _charOffsets[blockIndex] <= effectiveStart && usedHeight > 0;
        return PageSlice(
          startIndex: startBlockIndex,
          endIndex: blockIndex,
          startCharOffset: effectiveStart,
          endCharOffset: _charOffsets[blockIndex],
          cursorEnd: stalledAtZeroWidth ? effectiveStart + 1 : -1,
          accountedHeight: usedHeight,
        );
      }
      var isFirstLineOfPage = usedHeight <= 0;
      usedHeight += blockChrome;
      while (visualLineIndex < visualLines.length) {
        final visualLine = visualLines[visualLineIndex];
        final isLastLineOfBlock = visualLineIndex == visualLines.length - 1;
        final trailing = isLastLineOfBlock ? blockTrailingChrome : 0.0;
        final height = visualLine.height;
        if (usedHeight + height + trailing > budget &&
            (blockIndex > startBlockIndex || !isFirstLineOfPage)) {
          return PageSlice(
            startIndex: startBlockIndex,
            endIndex: blockIndex + 1,
            startCharOffset: effectiveStart,
            endCharOffset: _safeEndOffset(
              visualLine.globalStart,
              effectiveStart,
            ),
            accountedHeight: usedHeight,
          );
        }
        if (isFirstLineOfPage && height > budget) {
          visualLineIndex++;
          if (visualLineIndex >= visualLines.length) {
            // 这一行比整页还高：强制收下并结束本块。外层循环随后推进块指针，
            // 这里不能再自增一次，否则紧跟在后面的那一块被整页跳过。
            usedHeight += height + trailing;
            break;
          }
          return PageSlice(
            startIndex: startBlockIndex,
            endIndex: blockIndex + 1,
            startCharOffset: effectiveStart,
            endCharOffset: _safeEndOffset(
              visualLines[visualLineIndex].globalStart,
              effectiveStart,
            ),
            accountedHeight: usedHeight + height,
          );
        }
        usedHeight += height + trailing;
        isFirstLineOfPage = false;
        visualLineIndex++;
      }

      // 块间距已在进入本块时按渲染顺序预扣，这里不再补加。
      blockIndex++;
    }

    return PageSlice(
      startIndex: startBlockIndex,
      endIndex: blocks.length,
      startCharOffset: effectiveStart,
      endCharOffset: _totalChars,
      accountedHeight: usedHeight,
    );
  }

  /// 游标落在零字符块（图片/分隔线）起点时产出的独占页。
  ///
  /// 图片页的真实字符区间为零宽（[startCharOffset] == [endCharOffset]），
  /// 通过 [PageSlice.cursorEnd] 指向图片之后，保证页链继续推进。
  /// 链比一页高时按页预算切成多页，续页位置走 [PageSlice.chainContinueBlock]。
  PageSlice? _imagePageAt(int cursor, int chainContinueBlock) {
    final runs = _imageRuns ??= _buildImageRuns();
    final run = runs[cursor];
    if (run == null) {
      return null;
    }
    var start = run.$1;
    if (chainContinueBlock >= start && chainContinueBlock < run.$2) {
      start = chainContinueBlock;
    }
    return _chainPage(cursor, start, run.$2);
  }

  /// 把零宽块链 [start, end) 按页高预算装成一页。
  ///
  /// 链里的块在字符轴上全是零宽，装页时谁也不给谁让位：过去整条链压成一页、又不出
  /// 预算，两张高图就在一页里叠起来，翻页内容层不可滚，被挤下去的那张静默看不见。
  /// 现在装到装不下为止，剩下的用块索引接到下一页；链首那块无条件进页——比整页还高的
  /// 单张图只能独占一页，切成零块的页会推不动游标。
  PageSlice _chainPage(int cursor, int start, int end) {
    final budget = pageHeight - 1;
    var used = 0.0;
    var last = start;
    for (var index = start; index < end; index++) {
      final height = _fixedBlockHeights.putIfAbsent(
        index,
        () => ReaderPaginationEngine.measureBlockHeight(
          blocks[index],
          pageWidth,
          settings,
          textScale: textScale,
          availableHeight: pageHeight,
        ),
      );
      if (index > start && used + height > budget) break;
      used += height;
      last = index + 1;
    }
    final exhausted = last >= end;
    return PageSlice(
      startIndex: start,
      endIndex: last,
      startCharOffset: cursor,
      endCharOffset: cursor,
      cursorEnd: exhausted ? cursor + 1 : cursor,
      chainContinueBlock: exhausted ? -1 : last,
      accountedHeight: used,
    );
  }

  Map<int, (int, int)>? _imageRuns;
  Map<int, int>? _imageGroupStartByIndex;
  Map<int, int>? _imageGroupEndByIndex;

  /// 包含图片的零字符块组的起始块索引；非图片组返回 null。
  int? _imageGroupStart(int blockIndex) {
    _imageRuns ??= _buildImageRuns();
    return _imageGroupStartByIndex?[blockIndex];
  }

  /// 包含图片的零字符块组的结束块索引（不含）。
  int _imageGroupEnd(int blockIndex) {
    _imageRuns ??= _buildImageRuns();
    return _imageGroupEndByIndex?[blockIndex] ?? blockIndex + 1;
  }

  /// 图片独占页索引：键为零字符块组的字符起点偏移，值为 [起始块索引, 结束块索引)。
  ///
  /// 连续零字符块（图片、分隔线）宽度都是 0，必须划入同一页，避免出现无法
  /// 推进的零宽页面；组内不含图片时按普通原子块处理，不在此登记。
  Map<int, (int, int)> _buildImageRuns() {
    final runs = <int, (int, int)>{};
    final startByIndex = <int, int>{};
    final endByIndex = <int, int>{};
    var i = 0;
    while (i < blocks.length) {
      if (_blockChars(i) != 0) {
        i++;
        continue;
      }
      var end = i;
      var hasImage = false;
      while (end < blocks.length && _blockChars(end) == 0) {
        if (blocks[end] is ImageBlock) {
          hasImage = true;
        }
        end++;
      }
      if (hasImage) {
        final start = _charOffsets[i];
        runs[start] = (i, end);
        for (var index = i; index < end; index++) {
          startByIndex[index] = i;
          endByIndex[index] = end;
        }
      }
      i = end;
    }
    _imageGroupStartByIndex = startByIndex;
    _imageGroupEndByIndex = endByIndex;
    return runs;
  }

  /// 游标紧跟零字符块之后时，回退到后一段正文的真实块首。
  ///
  /// 仅当游标恰为该块首 +1 且紧邻零字符块时生效，不会影响段落内的正常分页。
  int _snapAfterZeroWidthRun(int cursor) {
    if (cursor <= 0) {
      return cursor;
    }
    final index = _findStartBlockIndex(cursor);
    if (index >= blocks.length) {
      return cursor;
    }
    if (_charOffsets[index] != cursor - 1) {
      return cursor;
    }
    final previous = index - 1;
    if (previous < 0 || _blockChars(previous) != 0) {
      return cursor;
    }
    return _charOffsets[index];
  }

  bool _isAtomicBlock(ContentBlock block) =>
      block is HeadingBlock || block is ImageBlock || block is DividerBlock;

  /// 表格各行在块内的字符前缀：`prefix[i]` = 前 i 行的字符数，长度 = 行数 + 1。
  ///
  /// 行的字符口径与 `BlockClipper.blockCharCount` 完全一致（各单元格可绘制文本相接，
  /// 没有分隔符），否则切点与裁剪两侧对不上，跨页表格会重字或丢字。
  static List<int> _tableRowPrefix(TableBlock block) {
    final prefix = <int>[0];
    var total = 0;
    for (final row in block.rows) {
      total += row.cells.fold(
        0,
        (sum, cell) => sum + cell.fold(0, (s, span) => s + span.text.length),
      );
      prefix.add(total);
    }
    return prefix;
  }

  /// [localStart] 落在哪一行；行尾之后返回行数，让调用方跳过本块。
  static int _rowIndexAtRowStart(List<int> prefix, int localStart) {
    for (var i = 0; i < prefix.length - 1; i++) {
      if (prefix[i + 1] > localStart) return i;
    }
    return prefix.length - 1;
  }

  List<PaginationVisualLine> _visualLinesFor(
    int blockIndex, {
    required bool isContinuation,
  }) {
    final cache =
        isContinuation ? _continuationVisualLines : _regularVisualLines;
    return cache.putIfAbsent(
      blockIndex,
      () => _ReaderPaginationTextLayout.measureVisualLinesInternal(
        blocks[blockIndex],
        pageWidth,
        settings,
        textScale,
        blockGlobalOffset: _charOffsets[blockIndex],
        isContinuation: isContinuation,
      ),
    );
  }

  /// 渲染侧 `BlockClipper.clipBlocksByCharRange` 会把"起点偏移上正好压着的零字符块"
  /// 回退纳入本页（只排除图片：图片由按索引裁剪的图片页单独出页），而二分定位按
  /// `块尾 <= 起点` 把它们判给上一页。两侧对"页首是谁"判断不同，引擎就少算整块高度，
  /// 翻页内容层不可滚 → 页底那一行被静默裁掉。这里按裁剪侧的同一条判据回退。
  ///
  /// 起始正文块属于图片组时整条回退作废：图片组占的是零宽字符窗口，并进来会让本页
  /// 的起止偏移相同，页链原地踏步（真书语料里 walden 前置页实测过）。混合组
  /// （`<hr>` 紧邻 `<img>`）里分隔线被谁渲染仍未定论，作为单独缺陷跟踪。

  int _pageHeadBlockIndex(
    int textStartIndex,
    int effectiveStart, {
    required bool snappedBack,
  }) {
    if (textStartIndex >= blocks.length) return textStartIndex;
    // 游标是被"多走一格"退回来的：那一串零字符块已经由上一页画过，再回退就是画两遍。
    if (snappedBack) return textStartIndex;
    if (_imageGroupStart(textStartIndex) != null) return textStartIndex;
    var index = textStartIndex;
    while (index > 0 &&
        _charOffsets[index - 1] == effectiveStart &&
        blocks[index - 1] is! ImageBlock &&
        _blockChars(index - 1) == 0) {
      index--;
    }
    if (index == textStartIndex) return textStartIndex;
    // 回退范围里若混进图片组成员，同样放弃：图片不在字符裁剪这一侧出页。
    for (var i = index; i < textStartIndex; i++) {
      if (blocks[i] is ImageBlock || _imageGroupStart(i) != null) {
        return textStartIndex;
      }
    }
    return index;
  }

  int _findStartBlockIndex(int startCharOffset) {
    var low = 0;
    var high = blocks.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      final blockEnd = _charOffsets[middle] + _blockChars(middle);
      if (blockEnd <= startCharOffset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _findVisualLineIndex(
    List<PaginationVisualLine> visualLines,
    int startCharOffset,
  ) {
    var low = 0;
    var high = visualLines.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (visualLines[middle].globalEnd <= startCharOffset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _safeEndOffset(int candidate, int startCharOffset) =>
      candidate > startCharOffset ? candidate : startCharOffset + 1;
}
