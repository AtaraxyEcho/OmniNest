import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_visual_metrics.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

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
    required this.visualBlockStart,
    required this.visualBlockEnd,
    required this.contentY,
    required this.geometryRevision,
  });

  final String chapterId;
  final VisualPosition visual;
  final LogicalPosition logical;

  /// 本次解析使用的几何版本号（诊断 ACTIVE 与 LIVE 是否同源）。
  final int geometryRevision;

  /// 逻辑章节进度（charOffset / totalChars）。
  final double chapterProgress;

  /// 视觉章节进度（visualCursor / visualExtent），图片内部连续变化。
  final double chapterVisualProgress;

  /// 章体视觉游标：前面块视觉高度 + 当前块内偏移。
  final double chapterVisualCursor;

  /// 章体视觉总高度。
  final double chapterVisualExtent;

  /// 当前块视觉区间起点（章体局部）。
  final double visualBlockStart;

  /// 当前块视觉区间终点（章体局部）。
  final double visualBlockEnd;

  /// 窗口内容坐标（含前缀章与章头 chrome）。
  final double contentY;
}

/// 运行时重排双锚点：布局变化前冻结的视觉 + 逻辑位置对。
///
/// [visual] 用于变化后在同一视觉位置（图片内部按块内比例）恢复；
/// [logical] 用于一致性确认与视觉锚点不可解析时的状态回退。
/// [oldEntry] 冻结变化前的章体几何，供块内比例重映射使用。
@immutable
class RuntimeAnchor {
  const RuntimeAnchor({
    required this.visual,
    required this.logical,
    this.oldEntry,
  });

  final VisualAnchor visual;
  final LogicalPosition logical;
  final ContinuousChapterEntry? oldEntry;
}

/// 连续阅读唯一位置解析器。
///
/// 纯函数服务：只读窗口几何（章条目、前缀高度、chrome 常量），
/// 不做 setState、jumpTo、进度保存、章节切换或网络请求。
/// 所有 contentY ↔ VisualPosition ↔ LogicalPosition 换算必须经此类。
class ReaderContinuousPositionResolver {
  ReaderContinuousPositionResolver(this._controller);

  final ReaderContinuousScrollController _controller;

  late final _LiveResolverGeometry _liveGeometry = _LiveResolverGeometry(
    _controller,
  );
  _SnapshotResolverGeometry? _lastSnapshotGeometry;

  _ResolverGeometry _geometryFor(ReaderScrollGeometrySource source) {
    if (source is SnapshotScrollGeometrySource) {
      final existing = _lastSnapshotGeometry;
      if (existing != null && identical(existing.snapshot, source.snapshot)) {
        return existing;
      }
      final view = _SnapshotResolverGeometry(source.snapshot);
      _lastSnapshotGeometry = view;
      return view;
    }
    return _liveGeometry;
  }

  /// 章体局部 contentY → charOffset（持久化精度路径）。
  ///
  /// 文本块用 TextPainter 视觉行测量精确计算（与 charOffsetToPixelOffset
  /// 互逆），非文本块或视觉行为空时线性插值；块区间按 [start, end)
  /// 归属。ReaderContentLoader.contentYToCharOffset 是本方法的对外包装。
  static int chapterLocalCharOffset({
    required List<ContentBlock> blocks,
    required List<double> cumulativeHeights,
    required int totalChars,
    required double contentY,
    required double pageWidth,
    ReaderViewSettings? settings,
    double textScale = 1.0,
    required int Function(ContentBlock block) blockCharCount,
  }) {
    if (blocks.isEmpty || cumulativeHeights.isEmpty) return 0;
    final totalHeight = cumulativeHeights.last;
    if (totalHeight <= 0) return 0;

    final normalizedOffset = contentY.clamp(0.0, totalHeight);

    // 二分查找 normalizedOffset 落在哪个 block 的累积高度区间内，
    // 块区间按 [start, end) 归属（块底归下一块），与窗口级映射一致。
    var lo = 0;
    var hi = cumulativeHeights.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (cumulativeHeights[mid] <= normalizedOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    // lo 是 normalizedOffset 落入的 block 索引，累加前 lo 个 block 的字符数。
    var charOffset = 0;
    for (var i = 0; i < lo; i++) {
      charOffset += blockCharCount(blocks[i]);
    }

    // 在 block 内：用 TextPainter 视觉行测量精确计算。
    final blockHeight =
        lo < cumulativeHeights.length
            ? cumulativeHeights[lo] - (lo > 0 ? cumulativeHeights[lo - 1] : 0.0)
            : 0.0;
    if (blockHeight > 0 && settings != null) {
      final blockStart = lo > 0 ? cumulativeHeights[lo - 1] : 0.0;
      final offsetInBlock = normalizedOffset - blockStart;
      final block = blocks[lo];
      final blockChars = blockCharCount(block);

      if (blockChars > 0 &&
          block is! ImageBlock &&
          block is! DividerBlock &&
          block is! TableBlock &&
          block is! HeadingBlock) {
        // 文本块：用视觉行测量精确查找 charOffset。
        final visualLines = ReaderPaginationEngine.measureVisualLines(
          block,
          pageWidth,
          settings,
          textScale,
          blockGlobalOffset: charOffset,
        );
        if (visualLines.isNotEmpty) {
          var accumulated = 0.0;
          for (var vi = 0; vi < visualLines.length; vi++) {
            final vl = visualLines[vi];
            if (offsetInBlock <= accumulated + vl.height) {
              // 目标在当前视觉行内。
              final vlLocalStart = vl.globalStart - charOffset;
              final vlLocalEnd = vl.globalEnd - charOffset;
              final lineChars = vlLocalEnd - vlLocalStart;
              if (lineChars > 0 && vl.height > 0) {
                final ratioInLine = ((offsetInBlock - accumulated) / vl.height)
                    .clamp(0.0, 1.0);
                charOffset += vlLocalStart + (ratioInLine * lineChars).round();
              } else {
                charOffset += vlLocalStart;
              }
              return charOffset.clamp(0, totalChars);
            }
            accumulated += vl.height;
          }
          // 超出所有视觉行，返回块末尾。
          charOffset += blockChars;
          return charOffset.clamp(0, totalChars);
        }
      }

      // 非文本块或视觉行为空：线性插值。
      if (blockChars > 0) {
        final progressInBlock = (offsetInBlock / blockHeight).clamp(0.0, 1.0);
        charOffset += (progressInBlock * blockChars).round();
      }
    }

    return charOffset.clamp(0, totalChars);
  }

  /// 解析窗口 contentY 处的完整位置。
  ///
  /// 块区间按 [start, end) 归属（块底归下一块，末块 [start, end]）。
  /// 未就绪章（无块级高度）视觉锚点落在 blockIndex=0、比例按章体估算。
  ContinuousResolvedPosition? resolveContentY(
    double contentY, {
    ReaderScrollGeometrySource source = const LiveScrollGeometrySource(),
  }) {
    final geometry = _geometryFor(source);
    final entries = geometry.entries;
    if (entries.isEmpty || !geometry.resolvable) {
      return null;
    }
    final y = contentY < 0 ? 0.0 : contentY;
    for (final entry in entries) {
      final start = geometry.prefixOf(entry.chapterId);
      final end = start + geometry.extentOf(entry);
      if (y < end || identical(entry, entries.last)) {
        // 章体位于章头之后：章头区域映射章首，章尾留白映射章尾。
        final localY = (y -
                start -
                ReaderContinuousScrollController.chapterHeaderExtent)
            .clamp(0.0, entry.totalHeight);
        final visualMetrics = ReaderContinuousVisualMetrics(
          ReaderContentMetrics.fromEntry(entry),
        );
        final (blockIndex, offsetInBlock, blockRatio) = visualMetrics.visualAt(
          localY,
        );
        final visual = VisualPosition(
          chapterId: entry.chapterId,
          blockIndex: blockIndex,
          offsetInBlock: offsetInBlock,
          blockRatio: blockRatio,
        );
        final charOffset = visualMetrics.charOffsetForBlock(
          blockIndex,
          blockRatio,
          blocks: entry.blocks,
        );
        final progress =
            entry.totalChars > 0
                ? (charOffset / entry.totalChars).clamp(0.0, 1.0)
                : 0.0;
        final (visualBlockStart, visualBlockEnd) = visualMetrics
            .visualRangeOfBlock(blockIndex);
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
          visualBlockStart: visualBlockStart,
          visualBlockEnd: visualBlockEnd,
          contentY: y,
          geometryRevision: geometry.revision,
        );
      }
    }
    return null;
  }

  /// 解析窗口 contentY 处的视觉位置（运行时锚点解析入口）。
  VisualPosition? visualAtContentY(
    double contentY, {
    ReaderScrollGeometrySource source = const LiveScrollGeometrySource(),
  }) {
    final geometry = _geometryFor(source);
    final entries = geometry.entries;
    if (entries.isEmpty || !geometry.resolvable) {
      return null;
    }
    final y = contentY < 0 ? 0.0 : contentY;
    for (final entry in entries) {
      final start = geometry.prefixOf(entry.chapterId);
      final end = start + geometry.extentOf(entry);
      if (y < end || identical(entry, entries.last)) {
        final localY = (y -
                start -
                ReaderContinuousScrollController.chapterHeaderExtent)
            .clamp(0.0, entry.totalHeight);
        final (
          blockIndex,
          offsetInBlock,
          blockRatio,
        ) = ReaderContinuousVisualMetrics(
          ReaderContentMetrics.fromEntry(entry),
        ).visualAt(localY);
        return VisualPosition(
          chapterId: entry.chapterId,
          blockIndex: blockIndex,
          offsetInBlock: offsetInBlock,
          blockRatio: blockRatio,
        );
      }
    }
    return null;
  }

  /// 视觉位置对应的窗口 contentY；锚点章不在窗口或块级高度缺失时
  /// 返回 null，调用方应回退高度差补偿。
  double? contentYForVisualPosition(
    VisualPosition position, {
    ReaderScrollGeometrySource source = const LiveScrollGeometrySource(),
  }) {
    final geometry = _geometryFor(source);
    final entry = geometry.entryFor(position.chapterId);
    if (entry == null) {
      return null;
    }
    final metrics = ReaderContentMetrics.fromEntry(entry);
    if (!metrics.hasBlockGeometry ||
        position.blockIndex < 0 ||
        position.blockIndex >= metrics.blockCount) {
      return null;
    }
    final blockStartY = metrics.blockStartY(position.blockIndex);
    final blockHeight = metrics.blockHeight(position.blockIndex);
    final offset =
        blockHeight > 0 ? position.offsetInBlock.clamp(0.0, blockHeight) : 0.0;
    return geometry.prefixOf(position.chapterId) +
        ReaderContinuousScrollController.chapterHeaderExtent +
        blockStartY +
        offset;
  }

  /// 视觉位置 → 逻辑位置：块内按字符前缀比例投影。
  ///
  /// 非文本块（图/分隔线/表格）字符数为 0 或不逐字映射：块内前半落块首
  /// 字符、后半落块末字符；图片内部移动时 charOffset 保持不变是正确行为。
  LogicalPosition? logicalFromVisual(
    VisualPosition position, {
    ReaderScrollGeometrySource source = const LiveScrollGeometrySource(),
  }) {
    final geometry = _geometryFor(source);
    final entry = geometry.entryFor(position.chapterId);
    if (entry == null) {
      return null;
    }
    final visualMetrics = ReaderContinuousVisualMetrics(
      ReaderContentMetrics.fromEntry(entry),
    );
    return LogicalPosition(
      chapterId: entry.chapterId,
      charOffset: visualMetrics.charOffsetForBlock(
        position.blockIndex,
        position.blockRatio,
        blocks: entry.blocks,
      ),
    );
  }

  /// 逻辑位置 → 视觉位置。
  ///
  /// charOffset 落在零字符块（图片）边界时映射到该块顶部，
  /// 避免恢复时直接跳到下一段正文把整图甩出视口。
  VisualPosition? visualFromLogical(
    String chapterId,
    int charOffset, {
    ReaderScrollGeometrySource source = const LiveScrollGeometrySource(),
  }) {
    final geometry = _geometryFor(source);
    final entry = geometry.entryFor(chapterId);
    if (entry == null) {
      return null;
    }
    final metrics = ReaderContentMetrics.fromEntry(entry);
    final prefixes = entry.blockCharPrefixes;
    if (!metrics.hasBlockGeometry || !metrics.hasCharPrefixes) {
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
    while (blockIndex < metrics.blockCount - 1 &&
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
    final blockCharStart = metrics.charStartOfBlock(blockIndex);
    final blockCharEnd = metrics.charEndOfBlock(blockIndex);
    final blockChars = blockCharEnd - blockCharStart;
    final ratio =
        blockChars > 0
            ? ((charOffset - blockCharStart) / blockChars).clamp(0.0, 1.0)
            : 0.0;
    final blockHeight = metrics.blockHeight(blockIndex);
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
  int? charOffsetForVisualCursor(
    String chapterId,
    double visualCursor, {
    ReaderScrollGeometrySource source = const LiveScrollGeometrySource(),
  }) {
    final geometry = _geometryFor(source);
    final entry = geometry.entryFor(chapterId);
    if (entry == null || entry.totalChars <= 0 || entry.totalHeight <= 0) {
      return null;
    }
    final metrics = ReaderContentMetrics.fromEntry(entry);
    final visualMetrics = ReaderContinuousVisualMetrics(metrics);
    final localY = visualCursor.clamp(0.0, entry.totalHeight);
    final (blockIndex, _, blockRatio) = visualMetrics.visualAt(localY);
    if (!metrics.hasCharPrefixes) {
      // 未就绪章退回全章线性估算。
      final ratio = entry.totalHeight > 0 ? (localY / entry.totalHeight) : 0.0;
      return (ratio * entry.totalChars).round().clamp(0, entry.totalChars);
    }
    return visualMetrics.charOffsetForBlock(
      blockIndex,
      blockRatio,
      blocks: entry.blocks,
    );
  }

  /// 块重测高后重映射视觉位置：块高变化时按块内比例保持相对位置。
  ///
  /// 例如用户位于图片中部（旧高 600、偏移 300），重测得新高 800 后
  /// 偏移变为 400，不回跳块顶。
  VisualPosition? remapVisualPosition(
    VisualPosition position, {
    ContinuousChapterEntry? oldEntry,
    ReaderScrollGeometrySource source = const LiveScrollGeometrySource(),
  }) {
    final geometry = _geometryFor(source);
    final newEntry = geometry.entryFor(position.chapterId);
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
}

/// 解析器内部几何视图：统一 Live 与 Snapshot 两种来源的读取口径
/// （方案 §6-8）。Resolver 本身仍是纯函数，几何由外部决定。
abstract interface class _ResolverGeometry {
  List<ContinuousChapterEntry> get entries;

  double prefixOf(String chapterId);

  ContinuousChapterEntry? entryFor(String chapterId);

  double extentOf(ContinuousChapterEntry entry);

  /// 窗口是否可解析（Live 需锚点存在；Snapshot 构建时已含锚点）。
  bool get resolvable;

  int get revision;
}

class _LiveResolverGeometry implements _ResolverGeometry {
  const _LiveResolverGeometry(this.controller);

  final ReaderContinuousScrollController controller;

  @override
  List<ContinuousChapterEntry> get entries => controller.entries;

  @override
  double prefixOf(String chapterId) => controller.prefixHeightOf(chapterId);

  @override
  ContinuousChapterEntry? entryFor(String chapterId) =>
      controller.entryFor(chapterId);

  @override
  double extentOf(ContinuousChapterEntry entry) =>
      controller.effectiveExtentOf(entry);

  @override
  bool get resolvable =>
      controller.entries.isNotEmpty && controller.anchorChapterId != null;

  @override
  int get revision => controller.geometryRevision;
}

class _SnapshotResolverGeometry implements _ResolverGeometry {
  _SnapshotResolverGeometry(this.snapshot);

  final ReaderScrollGeometrySnapshot snapshot;

  late final List<ContinuousChapterEntry> _synthesizedEntries = [
    for (final id in snapshot.chapterIds) snapshot.chapterOf(id)!.toEntry(),
  ];

  @override
  List<ContinuousChapterEntry> get entries => _synthesizedEntries;

  @override
  double prefixOf(String chapterId) => snapshot.prefixOf(chapterId);

  @override
  ContinuousChapterEntry? entryFor(String chapterId) =>
      snapshot.chapterOf(chapterId)?.toEntry();

  @override
  double extentOf(ContinuousChapterEntry entry) =>
      ReaderContinuousScrollController.chapterHeaderExtent +
      entry.totalHeight +
      (entry.isReady
          ? ReaderContinuousScrollController.chapterTrailingExtent
          : ReaderContinuousScrollController.chapterTrailingLoadingExtent);

  @override
  bool get resolvable => snapshot.chapterIds.isNotEmpty;

  @override
  int get revision => snapshot.revision;
}
