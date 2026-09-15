import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
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

  /// 懒计算单页：从指定字符偏移开始，按像素累积填充一页。
  ///
  /// [startCharOffset] 是章节全文中的字符偏移，用于精确定位续接点。
  /// 内部自动将字符偏移转换为 block 索引和视觉行位置。
  /// 返回 null 表示已到达内容末尾。
  static PageSlice? computePage(
    List<ContentBlock> blocks,
    double pageWidth,
    double pageHeight,
    ReaderViewSettings settings,
    int startCharOffset, {
    double textScale = 1.0,
  }) {
    return preparePageLayout(
      blocks,
      pageWidth,
      pageHeight,
      settings,
      textScale: textScale,
    ).computePage(startCharOffset);
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

  /// 计算单个 block 的渲染高度（像素）。
  ///
  /// 公式与 ReaderViewContent._buildBlock() 逐像素对齐。
  static double measureBlockHeight(
    ContentBlock block,
    double effectiveWidth,
    ReaderViewSettings settings, {
    double textScale = 1.0,
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
      ParagraphBlock(:final lines, :final hasTrailingSpacing) =>
        _ReaderPaginationMetrics.paragraphHeight(
          lines,
          hasTrailingSpacing,
          effectiveWidth,
          settings,
          textScale,
        ),
      ImageBlock(:final caption) => _ReaderPaginationMetrics.imageHeight(
        effectiveWidth,
        caption,
      ),
      DividerBlock() => _ReaderPaginationMetrics.dividerHeight,
      BlockquoteBlock(:final lines) =>
        _ReaderPaginationMetrics.blockquoteHeight(
          lines,
          effectiveWidth,
          settings,
          textScale,
        ),
      ListBlock(:final items) => _ReaderPaginationMetrics.listHeight(
        items,
        effectiveWidth,
        settings,
        textScale,
      ),
      TableBlock(:final rows) => _ReaderPaginationMetrics.tableHeight(
        rows,
        effectiveWidth,
        settings,
        textScale,
      ),
    };
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
        block is TableBlock) {
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

  /// 已执行的文本布局测量次数，用于性能回归测试。
  int get visualLineMeasurementCount =>
      _regularVisualLines.length + _continuationVisualLines.length;

  /// 从章节字符偏移计算一页内容。
  PageSlice? computePage(int startCharOffset) {
    if (blocks.isEmpty) return null;

    if (_totalChars == 0) {
      if (startCharOffset > 0) return null;
      return PageSlice(
        startIndex: 0,
        endIndex: blocks.length,
        startCharOffset: 0,
        endCharOffset: 0,
      );
    }

    // 图片页寻址：零字符图片块在字符轴上宽度为 0，普通二分定位会跳过它，
    // 导致放不下整页的图片被静默丢弃。游标落在图片块起点时单独产出一页。
    final imagePage = _imagePageAt(startCharOffset);
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
    if (blockIndex >= blocks.length) return null;
    final startBlockIndex = blockIndex;

    while (blockIndex < blocks.length) {
      final block = blocks[blockIndex];
      if (_isAtomicBlock(block)) {
        if (_ReaderPaginationTextLayout.blockCharCount(block) > 0 &&
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
            );
          }
          // 当前页即图片组本身（正常情况下由 _imagePageAt 处理）：
          // 整组产出一页，靠块区间渲染。
          return PageSlice(
            startIndex: imageGroupStart,
            endIndex: _imageGroupEnd(blockIndex),
            startCharOffset: effectiveStart,
            endCharOffset: effectiveStart,
            cursorEnd: effectiveStart + 1,
          );
        }
        if (usedHeight + height > budget && blockIndex > startBlockIndex) {
          return PageSlice(
            startIndex: startBlockIndex,
            endIndex: blockIndex,
            startCharOffset: effectiveStart,
            endCharOffset: _charOffsets[blockIndex],
          );
        }
        if (usedHeight + height > budget && blockIndex == startBlockIndex) {
          final endOffset =
              blockIndex + 1 < blocks.length
                  ? _charOffsets[blockIndex + 1]
                  : _charOffsets[blockIndex] +
                      _ReaderPaginationTextLayout.blockCharCount(block);
          return PageSlice(
            startIndex: startBlockIndex,
            endIndex: blockIndex + 1,
            startCharOffset: effectiveStart,
            endCharOffset: endOffset,
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
      var isFirstLineOfPage = usedHeight <= 0;
      while (visualLineIndex < visualLines.length) {
        final visualLine = visualLines[visualLineIndex];
        final height = visualLine.height;
        if (usedHeight + height > budget &&
            (blockIndex > startBlockIndex || !isFirstLineOfPage)) {
          return PageSlice(
            startIndex: startBlockIndex,
            endIndex: blockIndex + 1,
            startCharOffset: effectiveStart,
            endCharOffset: _safeEndOffset(
              visualLine.globalStart,
              effectiveStart,
            ),
          );
        }
        if (isFirstLineOfPage && height > budget) {
          visualLineIndex++;
          if (visualLineIndex >= visualLines.length) {
            blockIndex++;
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
          );
        }
        usedHeight += height;
        isFirstLineOfPage = false;
        visualLineIndex++;
      }

      if (block is ParagraphBlock && block.hasTrailingSpacing) {
        usedHeight += settings.fontSize * 0.6;
      }
      blockIndex++;
    }

    return PageSlice(
      startIndex: startBlockIndex,
      endIndex: blocks.length,
      startCharOffset: effectiveStart,
      endCharOffset: _totalChars,
    );
  }

  /// 游标落在零字符块（图片/分隔线）起点时产出的独占页。
  ///
  /// 图片页的真实字符区间为零宽（[startCharOffset] == [endCharOffset]），
  /// 通过 [PageSlice.cursorEnd] 指向图片之后，保证页链继续推进。
  PageSlice? _imagePageAt(int cursor) {
    final runs = _imageRuns ??= _buildImageRuns();
    final run = runs[cursor];
    if (run == null) {
      return null;
    }
    return PageSlice(
      startIndex: run.$1,
      endIndex: run.$2,
      startCharOffset: cursor,
      endCharOffset: cursor,
      cursorEnd: cursor + 1,
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
      if (_ReaderPaginationTextLayout.blockCharCount(blocks[i]) != 0) {
        i++;
        continue;
      }
      var end = i;
      var hasImage = false;
      while (end < blocks.length &&
          _ReaderPaginationTextLayout.blockCharCount(blocks[end]) == 0) {
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
    if (previous < 0 ||
        _ReaderPaginationTextLayout.blockCharCount(blocks[previous]) != 0) {
      return cursor;
    }
    return _charOffsets[index];
  }

  bool _isAtomicBlock(ContentBlock block) =>
      block is HeadingBlock ||
      block is ImageBlock ||
      block is DividerBlock ||
      block is TableBlock;

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

  int _findStartBlockIndex(int startCharOffset) {
    var low = 0;
    var high = blocks.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      final blockEnd =
          _charOffsets[middle] +
          _ReaderPaginationTextLayout.blockCharCount(blocks[middle]);
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
