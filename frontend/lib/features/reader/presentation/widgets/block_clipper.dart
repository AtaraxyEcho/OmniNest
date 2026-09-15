import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';

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
  static List<ContentBlock> clipBlocksByIndexRange(
    List<ContentBlock> blocks,
    int startIndex,
    int endIndex,
  ) {
    final start = startIndex.clamp(0, blocks.length);
    final end = endIndex.clamp(start, blocks.length);
    if (start >= end) return [];
    return blocks.sublist(start, end);
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
      case ParagraphBlock(:final lines, :final hasTrailingSpacing):
        final trimmed = trimTextBlockByCharRange(lines, localStart, localEnd);
        return trimmed != null
            ? ParagraphBlock(
              lines: trimmed,
              hasTrailingSpacing: hasTrailingSpacing,
            )
            : null;
      case BlockquoteBlock(:final lines, :final startOffset):
        final trimmed = trimTextBlockByCharRange(lines, localStart, localEnd);
        return trimmed != null
            ? BlockquoteBlock(lines: trimmed, startOffset: startOffset)
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
      case TableBlock():
        return localStart == 0 ? block : null;
    }
  }

  /// 按字符范围裁剪文本行列表。
  static List<LineData>? trimTextBlockByCharRange(
    List<LineData> lines,
    int localStart,
    int localEnd,
  ) {
    var offset = 0;
    final result = <LineData>[];

    for (final line in lines) {
      final lineLen = line.spans.fold<int>(0, (s, sp) => s + sp.text.length);
      final lineEnd = offset + lineLen;

      if (lineEnd <= localStart || offset >= localEnd) {
        offset = lineEnd;
        continue;
      }

      if (offset >= localStart && lineEnd <= localEnd) {
        result.add(line);
        offset = lineEnd;
        continue;
      }

      final clipStart = (localStart - offset).clamp(0, lineLen);
      final clipEnd = (localEnd - offset).clamp(0, lineLen);
      final trimmedSpans = trimSpansByCharRange(line.spans, clipStart, clipEnd);
      if (trimmedSpans.isNotEmpty) {
        result.add(
          LineData(spans: trimmedSpans, isNewParagraph: line.isNewParagraph),
        );
      }

      offset = lineEnd;
    }

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
        (s, l) => s + l.spans.fold(0, (s2, sp) => s2 + sp.text.length),
      ),
      ImageBlock() => 0,
      DividerBlock() => 0,
      BlockquoteBlock(:final lines) => lines.fold(
        0,
        (s, l) => s + l.spans.fold(0, (s2, sp) => s2 + sp.text.length),
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
