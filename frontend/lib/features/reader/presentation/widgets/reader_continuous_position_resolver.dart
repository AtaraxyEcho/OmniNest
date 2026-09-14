import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';

/// 视觉坐标：用户当前真正看到内容的视觉位置。
///
/// 图片等零字符块在视觉空间中占据真实高度而在逻辑空间中字符数为 0，
/// 因此视觉位置独立于 charOffset；重测高后按块内比例（[blockRatio]）
/// 重映射可保持所见内容不变。
@immutable
class VisualPosition {
  const VisualPosition({
    required this.chapterId,
    required this.blockIndex,
    required this.offsetInBlock,
    required this.blockRatio,
  });

  final String chapterId;
  final int blockIndex;

  /// 块内像素偏移（相对块顶）。
  final double offsetInBlock;

  /// 块内相对位置（offsetInBlock / blockHeight，0.0~1.0）。
  final double blockRatio;

  @override
  bool operator ==(Object other) =>
      other is VisualPosition &&
      other.chapterId == chapterId &&
      other.blockIndex == blockIndex &&
      other.offsetInBlock == offsetInBlock &&
      other.blockRatio == blockRatio;

  @override
  int get hashCode =>
      Object.hash(chapterId, blockIndex, offsetInBlock, blockRatio);

  @override
  String toString() =>
      'VisualPosition($chapterId#$blockIndex+${offsetInBlock.toStringAsFixed(1)}, '
      'ratio=${blockRatio.toStringAsFixed(3)})';
}

/// 逻辑坐标：用户在文本语义上读到哪里。
///
/// 持久化、模式切换、恢复与同步的核心状态；不承担图片内部像素位置。
@immutable
class LogicalPosition {
  const LogicalPosition({required this.chapterId, required this.charOffset});

  final String chapterId;
  final int charOffset;

  @override
  bool operator ==(Object other) =>
      other is LogicalPosition &&
      other.chapterId == chapterId &&
      other.charOffset == charOffset;

  @override
  int get hashCode => Object.hash(chapterId, charOffset);

  @override
  String toString() => 'LogicalPosition($chapterId, $charOffset)';
}

/// 一次解析的完整输出：双坐标 + 视觉游标一次到位。
@immutable
class ContinuousResolvedPosition {
  const ContinuousResolvedPosition({
    required this.chapterId,
    required this.visual,
    required this.logical,
    required this.chapterProgress,
    required this.chapterVisualProgress,
    required this.chapterVisualCursor,
    required this.chapterVisualExtent,
    required this.contentY,
  });

  final String chapterId;
  final VisualPosition visual;
  final LogicalPosition logical;

  /// 逻辑章节进度（charOffset / totalChars）。
  final double chapterProgress;

  /// 视觉章节进度（visualCursor / visualExtent），图片内部连续变化。
  final double chapterVisualProgress;

  /// 章体视觉游标：前面块视觉高度 + 当前块内偏移。
  final double chapterVisualCursor;

  /// 章体视觉总高度。
  final double chapterVisualExtent;

  /// 窗口内容坐标（含前缀章与章头 chrome）。
  final double contentY;
}

/// 连续阅读唯一位置解析器。
///
/// 纯函数服务：只读窗口几何（章条目、前缀高度、chrome 常量），
/// 不做 setState、jumpTo、进度保存、章节切换或网络请求。
/// 所有 contentY ↔ VisualPosition ↔ LogicalPosition 换算必须经此类。
class ReaderContinuousPositionResolver {
  const ReaderContinuousPositionResolver(this._controller);

  final ReaderContinuousScrollController _controller;

  /// 解析窗口 contentY 处的完整位置。
  ///
  /// 块区间按 [start, end) 归属（块底归下一块，末块 [start, end]）。
  /// 未就绪章（无块级高度）视觉锚点落在 blockIndex=0、比例按章体估算。
  ContinuousResolvedPosition? resolveContentY(double contentY) {
    final entries = _controller.entries;
    if (entries.isEmpty || _controller.anchorChapterId == null) {
      return null;
    }
    final y = contentY < 0 ? 0.0 : contentY;
    for (final entry in entries) {
      final start = _controller.prefixHeightOf(entry.chapterId);
      final end = start + _controller.effectiveExtentOf(entry);
      if (y < end || identical(entry, entries.last)) {
        // 章体位于章头之后：章头区域映射章首，章尾留白映射章尾。
        final localY = (y -
                start -
                ReaderContinuousScrollController.chapterHeaderExtent)
            .clamp(0.0, entry.totalHeight);
        final visual = _visualInEntry(entry, localY);
        final charOffset = _charOffsetInEntry(entry, localY, visual);
        final progress =
            entry.totalChars > 0
                ? (charOffset / entry.totalChars).clamp(0.0, 1.0)
                : 0.0;
        return ContinuousResolvedPosition(
          chapterId: entry.chapterId,
          visual: visual,
          logical: LogicalPosition(
            chapterId: entry.chapterId,
            charOffset: charOffset,
          ),
          chapterProgress: progress,
          chapterVisualProgress:
              entry.totalHeight > 0
                  ? (localY / entry.totalHeight).clamp(0.0, 1.0)
                  : 0.0,
          chapterVisualCursor: localY,
          chapterVisualExtent: entry.totalHeight,
          contentY: y,
        );
      }
    }
    return null;
  }

  /// 解析窗口 contentY 处的视觉位置（运行时锚点解析入口）。
  VisualPosition? visualAtContentY(double contentY) {
    final entries = _controller.entries;
    if (entries.isEmpty || _controller.anchorChapterId == null) {
      return null;
    }
    final y = contentY < 0 ? 0.0 : contentY;
    for (final entry in entries) {
      final start = _controller.prefixHeightOf(entry.chapterId);
      final end = start + _controller.effectiveExtentOf(entry);
      if (y < end || identical(entry, entries.last)) {
        final localY = (y -
                start -
                ReaderContinuousScrollController.chapterHeaderExtent)
            .clamp(0.0, entry.totalHeight);
        return _visualInEntry(entry, localY);
      }
    }
    return null;
  }

  /// 视觉位置对应的窗口 contentY；锚点章不在窗口或块级高度缺失时
  /// 返回 null，调用方应回退高度差补偿。
  double? contentYForVisualPosition(VisualPosition position) {
    final entry = _controller.entryFor(position.chapterId);
    if (entry == null) {
      return null;
    }
    final heights = entry.cumulativeHeights;
    if (entry.blockCount <= 0 ||
        heights.length != entry.blockCount ||
        position.blockIndex < 0 ||
        position.blockIndex >= entry.blockCount) {
      return null;
    }
    final blockStartY =
        position.blockIndex > 0 ? heights[position.blockIndex - 1] : 0.0;
    final blockHeight = heights[position.blockIndex] - blockStartY;
    final offset =
        blockHeight > 0 ? position.offsetInBlock.clamp(0.0, blockHeight) : 0.0;
    return _controller.prefixHeightOf(position.chapterId) +
        ReaderContinuousScrollController.chapterHeaderExtent +
        blockStartY +
        offset;
  }

  /// 视觉位置 → 逻辑位置：块内按字符前缀比例投影。
  ///
  /// 非文本块（图/分隔线/表格）字符数为 0 或不逐字映射：块内前半落块首
  /// 字符、后半落块末字符；图片内部移动时 charOffset 保持不变是正确行为。
  LogicalPosition? logicalFromVisual(VisualPosition position) {
    final entry = _controller.entryFor(position.chapterId);
    if (entry == null) {
      return null;
    }
    return LogicalPosition(
      chapterId: entry.chapterId,
      charOffset: _charOffsetForBlock(
        entry,
        position.blockIndex,
        position.blockRatio,
      ),
    );
  }

  /// 逻辑位置 → 视觉位置。
  ///
  /// charOffset 落在零字符块（图片）边界时映射到该块顶部，
  /// 避免恢复时直接跳到下一段正文把整图甩出视口。
  VisualPosition? visualFromLogical(String chapterId, int charOffset) {
    final entry = _controller.entryFor(chapterId);
    if (entry == null) {
      return null;
    }
    final heights = entry.cumulativeHeights;
    final prefixes = entry.blockCharPrefixes;
    if (entry.blockCount <= 0 ||
        heights.length != entry.blockCount ||
        prefixes.length != entry.blockCount + 1) {
      return null;
    }
    if (charOffset <= 0) {
      return VisualPosition(
        chapterId: chapterId,
        blockIndex: 0,
        offsetInBlock: 0,
        blockRatio: 0,
      );
    }
    var blockIndex = 0;
    while (blockIndex < entry.blockCount - 1 &&
        prefixes[blockIndex + 1] <= charOffset) {
      blockIndex++;
    }
    // 图片起点偏好：charOffset 恰为图片块累积起点时映射图片顶部，
    // 与 charOffsetToPixelOffset 的恢复规则一致，避免恢复时整图被甩出视口。
    for (var b = blockIndex - 1; b >= 0 && b < entry.blocks.length; b--) {
      final isImageBlockAtOffset =
          entry.blocks[b] is ImageBlock &&
          prefixes[b] == charOffset &&
          prefixes[b + 1] == charOffset;
      if (!isImageBlockAtOffset) {
        break;
      }
      blockIndex = b;
    }
    final blockCharStart = prefixes[blockIndex];
    final blockCharEnd = prefixes[blockIndex + 1];
    final blockChars = blockCharEnd - blockCharStart;
    final ratio =
        blockChars > 0
            ? ((charOffset - blockCharStart) / blockChars).clamp(0.0, 1.0)
            : 0.0;
    final blockStartY = blockIndex > 0 ? heights[blockIndex - 1] : 0.0;
    final blockHeight = heights[blockIndex] - blockStartY;
    return VisualPosition(
      chapterId: chapterId,
      blockIndex: blockIndex,
      offsetInBlock: ratio * blockHeight,
      blockRatio: blockHeight > 0 ? ratio : 0.0,
    );
  }

  /// 逻辑位置对应的窗口 contentY。
  double? contentYForLogicalPosition(String chapterId, int charOffset) {
    final visual = visualFromLogical(chapterId, charOffset);
    if (visual == null) {
      return null;
    }
    return contentYForVisualPosition(visual);
  }

  /// 章体视觉游标 → 逻辑 charOffset（仅限该章在窗口内）。
  ///
  /// seek 换算用：游标落在文本块时按块内比例投影，语义与
  /// resolveContentY 的正向映射互逆。
  int? charOffsetForVisualCursor(String chapterId, double visualCursor) {
    final entry = _controller.entryFor(chapterId);
    if (entry == null || entry.totalChars <= 0 || entry.totalHeight <= 0) {
      return null;
    }
    final localY = visualCursor.clamp(0.0, entry.totalHeight);
    final visual = _visualInEntry(entry, localY);
    return _charOffsetInEntry(entry, localY, visual);
  }

  /// 块重测高后重映射视觉位置：块高变化时按块内比例保持相对位置。
  ///
  /// 例如用户位于图片中部（旧高 600、偏移 300），重测得新高 800 后
  /// 偏移变为 400，不回跳块顶。
  VisualPosition? remapVisualPosition(
    VisualPosition position, {
    ContinuousChapterEntry? oldEntry,
  }) {
    final newEntry = _controller.entryFor(position.chapterId);
    if (newEntry == null) {
      return null;
    }
    final oldHeights = oldEntry?.cumulativeHeights;
    final newHeights = newEntry.cumulativeHeights;
    final hasOld =
        oldEntry != null &&
        oldHeights != null &&
        oldEntry.blockCount > 0 &&
        oldHeights.length == oldEntry.blockCount &&
        position.blockIndex >= 0 &&
        position.blockIndex < oldEntry.blockCount;
    final hasNew =
        newEntry.blockCount > 0 &&
        newHeights.length == newEntry.blockCount &&
        position.blockIndex >= 0 &&
        position.blockIndex < newEntry.blockCount;
    if (!hasOld || !hasNew) {
      return position;
    }
    final oldStart =
        position.blockIndex > 0 ? oldHeights[position.blockIndex - 1] : 0.0;
    final oldBlockHeight = oldHeights[position.blockIndex] - oldStart;
    final newStart =
        position.blockIndex > 0 ? newHeights[position.blockIndex - 1] : 0.0;
    final newBlockHeight = newHeights[position.blockIndex] - newStart;
    if (oldBlockHeight <= 0 || newBlockHeight <= 0) {
      return VisualPosition(
        chapterId: position.chapterId,
        blockIndex: position.blockIndex,
        offsetInBlock: 0,
        blockRatio: 0,
      );
    }
    final ratio = position.offsetInBlock / oldBlockHeight;
    return VisualPosition(
      chapterId: position.chapterId,
      blockIndex: position.blockIndex,
      offsetInBlock: ratio * newBlockHeight,
      blockRatio: ratio.clamp(0.0, 1.0),
    );
  }

  // ── 章内几何 ──

  /// 章体内局部 Y → 视觉位置。
  VisualPosition _visualInEntry(ContinuousChapterEntry entry, double localY) {
    final blockIndex = _blockIndexAt(entry, localY);
    final heights = entry.cumulativeHeights;
    final hasHeights =
        entry.blockCount > 0 && heights.length == entry.blockCount;
    final blockStartY =
        hasHeights && blockIndex > 0 ? heights[blockIndex - 1] : 0.0;
    final blockHeight =
        hasHeights ? heights[blockIndex] - blockStartY : entry.totalHeight;
    final offsetInBlock = localY - blockStartY;
    return VisualPosition(
      chapterId: entry.chapterId,
      blockIndex: blockIndex,
      offsetInBlock: offsetInBlock,
      blockRatio:
          blockHeight > 0 ? (offsetInBlock / blockHeight).clamp(0.0, 1.0) : 0.0,
    );
  }

  /// 块区间按 [start, end) 归属：块顶属当前块，块底（cumulativeHeights[i]）
  /// 归下一块，避免边界 Y 随机归属。块级高度缺失时返回 0。
  int _blockIndexAt(ContinuousChapterEntry entry, double localY) {
    final heights = entry.cumulativeHeights;
    if (entry.blockCount <= 0 || heights.length != entry.blockCount) {
      return 0;
    }
    var lo = 0;
    var hi = entry.blockCount - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (heights[mid] <= localY) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo >= entry.blockCount ? entry.blockCount - 1 : lo;
  }

  /// 章体内局部 Y → 逻辑 charOffset。
  ///
  /// 就绪章按「块索引 + 块级字符前缀」映射，文本块按块内比例插值；
  /// 未就绪章退回全章线性估算。
  int _charOffsetInEntry(
    ContinuousChapterEntry entry,
    double localY,
    VisualPosition visual,
  ) {
    if (entry.totalChars <= 0) {
      return 0;
    }
    final prefixes = entry.blockCharPrefixes;
    final hasPrefixes =
        entry.isReady &&
        prefixes.length == entry.blockCount + 1 &&
        entry.cumulativeHeights.length == entry.blockCount &&
        entry.blockCount > 0;
    if (!hasPrefixes) {
      final ratio = entry.totalHeight > 0 ? (localY / entry.totalHeight) : 0.0;
      return (ratio * entry.totalChars).round().clamp(0, entry.totalChars);
    }
    return _charOffsetForBlock(entry, visual.blockIndex, visual.blockRatio);
  }

  /// 块索引 + 块内比例 → 逻辑 charOffset。
  int _charOffsetForBlock(
    ContinuousChapterEntry entry,
    int blockIndex,
    double blockRatio,
  ) {
    final prefixes = entry.blockCharPrefixes;
    if (blockIndex < 0 || blockIndex >= entry.blockCount) {
      return entry.totalChars;
    }
    final blockCharStart = prefixes[blockIndex];
    final blockCharEnd = prefixes[blockIndex + 1];
    final blockChars = blockCharEnd - blockCharStart;
    if (blockChars <= 0) {
      // 非文本块（图/分隔线等）：块内前半落块首字符，后半落块末字符。
      return blockRatio >= 0.5 ? blockCharEnd : blockCharStart;
    }
    final isTextBlock =
        blockIndex >= entry.blocks.length ||
        entry.blocks[blockIndex] is ParagraphBlock ||
        entry.blocks[blockIndex] is BlockquoteBlock ||
        entry.blocks[blockIndex] is ListBlock ||
        entry.blocks[blockIndex] is HeadingBlock;
    if (!isTextBlock) {
      return blockRatio >= 0.5 ? blockCharEnd : blockCharStart;
    }
    return (blockCharStart + (blockRatio * blockChars).round()).clamp(
      blockCharStart,
      blockCharEnd,
    );
  }
}
