import 'dart:math' as math;

import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_models.dart';

/// 按字符范围裁剪 ContentBlock 列表的静态工具类。
///
/// 所有方法为纯函数，不依赖任何实例状态。
/// 从 reader_view_page.dart 提取，降低主文件行数。
class BlockClipper {
  BlockClipper._();

  /// 前缀缓存：blocks 身份不变时复用累积字符偏移，O(1) 命中。
  static List<ContentBlock>? _prefixBlocks;
  static List<int>? _prefixOffsets;

  /// 裁剪结果缓存：同一 blocks 身份 + 同一字符区间的裁剪结果复用，
  /// 使调用方（整页重建）拿到的列表身份稳定，下游 identical 判定生效。
  static final List<_ClipCacheEntry> _clipCache = <_ClipCacheEntry>[];
  static const _clipCacheLimit = 8;

  /// 块索引区间裁剪缓存（图片独占页路径），与字符路径互相独立。
  static final List<_ClipCacheEntry> _indexClipCache = <_ClipCacheEntry>[];

  /// 构建或复用 blocks 的累积字符前缀（blocks[i] 起始偏移，长度 = blocks.length + 1）。
  static List<int> _prefixFor(List<ContentBlock> blocks) {
    if (identical(_prefixBlocks, blocks) && _prefixOffsets != null) {
      return _prefixOffsets!;
    }
    final offsets = List<int>.filled(blocks.length + 1, 0);
    for (var i = 0; i < blocks.length; i++) {
      offsets[i + 1] = offsets[i] + blockCharCount(blocks[i]);
    }
    _prefixBlocks = blocks;
    _prefixOffsets = offsets;
    return offsets;
  }

  /// 在有序前缀中二分查找首个结束偏移 > target 的块索引。
  static int _lowerBound(List<int> offsets, int target) {
    var lo = 0;
    var hi = offsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (offsets[mid + 1] <= target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// 按块索引范围裁剪：保留 `[startIndex, endIndex)` 内的块。
  ///
  /// 供零字符块（图片独占页）使用：这类页面的真实字符区间为零宽，
  /// 无法用字符范围表达，只能按块区间取。
  /// 按页切片取本页要画的块，渲染侧与回归语料只能经由这里取数。
  ///
  /// 零宽窗口（图片独占页、链页）按块索引裁；其余按字符区间裁，再把**尾端**正好压在
  /// [PageSlice.endCharOffset] 上的零宽块补回来：区间裁剪按 `块起点 >= 区间尾` 停步，
  /// 而引擎已经把这些块装进本页并算过高度——不补就是收尾的分隔线静默不画。
  /// 起点侧的零宽图片块不补：那归 `_pageHeadBlockIndex` 的回退判据管，补了就画两遍。
  static List<ContentBlock> clipBlocksByPageRange(
    List<ContentBlock> blocks,
    PageSlice slice,
  ) {
    if (slice.endCharOffset <= slice.startCharOffset) {
      return clipBlocksByIndexRange(blocks, slice.startIndex, slice.endIndex);
    }
    final clipped = clipBlocksByCharRange(
      blocks,
      slice.startCharOffset,
      slice.endCharOffset,
    );
    final offsets = _prefixFor(blocks);
    final trailing = <ContentBlock>[];
    for (
      var i = slice.startIndex;
      i < slice.endIndex && i + 1 < offsets.length;
      i++
    ) {
      if (offsets[i] >= slice.endCharOffset && offsets[i] == offsets[i + 1]) {
        trailing.add(blocks[i]);
      }
    }
    if (trailing.isEmpty) return clipped;
    return <ContentBlock>[...clipped, ...trailing];
  }

  static List<ContentBlock> clipBlocksByIndexRange(
    List<ContentBlock> blocks,
    int startIndex,
    int endIndex,
  ) {
    final start = startIndex.clamp(0, blocks.length);
    final end = endIndex.clamp(start, blocks.length);
    if (start >= end) return [];
    // 与字符路径同等的身份稳定缓存：图片独占页每次整页重建时
    // visibleBlocks 不再产生新身份，didUpdateWidget 判定可短路。
    for (var i = 0; i < _indexClipCache.length; i++) {
      final entry = _indexClipCache[i];
      if (identical(entry.blocks, blocks) &&
          entry.start == start &&
          entry.end == end) {
        if (i != 0) {
          _indexClipCache.removeAt(i);
          _indexClipCache.insert(0, entry);
        }
        return entry.result;
      }
    }
    final result = blocks.sublist(start, end);
    _indexClipCache.insert(0, _ClipCacheEntry(blocks, start, end, result));
    while (_indexClipCache.length > _clipCacheLimit) {
      _indexClipCache.removeLast();
    }
    return result;
  }

  /// 按字符范围裁剪 blocks 列表。
  ///
  /// 只保留 [startCharOffset, endCharOffset) 范围内的内容。
  /// 对首尾块做 span 级字符裁剪，中间块原样保留。
  /// 使用前缀索引二分定位起始块，避免 O(块数) 线性扫描。
  static List<ContentBlock> clipBlocksByCharRange(
    List<ContentBlock> blocks,
    int startCharOffset,
    int endCharOffset,
  ) {
    if (blocks.isEmpty || startCharOffset >= endCharOffset) return [];

    for (var i = 0; i < _clipCache.length; i++) {
      final entry = _clipCache[i];
      if (identical(entry.blocks, blocks) &&
          entry.start == startCharOffset &&
          entry.end == endCharOffset) {
        if (i != 0) {
          _clipCache.removeAt(i);
          _clipCache.insert(0, entry);
        }
        return entry.result;
      }
    }

    final offsets = _prefixFor(blocks);
    // 二分定位第一个 blockEnd > startCharOffset 的块
    var firstIdx = _lowerBound(offsets, startCharOffset);
    // 零字符块（图片/分隔线）宽度为 0，二分会把起点正好落在其上的这类块跳过，
    // 导致图片页取不到图片本体；向前回退把它纳入。
    while (firstIdx > 0 && offsets[firstIdx] == startCharOffset) {
      firstIdx--;
    }
    if (firstIdx >= blocks.length) return [];

    final result = <ContentBlock>[];
    for (var i = firstIdx; i < blocks.length; i++) {
      final blockStart = offsets[i];
      final blockEnd = offsets[i + 1];

      if (blockStart >= endCharOffset) break;

      if (blockStart >= startCharOffset && blockEnd <= endCharOffset) {
        // 图片独占页经块区间路径渲染本体；非零宽正文页不得再把起点
        // 边界上的零宽图片块拖进来，否则同一图片双重渲染。
        if (blocks[i] is ImageBlock &&
            blockStart == blockEnd &&
            blockStart == startCharOffset) {
          continue;
        }
        result.add(blocks[i]);
        continue;
      }

      final clipStart = (startCharOffset - blockStart).clamp(
        0,
        blockEnd - blockStart,
      );
      final clipEnd = (endCharOffset - blockStart).clamp(
        0,
        blockEnd - blockStart,
      );
      final trimmed = trimBlockByCharRange(blocks[i], clipStart, clipEnd);
      if (trimmed != null) result.add(trimmed);
    }

    _clipCache.insert(
      0,
      _ClipCacheEntry(blocks, startCharOffset, endCharOffset, result),
    );
    while (_clipCache.length > _clipCacheLimit) {
      _clipCache.removeLast();
    }
    return result;
  }

  /// 按字符范围裁剪单个块内的 span。
  ///
  /// [localStart] / [localEnd] 是相对于该块起始的字符偏移。
  static ContentBlock? trimBlockByCharRange(
    ContentBlock block,
    int localStart,
    int localEnd,
  ) {
    switch (block) {
      case ParagraphBlock(
        :final lines,
        :final hasTrailingSpacing,
        :final style,
      ):
        final trimmed = trimTextBlockByCharRange(lines, localStart, localEnd);
        final blockChars = lines.fold<int>(
          0,
          (sum, line) => sum + line.sourceChars,
        );
        return trimmed != null
            ? ParagraphBlock(
              lines: trimmed,
              // 段尾间距只属于把最后一行放在本页的那一份：跨 N 页的长段落每页都
              // 保留这个信号时，同一处留白被计入 N 次，续接页底部凭空多出段距。
              hasTrailingSpacing: hasTrailingSpacing && localEnd >= blockChars,
              style: style,
            )
            : null;
      case BlockquoteBlock(
        :final lines,
        :final startOffset,
        :final style,
        :final hasTopPadding,
        :final hasBottomPadding,
      ):
        final trimmed = trimTextBlockByCharRange(lines, localStart, localEnd);
        final blockChars = lines.fold<int>(
          0,
          (sum, line) => sum + line.sourceChars,
        );
        return trimmed != null
            ? BlockquoteBlock(
              lines: trimmed,
              startOffset: startOffset,
              style: style,
              // 留白要按"运行位置 ∧ 窗口位置"取交集：整块被推到下一页时它不再带
              // 首段的顶部留白，留在本页的前半段也不再带尾段的底部留白。
              hasTopPadding: hasTopPadding && localStart == 0,
              hasBottomPadding: hasBottomPadding && localEnd >= blockChars,
            )
            : null;
      case ListBlock(:final items, :final isOrdered, :final startOffset):
        final trimmed = trimListBlockByCharRange(items, localStart, localEnd);
        return trimmed != null
            ? ListBlock(
              items: trimmed,
              isOrdered: isOrdered,
              startOffset: startOffset,
            )
            : null;
      case HeadingBlock():
      case ImageBlock():
      case DividerBlock():
        return localStart == 0 ? block : null;
      case TableBlock(:final rows, :final startOffset):
        // 表格可以按行跨页：整块放不下时页底会静默裁掉最后几行（真书语料里 walden
        // 的 696px 表格就是这样）。行是不可分的最小单位，切点只落在行边界上。
        return _trimTableByCharRange(rows, localStart, localEnd, startOffset);
    }
  }

  /// 按字符范围裁剪表格的行列表，切点只落在行边界。
  ///
  /// 行的字符数就是各单元格可绘制文本依次相接的长度（没有分隔符），所以行内裁剪
  /// 直接按单元格顺序换算。空单元格要保留，否则列数变了，表头底色也会跟着错位。
  static ContentBlock? _trimTableByCharRange(
    List<TableRowData> rows,
    int localStart,
    int localEnd,
    int startOffset,
  ) {
    var offset = 0;
    final kept = <TableRowData>[];
    for (final row in rows) {
      final rowChars = _rowCharCount(row);
      final rowEnd = offset + rowChars;
      if (rowEnd <= localStart || offset >= localEnd) {
        offset = rowEnd;
        continue;
      }
      final clipStart = math.max(0, localStart - offset);
      final clipEnd = math.min(rowChars, localEnd - offset);
      final cells = <List<ReaderInlineSpan>>[];
      var cellOffset = 0;
      for (final cell in row.cells) {
        final cellChars = cell.fold(0, (sum, span) => sum + span.text.length);
        if (cellChars == 0) {
          if (cellOffset >= clipStart && cellOffset <= clipEnd) {
            cells.add(cell);
          }
          continue;
        }
        final from = math.max(clipStart, cellOffset) - cellOffset;
        final to = math.min(clipEnd, cellOffset + cellChars) - cellOffset;
        if (to > from) {
          final trimmed = trimSpansByCharRange(cell, from, to);
          if (trimmed.isNotEmpty) {
            cells.add(trimmed);
          }
        }
        cellOffset += cellChars;
      }
      kept.add(TableRowData(cells: cells, isHeader: row.isHeader));
      offset = rowEnd;
    }
    if (kept.isEmpty) return null;
    return TableBlock(rows: kept, startOffset: startOffset);
  }

  static int _rowCharCount(TableRowData row) => row.cells.fold(
    0,
    (sum, cell) => sum + cell.fold(0, (s2, span) => s2 + span.text.length),
  );

  /// 按字符范围裁剪文本行列表。
  ///
  /// 入参与返回块的字符数都在**源文本空间**：行首折叠字符（缩进、被连排吞掉的
  /// 换行空白）没有可绘制文本，但必须计入长度，否则页与页之间会丢字或重字。
  /// 落在裁剪窗口内、却没有可绘制行来承载的折叠字符挂到前一个已输出行上：
  /// 它们不可见，只影响总数，而总数必须始终等于请求长度。
  static List<LineData>? trimTextBlockByCharRange(
    List<LineData> lines,
    int localStart,
    int localEnd,
  ) {
    var offset = 0;
    final result = <LineData>[];
    var orphanSource = 0;

    void attachOrphans() {
      if (orphanSource == 0 || result.isEmpty) {
        return;
      }
      final last = result.removeLast();
      result.add(
        LineData(
          spans: last.spans,
          isNewParagraph: last.isNewParagraph,
          collapsedChars: last.collapsedChars,
          // 孤儿折叠字符来自被丢掉的空白行，位置在这一行可绘制文本之后，
          // 记进行尾而不是行首，行首定位才不会跟着整体偏移。
          trailingCollapsedChars: last.trailingCollapsedChars + orphanSource,
          softWrap: last.softWrap,
          style: last.style,
        ),
      );
      orphanSource = 0;
    }

    for (final line in lines) {
      final lineLen = line.sourceChars;
      final lineEnd = offset + lineLen;

      if (lineEnd <= localStart || offset >= localEnd) {
        offset = lineEnd;
        continue;
      }

      if (offset >= localStart && lineEnd <= localEnd) {
        attachOrphans();
        result.add(line);
        offset = lineEnd;
        continue;
      }

      // 可绘制区间在源空间中整体后移 collapsedChars 个字符。
      final paintedStart = offset + line.collapsedChars;
      final paintedEnd = paintedStart + line.paintedChars;
      final clipStart =
          (localStart > paintedStart ? localStart : paintedStart) -
          paintedStart;
      final clipEnd =
          (localEnd < paintedEnd ? localEnd : paintedEnd) - paintedStart;
      final keptSource =
          (localEnd < lineEnd ? localEnd : lineEnd) -
          (localStart > offset ? localStart : offset);
      if (clipEnd > clipStart) {
        final trimmedSpans = trimSpansByCharRange(
          line.spans,
          clipStart,
          clipEnd,
        );
        var trimmedPainted = 0;
        for (final span in trimmedSpans) {
          trimmedPainted += span.text.length;
        }
        if (trimmedSpans.isNotEmpty) {
          attachOrphans();
          // 窗口内的折叠字符要继续计入，但必须按位置分成行首与行尾两份：
          // 行首那部分是 paintedStart 之前、窗口起点之后的字符。
          final keptLeading = math.max(
            0,
            paintedStart - (localStart > offset ? localStart : offset),
          );
          final keptTrailing = math.max(
            0,
            keptSource - trimmedPainted - keptLeading,
          );
          result.add(
            LineData(
              spans: trimmedSpans,
              isNewParagraph: line.isNewParagraph,
              collapsedChars: keptLeading,
              trailingCollapsedChars: keptTrailing,
              softWrap: line.softWrap,
              style: line.style,
            ),
          );
          offset = lineEnd;
          continue;
        }
      }
      orphanSource += keptSource;

      offset = lineEnd;
    }

    attachOrphans();

    return result.isEmpty ? null : result;
  }

  /// 按字符范围裁剪列表项。
  static List<ListItemData>? trimListBlockByCharRange(
    List<ListItemData> items,
    int localStart,
    int localEnd,
  ) {
    var offset = 0;
    final result = <ListItemData>[];

    for (final item in items) {
      final itemLen = item.spans.fold<int>(0, (s, sp) => s + sp.text.length);
      final itemEnd = offset + itemLen;

      if (itemEnd <= localStart || offset >= localEnd) {
        offset = itemEnd;
        continue;
      }

      if (offset >= localStart && itemEnd <= localEnd) {
        result.add(item);
        offset = itemEnd;
        continue;
      }

      final clipStart = (localStart - offset).clamp(0, itemLen);
      final clipEnd = (localEnd - offset).clamp(0, itemLen);
      final trimmedSpans = trimSpansByCharRange(item.spans, clipStart, clipEnd);
      if (trimmedSpans.isNotEmpty) {
        result.add(ListItemData(spans: trimmedSpans));
      }

      offset = itemEnd;
    }

    return result.isEmpty ? null : result;
  }

  /// 按字符范围裁剪 span 列表。
  static List<ReaderInlineSpan> trimSpansByCharRange(
    List<ReaderInlineSpan> spans,
    int start,
    int end,
  ) {
    var offset = 0;
    final result = <ReaderInlineSpan>[];

    for (final span in spans) {
      final spanEnd = offset + span.text.length;

      if (spanEnd <= start || offset >= end) {
        offset = spanEnd;
        continue;
      }

      if (offset >= start && spanEnd <= end) {
        result.add(span);
        offset = spanEnd;
        continue;
      }

      final clipStart = (start - offset).clamp(0, span.text.length);
      final clipEnd = (end - offset).clamp(0, span.text.length);
      final clippedText = span.text.substring(clipStart, clipEnd);
      if (clippedText.isNotEmpty) {
        result.add(
          ReaderInlineSpan(
            text: clippedText,
            isBold: span.isBold,
            isItalic: span.isItalic,
            isHeading: span.isHeading,
            href: span.href,
            isCode: span.isCode,
            startOffset: span.startOffset + clipStart,
            backgroundColor: span.backgroundColor,
            isSuperscript: span.isSuperscript,
            isSubscript: span.isSubscript,
            isMarked: span.isMarked,
            isDeleted: span.isDeleted,
            isUnderlined: span.isUnderlined,
          ),
        );
      }

      offset = spanEnd;
    }

    return result;
  }

  /// 计算块的总字符数。
  static int blockCharCount(ContentBlock block) {
    return switch (block) {
      HeadingBlock(:final text) => text.length,
      ParagraphBlock(:final lines) => lines.fold(
        0,
        (s, l) => s + l.sourceChars,
      ),
      ImageBlock() => 0,
      DividerBlock() => 0,
      BlockquoteBlock(:final lines) => lines.fold(
        0,
        (s, l) => s + l.sourceChars,
      ),
      ListBlock(:final items) => items.fold(
        0,
        (s, i) => s + i.spans.fold(0, (s2, sp) => s2 + sp.text.length),
      ),
      TableBlock(:final rows) => rows.fold(
        0,
        (s, r) =>
            s +
            r.cells.fold(
              0,
              (s2, c) => s2 + c.fold(0, (s3, sp) => s3 + sp.text.length),
            ),
      ),
    };
  }
}

/// 裁剪结果缓存条目：以 blocks 列表身份为键的一部分。
class _ClipCacheEntry {
  const _ClipCacheEntry(this.blocks, this.start, this.end, this.result);

  final List<ContentBlock> blocks;
  final int start;
  final int end;
  final List<ContentBlock> result;
}
