part of 'reader_content_loader.dart';

/// 翻页模式的懒分页导航器。
///
/// 按需计算单页并保留页边界，避免重复执行文本测量。
class PageNavigator {
  PageNavigator({required this.blocks, required this.computeFn});

  final List<ContentBlock> blocks;
  final PageSlice? Function(int startCharOffset) computeFn;

  final _cache = <int, PageSlice>{};
  int _currentPage = 0;

  /// 已计算到的最高页码（用于估算总页数）。
  int _maxComputedPage = -1;

  /// 最后一页是否返回了 null（即内容已耗尽）。
  bool _reachedEnd = false;
  bool _prefetching = false;
  int _prefetchTargetPage = -1;

  int get currentPage => _currentPage;

  /// 确认可读的页数（不含探测页）。
  ///
  /// 已分页完毕时返回精确值；未完毕时返回已确认有内容的页数。
  /// PageView.itemCount 应使用此值。
  int get readablePageCount => _maxComputedPage + 1;

  /// 是否已确认所有页都计算完毕。
  bool get isFullyPaginated => _reachedEnd;

  /// 获取指定页的切片（懒计算 + LRU 缓存）。
  PageSlice? getSlice(int pageIndex) {
    if (pageIndex < 0) return null;
    if (_reachedEnd && pageIndex > _maxComputedPage) return null;

    if (_cache.containsKey(pageIndex)) {
      _currentPage = pageIndex;
      return _cache[pageIndex];
    }

    final sw = Stopwatch()..start();
    final slice = _computeSlice(pageIndex);
    sw.stop();
    if (kDebugMode && sw.elapsedMilliseconds > 8) {
      // 帧预算观测：单页测量超过半帧（8ms/120Hz 预算）时告警。
      readerDebugLog(
        'PageNavigator: slice#$pageIndex computed in '
        '${sw.elapsedMilliseconds}ms',
      );
    }
    if (slice == null) {
      _reachedEnd = true;
      return null;
    }

    _cache[pageIndex] = slice;
    _currentPage = pageIndex;
    if (pageIndex > _maxComputedPage) _maxComputedPage = pageIndex;
    _evictFarPages();
    return slice;
  }

  /// 窗口保护式淘汰：只清除距当前页 ±_evictWindow 以外的页。
  /// _computeSlice 递归依赖前一页缓存，朴素 LRU 会级联重算。
  static const _evictWindow = 32;
  static const _maxCacheSize = 128;

  void _evictFarPages() {
    if (_cache.length <= _maxCacheSize) {
      return;
    }
    final lo = _currentPage - _evictWindow;
    final hi = _currentPage + _evictWindow;
    // _maxComputedPage 以下的页可能被递归依赖（_computeSlice(pageIndex-1) 链），保留 [0, hi] 窗口。
    _cache.removeWhere((page, _) => page < lo || page > hi);
  }

  /// 计算指定页的切片（递归依赖前一页）。
  ///
  /// 直接用上一页的 endCharOffset 作为起始点，
  /// 确保 pages[i].endCharOffset == pages[i+1].startCharOffset。
  PageSlice? _computeSlice(int pageIndex) {
    final prevSlice = pageIndex > 0 ? getSlice(pageIndex - 1) : null;
    if (prevSlice != null &&
        prevSlice.nextCursor <= prevSlice.startCharOffset) {
      return null;
    }
    final startCharOffset = prevSlice?.nextCursor ?? 0;
    final slice = computeFn(startCharOffset);
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
