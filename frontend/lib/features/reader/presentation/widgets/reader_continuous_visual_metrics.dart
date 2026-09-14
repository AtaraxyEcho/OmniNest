import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';

/// 章体内容几何模型（方案 §10 ContentMetrics）。
///
/// 从窗口章条目构建：块组成、块级累积高度、逻辑字符前缀与就绪态。
/// 位置解析只依赖本模型与 [ReaderContinuousVisualMetrics]，
/// 不直接触碰控制器或数据加载层。
@immutable
class ReaderContentMetrics {
  const ReaderContentMetrics({
    required this.chapterId,
    required this.blockCount,
    required this.cumulativeHeights,
    required this.totalHeight,
    required this.totalChars,
    required this.isReady,
    this.blockCharPrefixes = const <int>[],
  });

  /// 从窗口章条目构建；条目本身不可变，此处仅持有引用不复制。
  factory ReaderContentMetrics.fromEntry(ContinuousChapterEntry entry) {
    return ReaderContentMetrics(
      chapterId: entry.chapterId,
      blockCount: entry.blockCount,
      cumulativeHeights: entry.cumulativeHeights,
      totalHeight: entry.totalHeight,
      totalChars: entry.totalChars,
      isReady: entry.isReady,
      blockCharPrefixes: entry.blockCharPrefixes,
    );
  }

  final String chapterId;
  final int blockCount;
  final List<double> cumulativeHeights;
  final double totalHeight;
  final int totalChars;
  final bool isReady;
  final List<int> blockCharPrefixes;

  /// 是否具备块级几何（块数与累积高度对齐且非空）。
  bool get hasBlockGeometry =>
      blockCount > 0 && cumulativeHeights.length == blockCount;

  /// 是否具备块级字符前缀（长度 = 块数 + 1）。
  bool get hasCharPrefixes =>
      isReady && blockCharPrefixes.length == blockCount + 1;

  /// 块 [index] 的起始 Y（章体局部）；几何缺失时为 0。
  double blockStartY(int index) =>
      hasBlockGeometry && index > 0 ? cumulativeHeights[index - 1] : 0.0;

  /// 块 [index] 的高度；几何缺失时返回章体总高（全章单块近似）。
  double blockHeight(int index) {
    if (!hasBlockGeometry) {
      return totalHeight;
    }
    if (index < 0 || index >= blockCount) {
      return 0;
    }
    return cumulativeHeights[index] - blockStartY(index);
  }

  /// 块区间按 [start, end) 归属的块索引：块顶属当前块，块底
  /// （cumulativeHeights[i]）归下一块；末块为 [start, end]。
  /// 几何缺失时返回 0。
  int blockIndexAt(double localY) {
    if (!hasBlockGeometry) {
      return 0;
    }
    var lo = 0;
    var hi = blockCount - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cumulativeHeights[mid] <= localY) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo >= blockCount ? blockCount - 1 : lo;
  }

  /// 块 [index] 的起始字符；前缀缺失时按全章线性比例折算。
  int charStartOfBlock(int index) {
    if (hasCharPrefixes && index >= 0 && index <= blockCount) {
      return blockCharPrefixes[index];
    }
    if (totalChars <= 0 || blockCount <= 0 || totalHeight <= 0) {
      return 0;
    }
    return (totalChars * (index / blockCount)).round().clamp(0, totalChars);
  }

  /// 块 [index] 的结束字符。
  int charEndOfBlock(int index) => charStartOfBlock(index + 1);

  /// 块 [index] 是否为逐字映射的文本块；blocks 不足时按非文本处理。
  bool isTextBlockAt(int index, List<ContentBlock> blocks) {
    if (index < 0 || index >= blocks.length) {
      return false;
    }
    final block = blocks[index];
    return block is ParagraphBlock ||
        block is BlockquoteBlock ||
        block is ListBlock ||
        block is HeadingBlock;
  }
}

/// 章体视觉空间模型（方案 §10 VisualMetrics）：视觉块区间、
/// 章体视觉范围与视觉游标。
///
/// 图片等零字符块在视觉空间占据真实高度而在逻辑空间字符数为 0；
/// 视觉位置独立于 charOffset 是双坐标模型的核心。
@immutable
class ReaderContinuousVisualMetrics {
  const ReaderContinuousVisualMetrics(this.metrics);

  final ReaderContentMetrics metrics;

  /// 块 [index] 的视觉区间 [start, end)（章体局部 Y）。
  /// 区间为空（零高块）时返回 (块顶, 块顶)。
  (double, double) visualRangeOfBlock(int index) {
    final start = metrics.blockStartY(index);
    final end = start + metrics.blockHeight(index);
    return (start, end);
  }

  /// 章体内局部 Y → 视觉位置三元组（块索引、块内偏移、块内比例）。
  (int, double, double) visualAt(double localY) {
    final blockIndex = metrics.blockIndexAt(localY);
    final blockStartY = metrics.blockStartY(blockIndex);
    final offsetInBlock = localY - blockStartY;
    final blockHeight = metrics.blockHeight(blockIndex);
    final ratio =
        blockHeight > 0 ? (offsetInBlock / blockHeight).clamp(0.0, 1.0) : 0.0;
    return (blockIndex, offsetInBlock, ratio);
  }

  /// 视觉游标：前面块高度 + 当前块内偏移（章体局部即 localY）。
  double cursorFor(int blockIndex, double offsetInBlock) {
    return metrics.blockStartY(blockIndex) + offsetInBlock;
  }

  /// 块内比例 → 逻辑 charOffset。
  ///
  /// 文本块按字符前缀线性投影；非文本块（图/分隔线/表格）块内前半落
  /// 块首字符、后半落块末字符——零字符块的首末字符相同，图片内部
  /// 移动时 charOffset 保持不变是正确行为。
  int charOffsetForBlock(
    int blockIndex,
    double blockRatio, {
    required List<ContentBlock> blocks,
  }) {
    final blockCharStart = metrics.charStartOfBlock(blockIndex);
    final blockCharEnd = metrics.charEndOfBlock(blockIndex);
    final blockChars = blockCharEnd - blockCharStart;
    if (blockChars <= 0) {
      return blockRatio >= 0.5 ? blockCharEnd : blockCharStart;
    }
    if (!metrics.isTextBlockAt(blockIndex, blocks)) {
      return blockRatio >= 0.5 ? blockCharEnd : blockCharStart;
    }
    return (blockCharStart + (blockRatio * blockChars).round()).clamp(
      blockCharStart,
      blockCharEnd,
    );
  }
}
