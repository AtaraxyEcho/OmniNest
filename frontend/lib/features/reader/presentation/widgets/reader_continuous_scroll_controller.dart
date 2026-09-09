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

  ContinuousChapterEntry copyWith({
    String? title,
    int? blockCount,
    List<double>? cumulativeHeights,
    double? totalHeight,
    int? totalChars,
    bool? isReady,
    List<ContentBlock>? blocks,
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
    return prefixHeightOf(last.chapterId) + last.totalHeight;
  }

  /// 用新的锚点章与全量章节元数据重建窗口。
  ///
  /// [resolve] 负责提供某章的已加载数据；返回 null 表示尚未加载。
  void rebuild({
    required String anchorChapterId,
    required List<String> allChapterIds,
    required ContinuousChapterEntry? Function(String chapterId) resolve,
  }) {
    _anchorChapterId = anchorChapterId;
    final anchorIndex = allChapterIds.indexOf(anchorChapterId);
    if (anchorIndex < 0) {
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
      nextEntries.add(
        resolved ??
            ContinuousChapterEntry(
              chapterId: id,
              title: '',
              blockCount: 0,
              cumulativeHeights: const [],
              totalHeight: _placeholderHeight,
              totalChars: 0,
              isReady: false,
            ),
      );
    }

    _entries = nextEntries;
    _entryById
      ..clear()
      ..addEntries(nextEntries.map((e) => MapEntry(e.chapterId, e)));
    _prefixHeights.clear();
    var running = 0.0;
    for (final entry in nextEntries) {
      _prefixHeights[entry.chapterId] = running;
      running += entry.totalHeight;
    }
    _items = _buildItems(nextEntries);
    notifyListeners();
  }

  /// 就绪章未加载时的占位高度，避免窗口塌缩。
  static const double _placeholderHeight = 240;

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
  ContinuousScrollPosition? positionAtContentY(double contentY) {
    if (_entries.isEmpty || _anchorChapterId == null) {
      return null;
    }
    final y = contentY < 0 ? 0.0 : contentY;
    for (final entry in _entries) {
      final start = prefixHeightOf(entry.chapterId);
      final end = start + entry.totalHeight;
      if (y < end || identical(entry, _entries.last)) {
        final localY = (y - start).clamp(0.0, entry.totalHeight);
        var charOffset = 0;
        var progress = 0.0;
        if (entry.isReady &&
            entry.totalChars > 0 &&
            entry.cumulativeHeights.length == entry.blockCount &&
            entry.blockCount > 0) {
          var lo = 0;
          var hi = entry.cumulativeHeights.length - 1;
          while (lo < hi) {
            final mid = (lo + hi) >> 1;
            if (entry.cumulativeHeights[mid] < localY) {
              lo = mid + 1;
            } else {
              hi = mid;
            }
          }
          final blockStart = lo > 0 ? entry.cumulativeHeights[lo - 1] : 0.0;
          final blockHeight = entry.cumulativeHeights[lo] - blockStart;
          final ratioInBlock =
              blockHeight > 0
                  ? ((localY - blockStart) / blockHeight).clamp(0.0, 1.0)
                  : 0.0;
          // 近似：按高度比例映射到章内字符。
          charOffset = (localY /
                  (entry.totalHeight <= 0 ? 1 : entry.totalHeight) *
                  entry.totalChars)
              .round()
              .clamp(0, entry.totalChars);
          // 块内比例仅用于平滑进度展示。
          progress = (charOffset / entry.totalChars).clamp(0.0, 1.0);
          if (ratioInBlock == 0 && lo == 0 && localY <= 0) {
            charOffset = 0;
            progress = 0;
          }
        } else if (entry.totalChars > 0) {
          final ratio =
              entry.totalHeight > 0 ? (localY / entry.totalHeight) : 0.0;
          charOffset = (ratio * entry.totalChars).round().clamp(
            0,
            entry.totalChars,
          );
          progress = (charOffset / entry.totalChars).clamp(0.0, 1.0);
        }
        return ContinuousScrollPosition(
          chapterId: entry.chapterId,
          charOffset: charOffset,
          chapterProgress: progress,
          contentY: y,
        );
      }
    }
    return null;
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
      return prefix;
    }
    final ratio = (charOffset / totalChars).clamp(0.0, 1.0);
    return prefix + ratio * chapterHeight;
  }

  /// 是否需要向后扩挂（视口接近窗口末尾）。
  bool shouldExpandForward(double contentY, double viewportHeight) {
    if (_entries.isEmpty) return false;
    return contentY + viewportHeight * 1.2 >= totalHeight;
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
