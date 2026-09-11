import 'package:flutter/foundation.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';

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

/// 连续滚动阅读位置。
@immutable
class ContinuousScrollPosition {
  const ContinuousScrollPosition({
    required this.chapterId,
    required this.charOffset,
    required this.chapterProgress,
    required this.contentY,
  });

  final String chapterId;
  final int charOffset;
  final double chapterProgress;

  /// 窗口内容坐标（含前缀章节高度）。
  final double contentY;
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
    notifyListeners();
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

  /// 根据窗口内容 Y 解析阅读位置。
  ///
  /// 就绪章优先按「块索引 + 块级字符前缀」映射；文本块再按块内高度比例插值，
  /// 非文本块（图/表/分隔线）落到块起止字符，避免全章线性插值拉偏进度。
  ContinuousScrollPosition? positionAtContentY(double contentY) {
    if (_entries.isEmpty || _anchorChapterId == null) {
      return null;
    }
    final y = contentY < 0 ? 0.0 : contentY;
    for (final entry in _entries) {
      final start = prefixHeightOf(entry.chapterId);
      final end = start + effectiveExtentOf(entry);
      if (y < end || identical(entry, _entries.last)) {
        // 章体位于章头之后：章头区域映射章首，章尾留白映射章尾。
        final localY = (y - start - chapterHeaderExtent).clamp(
          0.0,
          entry.totalHeight,
        );
        final resolved = _charOffsetInEntry(entry, localY);
        final progress =
            entry.totalChars > 0
                ? (resolved / entry.totalChars).clamp(0.0, 1.0)
                : 0.0;
        return ContinuousScrollPosition(
          chapterId: entry.chapterId,
          charOffset: resolved,
          chapterProgress: progress,
          contentY: y,
        );
      }
    }
    return null;
  }

  int _charOffsetInEntry(ContinuousChapterEntry entry, double localY) {
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

    var lo = 0;
    var hi = entry.blockCount - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (entry.cumulativeHeights[mid] < localY) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final blockStart = lo > 0 ? entry.cumulativeHeights[lo - 1] : 0.0;
    final blockEnd = entry.cumulativeHeights[lo];
    final blockHeight = blockEnd - blockStart;
    final ratioInBlock =
        blockHeight > 0
            ? ((localY - blockStart) / blockHeight).clamp(0.0, 1.0)
            : 0.0;
    final blockCharStart = prefixes[lo];
    final blockCharEnd = prefixes[lo + 1];
    final blockChars = blockCharEnd - blockCharStart;
    if (blockChars <= 0) {
      // 非文本块（图/分隔线等）：落在块起点；越过半高则落到块后。
      return ratioInBlock >= 0.5 ? blockCharEnd : blockCharStart;
    }
    final isTextBlock =
        lo >= entry.blocks.length ||
        entry.blocks[lo] is ParagraphBlock ||
        entry.blocks[lo] is BlockquoteBlock ||
        entry.blocks[lo] is ListBlock ||
        entry.blocks[lo] is HeadingBlock;
    if (!isTextBlock) {
      return ratioInBlock >= 0.5 ? blockCharEnd : blockCharStart;
    }
    return (blockCharStart + (ratioInBlock * blockChars).round()).clamp(
      blockCharStart,
      blockCharEnd,
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
