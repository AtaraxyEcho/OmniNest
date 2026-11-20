part of 'reader_content_loader.dart';

/// 翻页模式的懒分页导航器。
///
/// 按需计算单页并保留页边界，避免重复执行文本测量。
class PageNavigator {
  PageNavigator({required this.blocks, required this.computeFn});

  final List<ContentBlock> blocks;

  /// 上一页 → 下一页。页链的推进与到底判定都在分页布局里（`computeNextPage`），
  /// 导航器只管缓存与页码：零宽块链的续页位置不在字符轴上，这里自己算游标就会算错。
  final PageSlice? Function(PageSlice? previous) computeFn;

  final _cache = <int, PageSlice>{};
  int _currentPage = 0;

  /// 已计算到的最高页码（用于估算总页数）。
  int _maxComputedPage = -1;

  /// 最后一页是否返回了 null（即内容已耗尽）。
  bool _reachedEnd = false;
  bool _prefetching = false;
  int _prefetchTargetPage = -1;
  int? _confirmedTotalPages;
  bool _fullPaginating = false;
  int _fullPaginationToken = 0;

  int? get confirmedTotalPages => _confirmedTotalPages;

  int get _chapterTotalChars => blocks.fold<int>(
    0,
    (sum, block) => sum + BlockClipper.blockCharCount(block),
  );

  /// 稳定的展示总页数：全章分页完成后返回精确真实总页数；
  /// 测算中返回字符密度估算值，彻底消除「翻一页总页数+1」。
  int get displayTotalPages {
    if (_confirmedTotalPages != null) return _confirmedTotalPages!;
    if (_reachedEnd) return _maxComputedPage + 1;
    if (_maxComputedPage < 0) return 1;
    final lastSlice = _cache[_maxComputedPage];
    final coveredChars = lastSlice?.endCharOffset ?? 0;
    final totalChars = _chapterTotalChars;
    if (coveredChars <= 0 || totalChars <= coveredChars) {
      return _maxComputedPage + 1;
    }
    final avgCharsPerPage = coveredChars / (_maxComputedPage + 1);
    return math.max(
      _maxComputedPage + 1,
      (totalChars / avgCharsPerPage).ceil(),
    );
  }

  /// 时间片后台全章分页：每帧预算 <= 6ms，算完锁定 [confirmedTotalPages]。
  void scheduleFullPagination({
    VoidCallback? onCompleted,
    bool Function()? isCancelled,
  }) {
    if (_reachedEnd || _confirmedTotalPages != null) {
      _confirmedTotalPages ??= _maxComputedPage + 1;
      onCompleted?.call();
      return;
    }
    if (_fullPaginating) return;
    _fullPaginating = true;
    final token = ++_fullPaginationToken;
    unawaited(_runFullPagination(token, onCompleted, isCancelled));
  }

  Future<void> _runFullPagination(
    int token,
    VoidCallback? onCompleted,
    bool Function()? isCancelled,
  ) async {
    try {
      final sw = Stopwatch();
      while (!_reachedEnd && token == _fullPaginationToken) {
        if (isCancelled?.call() ?? false) return;
        sw
          ..reset()
          ..start();
        while (!_reachedEnd && sw.elapsedMilliseconds < 6) {
          final nextPage = _maxComputedPage + 1;
          final slice = _computeSlice(nextPage);
          if (slice == null) {
            _reachedEnd = true;
            _confirmedTotalPages = _maxComputedPage + 1;
            break;
          }
          _cache[nextPage] = slice;
          _maxComputedPage = nextPage;
        }
        sw.stop();
        if (_reachedEnd) break;
        await Future<void>.delayed(Duration.zero);
      }
      if (_reachedEnd && token == _fullPaginationToken) {
        _confirmedTotalPages = _maxComputedPage + 1;
        onCompleted?.call();
      }
    } finally {
      if (token == _fullPaginationToken) {
        _fullPaginating = false;
      }
    }
  }

  void cancelFullPagination() {
    _fullPaginationToken++;
    _fullPaginating = false;
  }

  int get currentPage => _currentPage;

  /// 确认可读的页数（不含探测页）。
  ///
  /// 已分页完毕时返回精确值；未完毕时返回已确认有内容的页数。
  /// PageView.itemCount 应使用此值。
  int get readablePageCount => _maxComputedPage + 1;

  /// 是否已确认所有页都计算完毕。
  bool get isFullyPaginated => _reachedEnd;

  /// 获取指定页的切片（按需顺序递推 + 尾部窗口裁剪）。
  PageSlice? getSlice(int pageIndex) {
    if (pageIndex < 0) return null;
    if (_reachedEnd && pageIndex > _maxComputedPage) return null;

    final cached = _cache[pageIndex];
    if (cached != null) {
      _currentPage = pageIndex;
      // 命中缓存也要按新的当前页裁窗：只在新计算页时裁剪的话，连续回跳
      // 会让缓存停在历史峰值上，远端尾部页一直占着内存。
      _evictFarPages();
      return cached;
    }

    final sw = Stopwatch()..start();
    // 从已确认的最高连续页向后逐页推进：递归调 getSlice(pageIndex - 1) 时，
    // 前缀一旦缺失就会在一帧内从目标页同步回滚到第 0 页重算，长章直接卡死 UI。
    for (var page = _maxComputedPage + 1; page <= pageIndex; page++) {
      final slice = _computeSlice(page);
      if (slice == null) {
        _reachedEnd = true;
        _confirmedTotalPages = _maxComputedPage + 1;
        break;
      }
      _cache[page] = slice;
      _maxComputedPage = page;
    }
    sw.stop();
    if (kDebugMode && sw.elapsedMilliseconds > 8) {
      // 帧预算观测：单页测量超过半帧（8ms/120Hz 预算）时告警。
      readerDebugLog(
        'PageNavigator: slice#$pageIndex computed in '
        '${sw.elapsedMilliseconds}ms',
      );
    }
    final result = _cache[pageIndex];
    if (result == null) {
      return null;
    }
    _currentPage = pageIndex;
    _evictFarPages();
    return result;
  }

  /// 窗口保护式淘汰：前缀 `[0, _maxComputedPage]` 是递推与二分查找的基础，必须连续保留；
  /// 缓存超限时只裁掉 `hi` 之后的远端尾部页，并把 `_maxComputedPage` 同步回拨。
  /// 只裁尾不裁头，否则 `_findCachedPage` 的二分会落进空洞并把整段已算页当没算过。
  static const _evictWindow = 64;
  static const _maxCacheSize = 512;

  void _evictFarPages() {
    if (_cache.length <= _maxCacheSize) {
      return;
    }
    final hi = _currentPage + _evictWindow;
    if (_maxComputedPage > hi) {
      _cache.removeWhere((page, _) => page > hi);
      _maxComputedPage = hi;
      // 尾部是被裁掉的、不是到底的：恢复可继续向前推进。
      _reachedEnd = false;
    }
  }

  /// 计算单页切片（调用前 `pageIndex - 1` 必然已在缓存里）。
  ///
  /// 下一页的起点由分页布局从上一页推出来（游标 + 零宽块链的续页索引），
  /// 确保 pages[i].endCharOffset == pages[i+1].startCharOffset。
  PageSlice? _computeSlice(int pageIndex) {
    final prevSlice = pageIndex > 0 ? _cache[pageIndex - 1] : null;
    if (pageIndex > 0 && prevSlice == null) {
      return null;
    }
    final slice = computeFn(prevSlice);
    if (slice == null) {
      return null;
    }
    // 无进展保护：游标校正后若得到与上一页完全相同的页（块与行范围一致），
    // 说明无法继续推进，判定内容结束，避免页链死循环。
    if (prevSlice != null &&
        slice.startIndex == prevSlice.startIndex &&
        slice.startLine == prevSlice.startLine &&
        slice.endIndex == prevSlice.endIndex &&
        slice.endLine == prevSlice.endLine &&
        slice.nextCursor <= prevSlice.nextCursor) {
      return null;
    }
    return slice;
  }

  /// 在当前帧结束后逐页预热后续分页结果。
  ///
  /// 每轮只计算一页并让出事件循环，避免把多个文本测量任务集中到翻页手势帧。
  void schedulePrefetch(
    int currentIndex, {
    int pagesAhead = 3,
    VoidCallback? onPageReady,
  }) {
    final targetPage = currentIndex + pagesAhead;
    if (targetPage > _prefetchTargetPage) {
      _prefetchTargetPage = targetPage;
    }
    if (_prefetching || _reachedEnd) {
      return;
    }
    _prefetching = true;
    unawaited(_runPrefetch(onPageReady));
  }

  Future<void> _runPrefetch(VoidCallback? onPageReady) async {
    try {
      while (!_reachedEnd && _maxComputedPage < _prefetchTargetPage) {
        await Future<void>.delayed(Duration.zero);
        final nextPage = _maxComputedPage + 1;
        final beforeCount = readablePageCount;
        getSlice(nextPage);
        if (readablePageCount > beforeCount) {
          onPageReady?.call();
        }
        SchedulerBinding.instance.scheduleFrame();
        await SchedulerBinding.instance.endOfFrame;
      }
    } finally {
      _prefetching = false;
      if (!_reachedEnd && _maxComputedPage < _prefetchTargetPage) {
        schedulePrefetch(
          _maxComputedPage,
          pagesAhead: _prefetchTargetPage - _maxComputedPage,
          onPageReady: onPageReady,
        );
      }
    }
  }

  /// 确保指定页已计算并缓存。返回该页切片，或 null（章节结束）。
  PageSlice? ensurePage(int pageIndex) => getSlice(pageIndex);

  /// 分批定位包含指定字符偏移的页码。
  ///
  /// 每计算一组页面后让出事件循环，避免长章节恢复进度时连续占用 UI 线程。
  Future<int?> findPageByCharOffset(
    int charOffset, {
    int pagesPerBatch = 8,
    bool Function()? isCancelled,
  }) async {
    if (charOffset <= 0 || blocks.isEmpty) {
      return 0;
    }

    var pageIndex = 0;
    if (_maxComputedPage >= 0) {
      final cachedPage = _findCachedPage(charOffset);
      if (cachedPage != null) {
        return cachedPage;
      }
      pageIndex = _maxComputedPage + 1;
    }

    final batchSize = pagesPerBatch.clamp(1, 32);
    while (true) {
      if (isCancelled?.call() ?? false) {
        return null;
      }
      for (var index = 0; index < batchSize; index++) {
        if (isCancelled?.call() ?? false) {
          return null;
        }
        final slice = getSlice(pageIndex);
        if (slice == null) {
          return pageIndex > 0 ? pageIndex - 1 : 0;
        }
        if (charOffset < slice.endCharOffset) {
          return pageIndex;
        }
        pageIndex++;
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  int? _findCachedPage(int charOffset) {
    var low = 0;
    var high = _maxComputedPage;
    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      final slice = _cache[middle];
      if (slice == null) {
        return null;
      }
      if (charOffset < slice.startCharOffset) {
        high = middle - 1;
      } else if (charOffset >= slice.endCharOffset) {
        low = middle + 1;
      } else {
        return middle;
      }
    }
    return null;
  }
}
