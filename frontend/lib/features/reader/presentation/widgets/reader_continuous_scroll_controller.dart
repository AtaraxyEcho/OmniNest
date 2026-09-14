import 'package:flutter/foundation.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_position_resolver.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// 连续滚动窗口内的一章。
@immutable
class ContinuousChapterEntry {
  const ContinuousChapterEntry({
    required this.chapterId,
    required this.title,
    required this.blockCount,
    required this.cumulativeHeights,
    required this.totalHeight,
    required this.totalChars,
    required this.isReady,
    this.blocks = const <ContentBlock>[],
    this.blockCharPrefixes = const <int>[],
  });

  final String chapterId;
  final String title;
  final int blockCount;

  /// 与 blockCount 对齐的累积高度；未就绪时为空。
  final List<double> cumulativeHeights;
  final double totalHeight;
  final int totalChars;
  final bool isReady;
  final List<ContentBlock> blocks;

  /// 块级字符前缀：prefixes[i] = 前 i 个 block 字符数；末项为 totalChars。
  final List<int> blockCharPrefixes;

  ContinuousChapterEntry copyWith({
    String? title,
    int? blockCount,
    List<double>? cumulativeHeights,
    double? totalHeight,
    int? totalChars,
    bool? isReady,
    List<ContentBlock>? blocks,
    List<int>? blockCharPrefixes,
  }) {
    return ContinuousChapterEntry(
      chapterId: chapterId,
      title: title ?? this.title,
      blockCount: blockCount ?? this.blockCount,
      cumulativeHeights: cumulativeHeights ?? this.cumulativeHeights,
      totalHeight: totalHeight ?? this.totalHeight,
      totalChars: totalChars ?? this.totalChars,
      isReady: isReady ?? this.isReady,
      blocks: blocks ?? this.blocks,
      blockCharPrefixes: blockCharPrefixes ?? this.blockCharPrefixes,
    );
  }
}

/// 窗口内虚拟列表项：章节头 / 正文块 / 章末间隔。
@immutable
class ContinuousScrollItem {
  const ContinuousScrollItem.chapterHeader({
    required this.chapterId,
    required this.title,
  }) : blockIndex = -1,
       kind = ContinuousScrollItemKind.chapterHeader;

  const ContinuousScrollItem.block({
    required this.chapterId,
    required this.blockIndex,
  }) : title = null,
       kind = ContinuousScrollItemKind.block;

  const ContinuousScrollItem.chapterTrailing({required this.chapterId})
    : blockIndex = -1,
      title = null,
      kind = ContinuousScrollItemKind.chapterTrailing;

  final ContinuousScrollItemKind kind;
  final String chapterId;
  final int blockIndex;
  final String? title;
}

enum ContinuousScrollItemKind { chapterHeader, block, chapterTrailing }

/// 连续滚动阅读位置：同时携带视觉坐标与逻辑坐标（双坐标模型）。
@immutable
class ContinuousScrollPosition {
  const ContinuousScrollPosition({
    required this.chapterId,
    required this.charOffset,
    required this.chapterProgress,
    required this.contentY,
    required this.visual,
    required this.chapterVisualProgress,
    required this.chapterVisualCursor,
    required this.geometryRevision,
  });

  final String chapterId;
  final int charOffset;
  final double chapterProgress;

  /// 本次解析使用的几何版本号（ACTIVE_SCROLL 期间应恒定）。
  final int geometryRevision;

  /// 窗口内容坐标（含前缀章节高度）。
  final double contentY;

  /// 视觉坐标（块索引 + 块内偏移 + 块内比例）。
  final VisualPosition visual;

  /// 视觉章节进度：图片内部连续变化，与逻辑进度语义独立。
  final double chapterVisualProgress;

  /// 章体视觉游标（前面块高度 + 当前块内偏移）。
  final double chapterVisualCursor;
}

/// 连续滚动的视觉锚点：视口顶所在块及块内偏移。
///
/// 视觉坐标优先于逻辑坐标：charOffset 只是视觉位置向逻辑层的投影；
/// 块重测高（图片解码、精测分批替换）后按块内比例重映射，用户看到
/// 的内容保持不变。
@immutable
class VisualAnchor {
  const VisualAnchor({
    required this.chapterId,
    required this.blockIndex,
    required this.offsetInBlock,
  });

  final String chapterId;
  final int blockIndex;

  /// 块内像素偏移（相对块顶）。
  final double offsetInBlock;

  @override
  String toString() =>
      'VisualAnchor($chapterId#$blockIndex+${offsetInBlock.toStringAsFixed(1)})';
}

/// 多章连续滚动窗口控制器。
///
/// 维护 current±1 的章节窗口，把多章拼成一条虚拟列表坐标，
/// 顺序滚动不触发硬切章；跳转仍由外层 switchToChapter 处理。
class ReaderContinuousScrollController extends ChangeNotifier {
  ReaderContinuousScrollController({this.sideChapterCount = 1});

  /// 锚点章两侧各保留的章节数。
  final int sideChapterCount;

  String? _anchorChapterId;
  List<ContinuousChapterEntry> _entries = const [];
  List<ContinuousScrollItem> _items = const [];
  final Map<String, ContinuousChapterEntry> _entryById = {};
  final Map<String, double> _prefixHeights = {};

  String? get anchorChapterId => _anchorChapterId;
  List<ContinuousChapterEntry> get entries => _entries;
  List<ContinuousScrollItem> get items => _items;
  bool get isEmpty => _entries.isEmpty;

  ContinuousChapterEntry? entryFor(String chapterId) => _entryById[chapterId];

  /// 指定章节在窗口中的前缀高度（其之前所有章高度之和）。
  double prefixHeightOf(String chapterId) => _prefixHeights[chapterId] ?? 0;

  /// 窗口总高度。
  double get totalHeight {
    if (_entries.isEmpty) return 0;
    final last = _entries.last;
    return prefixHeightOf(last.chapterId) + effectiveExtentOf(last);
  }

  /// 未加载章的兜底占位高度。
  static const double fallbackPlaceholderHeight = 240;

  /// 章头 sliver 高度，与 view 的 _ChapterHeaderDelegate 对齐。
  static const double chapterHeaderExtent = 36;

  /// 章尾留白，与 view 的 ch-trailing 对齐：就绪章 48 / 未就绪章 24。
  static const double chapterTrailingExtent = 48;
  static const double chapterTrailingLoadingExtent = 24;

  /// 章在窗口中的完整占位高度：章头 + 章体 + 章尾。
  ///
  /// 窗口坐标（prefix、positionAtContentY、contentYFor）必须与 view 的
  /// sliver 布局（header + body + trailing）一致，否则跨章边界换算有
  /// 固定偏差。
  double effectiveExtentOf(ContinuousChapterEntry entry) {
    return chapterHeaderExtent +
        entry.totalHeight +
        (entry.isReady ? chapterTrailingExtent : chapterTrailingLoadingExtent);
  }

  /// 用新的锚点章与全量章节元数据重建窗口。
  ///
  /// [resolve] 负责提供某章的已加载数据；返回 null 表示尚未加载。
  /// [estimateHeight] 为未加载章提供基于字数的估算高度，减少占位跳动。
  ///
  /// 若窗口组成与布局指纹未变化，不调用 [notifyListeners]，避免滚动热路径重建。
  void rebuild({
    required String anchorChapterId,
    required List<String> allChapterIds,
    required ContinuousChapterEntry? Function(String chapterId) resolve,
    double Function(String chapterId)? estimateHeight,
  }) {
    final anchorIndex = allChapterIds.indexOf(anchorChapterId);
    if (anchorIndex < 0) {
      if (_entries.isEmpty && _anchorChapterId == anchorChapterId) {
        return;
      }
      _anchorChapterId = anchorChapterId;
      _entries = const [];
      _items = const [];
      _entryById.clear();
      _prefixHeights.clear();
      notifyListeners();
      return;
    }

    final start = (anchorIndex - sideChapterCount).clamp(
      0,
      allChapterIds.length,
    );
    final endExclusive = (anchorIndex + sideChapterCount + 1).clamp(
      0,
      allChapterIds.length,
    );
    final nextEntries = <ContinuousChapterEntry>[];
    for (var i = start; i < endExclusive; i++) {
      final id = allChapterIds[i];
      final resolved = resolve(id);
      if (resolved != null) {
        nextEntries.add(resolved);
        continue;
      }
      final estimated = estimateHeight?.call(id) ?? 0;
      nextEntries.add(
        ContinuousChapterEntry(
          chapterId: id,
          title: '',
          blockCount: 0,
          cumulativeHeights: const [],
          totalHeight: estimated > 0 ? estimated : fallbackPlaceholderHeight,
          totalChars: 0,
          isReady: false,
        ),
      );
    }

    if (_anchorChapterId == anchorChapterId &&
        _windowSignatureEqual(_entries, nextEntries)) {
      return;
    }

    _anchorChapterId = anchorChapterId;
    _entries = nextEntries;
    _entryById
      ..clear()
      ..addEntries(nextEntries.map((e) => MapEntry(e.chapterId, e)));
    _prefixHeights.clear();
    var running = 0.0;
    for (final entry in nextEntries) {
      _prefixHeights[entry.chapterId] = running;
      running += effectiveExtentOf(entry);
    }
    _items = _buildItems(nextEntries);
    geometryRevision++;
    notifyListeners();
  }

  /// 构建当前 Live 几何的不可变快照（方案 §10：ScrollStart 时生成）。
  ReaderGeometrySnapshot buildGeometrySnapshot({int? revision}) {
    return ReaderGeometrySnapshot.fromController(
      this,
      revision: revision ?? geometryRevision,
    );
  }

  /// 窗口签名比较：章组成、就绪态与高度指纹一致则视为未变化。
  bool _windowSignatureEqual(
    List<ContinuousChapterEntry> a,
    List<ContinuousChapterEntry> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.chapterId != y.chapterId ||
          x.title != y.title ||
          x.blockCount != y.blockCount ||
          x.totalChars != y.totalChars ||
          x.isReady != y.isReady ||
          x.totalHeight != y.totalHeight) {
        return false;
      }
      final hx = x.cumulativeHeights;
      final hy = y.cumulativeHeights;
      if (hx.length != hy.length) {
        return false;
      }
      if (hx.isNotEmpty && hx.last != hy.last) {
        return false;
      }
    }
    return true;
  }

  List<ContinuousScrollItem> _buildItems(List<ContinuousChapterEntry> entries) {
    final items = <ContinuousScrollItem>[];
    for (final entry in entries) {
      items.add(
        ContinuousScrollItem.chapterHeader(
          chapterId: entry.chapterId,
          title: entry.title,
        ),
      );
      for (var i = 0; i < entry.blockCount; i++) {
        items.add(
          ContinuousScrollItem.block(chapterId: entry.chapterId, blockIndex: i),
        );
      }
      items.add(
        ContinuousScrollItem.chapterTrailing(chapterId: entry.chapterId),
      );
    }
    return items;
  }

  /// 唯一位置解析器：所有 contentY ↔ Visual ↔ Logical 换算经此完成，
  /// 控制器只保留窗口几何（章条目、前缀高度、chrome 常量）的所有权。
  late final ReaderContinuousPositionResolver resolver =
      ReaderContinuousPositionResolver(this);

  /// 窗口几何版本号：rebuild 实际应用变化时递增，供快照与诊断对齐。
  int geometryRevision = 0;

  /// 根据窗口内容 Y 解析阅读位置（双坐标：视觉 + 逻辑）。
  ContinuousScrollPosition? positionAtContentY(
    double contentY, {
    ReaderScrollGeometrySource source = const LiveScrollGeometrySource(),
  }) {
    final resolved = resolver.resolveContentY(contentY, source: source);
    if (resolved == null) {
      return null;
    }
    return ContinuousScrollPosition(
      chapterId: resolved.chapterId,
      charOffset: resolved.logical.charOffset,
      chapterProgress: resolved.chapterProgress,
      contentY: resolved.contentY,
      visual: resolved.visual,
      chapterVisualProgress: resolved.chapterVisualProgress,
      chapterVisualCursor: resolved.chapterVisualCursor,
      geometryRevision: resolved.geometryRevision,
    );
  }

  /// 解析窗口 contentY 处的视觉锚点（运行时布局保持用）。
  VisualAnchor? visualAnchorAt(
    double contentY, {
    ReaderScrollGeometrySource source = const LiveScrollGeometrySource(),
  }) {
    final visual = resolver.visualAtContentY(contentY, source: source);
    if (visual == null) {
      return null;
    }
    return VisualAnchor(
      chapterId: visual.chapterId,
      blockIndex: visual.blockIndex,
      offsetInBlock: visual.offsetInBlock,
    );
  }

  /// 视觉锚点对应的窗口 contentY；锚点章不在窗口或块级高度缺失时
  /// 返回 null，调用方应回退高度差补偿。
  double? contentYForVisualAnchor(VisualAnchor anchor) {
    return resolver.contentYForVisualPosition(
      VisualPosition(
        chapterId: anchor.chapterId,
        blockIndex: anchor.blockIndex,
        offsetInBlock: anchor.offsetInBlock,
        blockRatio: 0,
      ),
    );
  }

  /// 块重测高后重映射视觉锚点：块高变化时按块内比例保持相对位置。
  ///
  /// 例如用户位于图片中部（oldHeight 600、offset 300），重测得
  /// newHeight 800 后偏移变为 400，不回跳块顶。
  VisualAnchor? remapVisualAnchor(
    VisualAnchor anchor, {
    ContinuousChapterEntry? oldEntry,
  }) {
    final remapped = resolver.remapVisualPosition(
      VisualPosition(
        chapterId: anchor.chapterId,
        blockIndex: anchor.blockIndex,
        offsetInBlock: anchor.offsetInBlock,
        blockRatio: 0,
      ),
      oldEntry: oldEntry,
    );
    if (remapped == null) {
      return null;
    }
    return VisualAnchor(
      chapterId: remapped.chapterId,
      blockIndex: remapped.blockIndex,
      offsetInBlock: remapped.offsetInBlock,
    );
  }

  /// 某章 charOffset 对应的窗口 contentY。
  double contentYFor({
    required String chapterId,
    required int charOffset,
    required int totalChars,
    required double chapterHeight,
  }) {
    final prefix = prefixHeightOf(chapterId);
    if (totalChars <= 0 || chapterHeight <= 0) {
      return prefix + chapterHeaderExtent;
    }
    final ratio = (charOffset / totalChars).clamp(0.0, 1.0);
    return prefix + chapterHeaderExtent + ratio * chapterHeight;
  }

  /// 是否需要向后扩挂（视口接近窗口末尾）。
  bool shouldExpandForward(double contentY, double viewportHeight) {
    if (_entries.isEmpty) return false;
    // 2 个视口的提前量：扩挂需预取 + phase-one 测高 + 窗口重建，
    // 1.2 视口在快速滚动下会先看到估算高度甚至空白。
    return contentY + viewportHeight * 2.0 >= totalHeight;
  }

  /// 是否需要向前扩挂（视口接近窗口开头）。
  bool shouldExpandBackward(double contentY) {
    if (_entries.isEmpty) return false;
    return contentY <= viewportGuard;
  }

  static const double viewportGuard = 240;

  /// 当前锚点是否已随滚动进入下一章。
  bool get canAdvanceForward {
    final anchor = _anchorChapterId;
    if (anchor == null || _entries.length < 2) return false;
    return _entries.first.chapterId == anchor;
  }

  /// 当前锚点是否已回退到上一章。
  bool get canRetreatBackward {
    final anchor = _anchorChapterId;
    if (anchor == null || _entries.length < 2) return false;
    return _entries.last.chapterId == anchor;
  }
}
