import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 翻页流中的一页：属于哪一章的第几页。
class BookPageRef {
  const BookPageRef({required this.chapterId, required this.localPageIndex});

  final String chapterId;
  final int localPageIndex;

  @override
  bool operator ==(Object other) =>
      other is BookPageRef &&
      other.chapterId == chapterId &&
      other.localPageIndex == localPageIndex;

  @override
  int get hashCode => Object.hash(chapterId, localPageIndex);

  @override
  String toString() => 'BookPageRef($chapterId#$localPageIndex)';
}

/// 跨章翻页窗口：把当前章 ±1（可扩）拼成一条页流。
///
/// 不负责文本测量；页数与是否分页完由各章 [PageNavigator] 提供。
/// 探测页（尚未确认的下一页）不在 [pages] 内，由 [needsProbe] 表达。
class ReaderPageFlow {
  ReaderPageFlow({
    required this.chapterIds,
    required this.readableCounts,
    required this.fullyPaginated,
    required this.hasNextChapterAfterWindow,
    required this.hasPrevChapterBeforeWindow,
    required this.anchorChapterId,
  });

  /// 窗口内章节，按阅读顺序。
  final List<String> chapterIds;
  final Map<String, int> readableCounts;
  final Map<String, bool> fullyPaginated;
  final bool hasNextChapterAfterWindow;
  final bool hasPrevChapterBeforeWindow;
  final String anchorChapterId;

  List<BookPageRef>? _pagesCache;
  Map<BookPageRef, int>? _indexByRefCache;
  Map<String, int>? _startIndexByChapterCache;

  /// 展开后的已确认页序列。
  List<BookPageRef> get pages {
    return _pagesCache ??= [
      for (final chapterId in chapterIds)
        for (var i = 0; i < (readableCounts[chapterId] ?? 0); i++)
          BookPageRef(chapterId: chapterId, localPageIndex: i),
    ];
  }

  /// 页身份 → 全局索引（随 [pages] 惰性建表）。
  Map<BookPageRef, int> get _indexByRef =>
      _indexByRefCache ??= {for (var i = 0; i < pages.length; i++) pages[i]: i};

  /// 章节 → 章内第一页全局索引（首次出现；随 [pages] 惰性建表）。
  Map<String, int> get _startIndexByChapter {
    final cached = _startIndexByChapterCache;
    if (cached != null) {
      return cached;
    }
    final map = <String, int>{};
    for (var i = 0; i < pages.length; i++) {
      map.putIfAbsent(pages[i].chapterId, () => i);
    }
    return _startIndexByChapterCache = map;
  }

  int get readablePageCount => pages.length;

  /// 是否仍需探测下一页（当前章未分页完，或窗口后还有章）。
  bool get needsProbe {
    if (chapterIds.isEmpty) {
      return false;
    }
    final last = chapterIds.last;
    if (!(fullyPaginated[last] ?? false)) {
      return true;
    }
    return hasNextChapterAfterWindow;
  }

  /// PageView.itemCount：已确认页 + 可选探测页。
  int get itemCount => readablePageCount + (needsProbe ? 1 : 0);

  /// 锚点章在页流中的起始全局索引。
  int get anchorStartIndex {
    final idx = chapterIds.indexOf(anchorChapterId);
    if (idx <= 0) {
      return 0;
    }
    var sum = 0;
    for (var i = 0; i < idx; i++) {
      sum += readableCounts[chapterIds[i]] ?? 0;
    }
    return sum;
  }

  BookPageRef? keyAt(int globalIndex) {
    if (globalIndex < 0 || globalIndex >= pages.length) {
      return null;
    }
    return pages[globalIndex];
  }

  /// 反向查找：某章某页在流内的全局索引；不存在返回 null。
  int? indexOf(BookPageRef ref) => _indexByRef[ref];

  /// 全局索引 → 所属章节 id。
  String? chapterIdAt(int globalIndex) => keyAt(globalIndex)?.chapterId;

  /// 章内第一页的全局索引。
  int? startIndexOf(String chapterId) => _startIndexByChapter[chapterId];

  /// 页流重建后的当前页索引归属解析。
  ///
  /// 优先级：待映射章内页 > 显式导航锚定 > 旧页身份重映射 > 越界钳制。
  /// [explicitNavigation] 为 true（切章锁定帧）时禁止旧页身份重映射：
  /// 旧流的页引用可能属于窗口前缀章，重映射会把显式跳章拉回旧章。
  /// [pendingLocalIndex] 在锚点章尚无页（数据未就绪）时不生效，由调用方
  /// 保留待映射索引下帧重试。
  int resolveRebuiltPageIndex({
    required String anchorChapterId,
    required int currentPage,
    BookPageRef? previousRef,
    int? pendingLocalIndex,
    bool explicitNavigation = false,
  }) {
    if (pendingLocalIndex != null || explicitNavigation) {
      final start = startIndexOf(anchorChapterId);
      if (start != null) {
        return start + (pendingLocalIndex ?? 0);
      }
      return currentPage;
    }
    final remapped = previousRef == null ? null : indexOf(previousRef);
    if (remapped != null) {
      return remapped;
    }
    // 身份丢失（窗口滑出/排版重排）：钳制到锚点章起始，避免越界。
    final start = startIndexOf(anchorChapterId) ?? 0;
    final maxIndex = readablePageCount - 1;
    if (currentPage < start || (maxIndex >= 0 && currentPage > maxIndex)) {
      return start.clamp(0, maxIndex < 0 ? 0 : maxIndex);
    }
    return currentPage;
  }

  /// 从 loader + 排版参数构建窗口页流。
  ///
  /// [windowSide]：锚点章两侧各保留的章节数（默认 1）。
  factory ReaderPageFlow.fromLoader({
    required ReaderContentLoader loader,
    required String anchorChapterId,
    required ReaderViewSettings settings,
    required double pageWidth,
    required double pageHeight,
    double textScale = 1.0,
    int windowSide = 1,
  }) {
    final all = loader.chapterIds;
    final anchorIdx = all.indexOf(anchorChapterId);
    final center = anchorIdx < 0 ? 0 : anchorIdx;
    final start = (center - windowSide).clamp(0, all.length);
    final end = (center + windowSide + 1).clamp(0, all.length);
    final windowIds =
        start >= end
            ? <String>[if (anchorIdx >= 0) anchorChapterId]
            : all.sublist(start, end);

    final readable = <String, int>{};
    final done = <String, bool>{};
    for (final id in windowIds) {
      final data = loader.get(id, settings);
      if (data == null) {
        readable[id] = 0;
        done[id] = false;
        continue;
      }
      final navigator = data.getOrCreatePageNavigator(
        pageWidth,
        pageHeight,
        settings,
        textScale: textScale,
      );
      // 触发懒分页至少一页，保证 readablePageCount 有意义。
      if (navigator.readablePageCount == 0 && !navigator.isFullyPaginated) {
        navigator.getSlice(0);
      }
      readable[id] = navigator.readablePageCount;
      done[id] = navigator.isFullyPaginated;
    }

    return ReaderPageFlow(
      chapterIds: windowIds,
      readableCounts: readable,
      fullyPaginated: done,
      hasNextChapterAfterWindow: end < all.length,
      hasPrevChapterBeforeWindow: start > 0,
      anchorChapterId: anchorChapterId,
    );
  }

  /// 前向扩窗：把下一章并入窗口。
  ReaderPageFlow expandForward(List<String> allChapterIds) {
    final lastIdx = allChapterIds.indexOf(
      chapterIds.isEmpty ? anchorChapterId : chapterIds.last,
    );
    if (lastIdx < 0 || lastIdx + 1 >= allChapterIds.length) {
      return this;
    }
    final nextId = allChapterIds[lastIdx + 1];
    return ReaderPageFlow(
      chapterIds: [...chapterIds, nextId],
      readableCounts: {...readableCounts, nextId: 0},
      fullyPaginated: {...fullyPaginated, nextId: false},
      hasNextChapterAfterWindow: lastIdx + 2 < allChapterIds.length,
      hasPrevChapterBeforeWindow: hasPrevChapterBeforeWindow,
      anchorChapterId: anchorChapterId,
    );
  }

  /// 后向扩窗。
  ReaderPageFlow expandBackward(List<String> allChapterIds) {
    final firstIdx = allChapterIds.indexOf(
      chapterIds.isEmpty ? anchorChapterId : chapterIds.first,
    );
    if (firstIdx <= 0) {
      return this;
    }
    final prevId = allChapterIds[firstIdx - 1];
    return ReaderPageFlow(
      chapterIds: [prevId, ...chapterIds],
      readableCounts: {...readableCounts, prevId: 0},
      fullyPaginated: {...fullyPaginated, prevId: false},
      hasNextChapterAfterWindow: hasNextChapterAfterWindow,
      hasPrevChapterBeforeWindow: firstIdx - 1 > 0,
      anchorChapterId: anchorChapterId,
    );
  }
}
