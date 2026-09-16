import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 单章分页数据。
///
/// slices 和 cumulativeHeights 为内部状态，
/// 仅通过 ReaderContentLoader 的方法修改。
class ChapterData {
  ChapterData({
    required this.chapterId,
    required this.content,
    required this.blocks,
    List<PageSlice> slices = const [],
    List<double> cumulativeHeights = const [],
    this.totalChars = 0,
  }) : _slices = slices,
       _cumulativeHeights = cumulativeHeights;

  final String chapterId;
  final ReaderChapterContent content;
  final List<ContentBlock> blocks;
  final int totalChars;

  List<PageSlice> get slices => _slices;
  final List<PageSlice> _slices;

  List<double> get cumulativeHeights => _cumulativeHeights;
  List<double> _cumulativeHeights;

  List<int> _blockCharPrefixes = const [];

  /// 累积字符前缀：`blockCharPrefixes[i]` = 前 i 块的字符数之和，
  /// 长度 = 块数 + 1。blocks 创建后内容不变，惰性计算一次；
  /// 供 contentYToCharOffset / charOffsetToPixelOffset 消除逐帧线性累加。
  List<int> get blockCharPrefixes {
    if (_blockCharPrefixes.length != blocks.length + 1) {
      final prefixes = List<int>.filled(blocks.length + 1, 0);
      for (var i = 0; i < blocks.length; i++) {
        prefixes[i + 1] = prefixes[i] + _blockCharCount(blocks[i]);
      }
      _blockCharPrefixes = prefixes;
    }
    return _blockCharPrefixes;
  }

  /// 翻页模式的懒分页导航器（按需计算单页）。
  PageNavigator? _pageNavigator;
  double? _navigatorPageWidth;
  double? _navigatorPageHeight;
  double? _navigatorFontSize;
  double? _navigatorLineHeight;
  String? _navigatorFontFamily;
  double? _navigatorTextScale;

  /// 获取或创建翻页导航器。
  ///
  /// 当视口尺寸或排版参数变化时自动重建 navigator。
  PageNavigator getOrCreatePageNavigator(
    double pageWidth,
    double pageHeight,
    ReaderViewSettings settings, {
    double textScale = 1.0,
  }) {
    final layoutChanged =
        !_sameDimension(_navigatorPageWidth, pageWidth) ||
        !_sameDimension(_navigatorPageHeight, pageHeight) ||
        _navigatorFontSize != settings.fontSize ||
        _navigatorLineHeight != settings.lineHeight ||
        _navigatorFontFamily != settings.fontFamily ||
        _navigatorTextScale != textScale;
    if (_pageNavigator != null && layoutChanged) {
      _pageNavigator = null;
    }
    if (_pageNavigator == null) {
      final pageLayout = ReaderPaginationEngine.preparePageLayout(
        blocks,
        pageWidth,
        pageHeight,
        settings,
        textScale: textScale,
      );
      _pageNavigator = PageNavigator(
        blocks: blocks,
        computeFn: pageLayout.computePage,
      );
    }
    _navigatorPageWidth = pageWidth;
    _navigatorPageHeight = pageHeight;
    _navigatorFontSize = settings.fontSize;
    _navigatorLineHeight = settings.lineHeight;
    _navigatorFontFamily = settings.fontFamily;
    _navigatorTextScale = textScale;
    return _pageNavigator!;
  }

  /// 清除翻页导航器缓存（设置变更或窗口变化时调用）。
  void invalidatePageNavigator() {
    _pageNavigator = null;
    _navigatorPageWidth = null;
    _navigatorPageHeight = null;
    _navigatorFontSize = null;
    _navigatorLineHeight = null;
    _navigatorFontFamily = null;
    _navigatorTextScale = null;
  }

  static bool _sameDimension(double? previous, double current) =>
      previous != null && (previous - current).abs() < 0.5;

  /// 更新累积高度（仅限 ReaderContentLoader 调用）。
  ///
  /// 估算填充与精测分批都经此入口，更新即视为未精测；
  /// 精测全部批次完成后由 [markPreciseHeights] 置位。
  void updateCumulativeHeights(List<double> newHeights) {
    _cumulativeHeights = newHeights;
    _hasPreciseHeights = false;
  }

  bool _hasPreciseHeights = false;

  /// 累积高度是否已完成第二阶段精测。
  bool get hasPreciseHeights => _hasPreciseHeights;

  /// 精测全部批次完成标记（仅限 ReaderContentLoader 调用）。
  void markPreciseHeights() => _hasPreciseHeights = true;
}

/// 滚动模式测高分批参数：头部精确测量块数与每批测量块数。
const _metricsPhaseOneBlocks = 12;
const _metricsBatchBlocks = 40;

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

/// 内容加载器：管理章节内容的加载、解析、缓存、预加载。
///
/// 缓存 key 包含字体设置，确保设置变化后自动失效。
/// 缓存 key：chapterId + 字体设置指纹。
class _CacheKey {
  final String chapterId;
  final double fontSize;
  final double lineHeight;
  final String fontFamily;

  const _CacheKey({
    required this.chapterId,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _CacheKey &&
          chapterId == other.chapterId &&
          fontSize == other.fontSize &&
          lineHeight == other.lineHeight &&
          fontFamily == other.fontFamily);

  @override
  int get hashCode => Object.hash(chapterId, fontSize, lineHeight, fontFamily);
}

class ReaderContentLoader {
  ReaderContentLoader({required this.allChapters});

  final List<ReaderChapter> allChapters;
  final Map<_CacheKey, ChapterData> _cache = {};
  int _heightsGeneration = 0;
  final Map<_CacheKey, Future<ChapterData>> _inflight = {};
  final Map<String, ReaderChapterContent> _contentCache = {};
  String? _activeChapterId;

  String? get activeChapterId => _activeChapterId;

  _CacheKey _key(String chapterId, ReaderViewSettings settings) {
    return _CacheKey(
      chapterId: chapterId,
      fontSize: settings.fontSize,
      lineHeight: settings.lineHeight,
      fontFamily: settings.fontFamily,
    );
  }

  /// 加载章节内容，并按当前阅读模式准备布局数据。
  Future<ChapterData> loadChapter({
    required String chapterId,
    required ReaderChapterContent content,
    required double pageWidth,
    required double pageHeight,
    required ReaderViewSettings settings,
    double textScale = 1.0,
    bool prepareScrollLayout = true,
  }) async {
    _contentCache[chapterId] = content;
    final key = _key(chapterId, settings);
    final cached = _cache[key];
    if (cached != null) {
      _prepareScrollMetricsIfNeeded(
        cached,
        prepareScrollLayout: prepareScrollLayout,
        pageWidth: pageWidth,
        settings: settings,
        textScale: textScale,
      );
      return cached;
    }

    final loadFuture = _inflight.putIfAbsent(
      key,
      () => _parseChapter(chapterId: chapterId, content: content),
    );
    try {
      final data = await loadFuture;
      if (_shouldRetainChapter(chapterId)) {
        _cache[key] = data;
      }
      _prepareScrollMetricsIfNeeded(
        data,
        prepareScrollLayout: prepareScrollLayout,
        pageWidth: pageWidth,
        settings: settings,
        textScale: textScale,
      );
      return data;
    } finally {
      if (identical(_inflight[key], loadFuture)) {
        _inflight.remove(key);
      }
    }
  }

  Future<ChapterData> _parseChapter({
    required String chapterId,
    required ReaderChapterContent content,
  }) async {
    final isLarge = content.content.length > 10000;

    List<ContentBlock> blocks;
    // isolate 只做 HTML 解析（parseBlocks 纯 Dart 代码，无 Flutter 依赖）
    // TextPainter 不能在 isolate 中使用（继承 NativeFieldWrapperClass2）
    // Web 平台 compute 返回 JSArray，无法转为 Dart List，直接调用
    if (isLarge && !kIsWeb) {
      blocks = await compute(parseBlocks, content.content);
    } else {
      blocks = parseBlocks(content.content);
    }

    // 如果 HTML 解析无 blocks，用纯文本创建段落块（兜底）
    if (blocks.isEmpty && content.content.trim().isNotEmpty) {
      if (kDebugMode) {
        readerDebugLog(
          'ReaderContentLoader: parseBlocks returned empty, creating fallback paragraph',
        );
      }
      final plainText =
          content.content
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .replaceAll(RegExp(r'&[a-zA-Z]+;'), ' ')
              .trim();
      final displayText = plainText.isNotEmpty ? plainText : content.title;
      if (displayText.isNotEmpty) {
        blocks = [
          ParagraphBlock(
            lines: [
              LineData(spans: [ReaderInlineSpan(text: displayText)]),
            ],
            hasTrailingSpacing: false,
          ),
        ];
      }
    }
    return ChapterData(
      chapterId: chapterId,
      content: content,
      blocks: blocks,
      slices: const <PageSlice>[],
      cumulativeHeights: const <double>[],
      totalChars: blocks.fold(0, (sum, b) => sum + _blockCharCount(b)),
    );
  }

  void _prepareScrollMetricsIfNeeded(
    ChapterData data, {
    required bool prepareScrollLayout,
    required double pageWidth,
    required ReaderViewSettings settings,
    required double textScale,
  }) {
    if (!prepareScrollLayout || data.cumulativeHeights.isNotEmpty) {
      return;
    }
    // 第一阶段：精确测量头部若干块，以平均块高估算整章，立即填充
    // cumulative 数组，保证滚动映射从首帧起无空洞。
    // 估算基线优先取已精测章节的分块型高度均值（同书排版一致），
    // 降低 estimate→precise 转换时的窗口高度跳变。
    final blocks = data.blocks;
    final headCount = math.min(_metricsPhaseOneBlocks, blocks.length);
    final headHeights = <double>[];
    var headCumulative = 0.0;
    for (var i = 0; i < headCount; i++) {
      headCumulative += ReaderPaginationEngine.measureBlockHeight(
        blocks[i],
        pageWidth,
        settings,
        textScale: textScale,
      );
      headHeights.add(headCumulative);
    }
    final estimateBase =
        headHeights.isEmpty ? 0.0 : headHeights.last / headCount;
    final typeAverages = _measuredBlockAverages();
    final estimated = List<double>.filled(blocks.length, 0);
    var running = 0.0;
    for (var i = 0; i < blocks.length; i++) {
      running +=
          i < headCount
              ? headHeights[i] - (i == 0 ? 0.0 : headHeights[i - 1])
              : (typeAverages?[blocks[i].runtimeType] ?? estimateBase);
      estimated[i] = running;
    }
    data.updateCumulativeHeights(estimated);
    unawaited(
      _schedulePreciseHeights(
        data,
        pageWidth: pageWidth,
        settings: settings,
        textScale: textScale,
      ),
    );
  }

  /// 第二阶段：分批精确测量并替换估算值。
  ///
  /// 每批让出一帧；代次或 heights 数组身份变化（切章、设置重算、
  /// rekey 替换）即中止，避免旧任务覆盖新状态。
  Future<void> _schedulePreciseHeights(
    ChapterData data, {
    required double pageWidth,
    required ReaderViewSettings settings,
    required double textScale,
  }) async {
    final generation = ++_heightsGeneration;
    final blocks = data.blocks;
    // 以现有高度表为基线（phase-one 估算或部分精测），逐块用实测覆盖：
    // 分批发布的中间态保持单调且 totalHeight 恒有效，避免
    // 「前缀实测 + 尾部全 0」窗口期内进度映射归零，也避免预取推进
    // 代次时把当前章留在被截断的半精测状态。
    final heights =
        data.cumulativeHeights.length == blocks.length
            ? List<double>.of(data.cumulativeHeights)
            : List<double>.filled(blocks.length, 0);
    var cumulative = 0.0;
    for (var i = 0; i < blocks.length; i++) {
      cumulative += ReaderPaginationEngine.measureBlockHeight(
        blocks[i],
        pageWidth,
        settings,
        textScale: textScale,
      );
      heights[i] = cumulative;
      if (i > 0 && heights[i] < heights[i - 1]) {
        heights[i] = heights[i - 1];
      }
      if ((i + 1) % _metricsBatchBlocks == 0 || i == blocks.length - 1) {
        data.updateCumulativeHeights(heights);
        await Future<void>.delayed(Duration.zero);
        if (generation != _heightsGeneration ||
            !identical(data.cumulativeHeights, heights)) {
          return;
        }
      }
    }
    data.markPreciseHeights();
  }

  /// 确保指定章节高度已精测：未精测且非空块章时触发分批精测（幂等，
  /// 重复调用由代次去重）。供进度恢复在落位前等待真实高度使用。
  void ensurePreciseHeights({
    required String chapterId,
    required double pageWidth,
    required ReaderViewSettings settings,
    required double textScale,
  }) {
    final data = get(chapterId, settings);
    if (data == null || data.blocks.isEmpty || data.hasPreciseHeights) {
      return;
    }
    unawaited(
      _schedulePreciseHeights(
        data,
        pageWidth: pageWidth,
        settings: settings,
        textScale: textScale,
      ),
    );
  }

  /// 从首个已精测章节提取各块类型的平均高度，供邻章 phase-one 估算。
  ///
  /// 同一书排版一致，跨章块型均值比仅头部块实测更接近全章真实均值；
  /// 无已精测章节时返回 null，调用方退回头部均值。
  Map<Type, double>? _measuredBlockAverages() {
    for (final data in _cache.values) {
      if (!data.hasPreciseHeights || data.blocks.isEmpty) {
        continue;
      }
      final heights = data.cumulativeHeights;
      if (heights.length != data.blocks.length) {
        continue;
      }
      final sums = <Type, double>{};
      final counts = <Type, int>{};
      for (var i = 0; i < data.blocks.length; i++) {
        final type = data.blocks[i].runtimeType;
        final height = heights[i] - (i == 0 ? 0.0 : heights[i - 1]);
        sums[type] = (sums[type] ?? 0) + height;
        counts[type] = (counts[type] ?? 0) + 1;
      }
      return {
        for (final entry in sums.entries)
          entry.key: entry.value / counts[entry.key]!,
      };
    }
    return null;
  }

  bool _shouldRetainChapter(String chapterId) {
    final activeChapterId = _activeChapterId;
    if (activeChapterId == null) {
      return true;
    }
    final activeIndex = _chapterIndex(activeChapterId);
    final chapterIndex = _chapterIndex(chapterId);
    return activeIndex < 0 ||
        chapterIndex < 0 ||
        (chapterIndex - activeIndex).abs() <= 1;
  }

  /// 获取章节数据（需传入当前 settings 以匹配缓存 key）。
  ChapterData? get(String chapterId, ReaderViewSettings settings) {
    return _cache[_key(chapterId, settings)];
  }

  /// 获取章节数据（仅用 chapterId 查找，匹配任意设置版本）。
  ChapterData? getByChapterId(String chapterId) {
    for (final entry in _cache.entries) {
      if (entry.key.chapterId == chapterId) return entry.value;
    }
    return null;
  }

  /// 返回预加载阶段保留的章节原始内容。
  ReaderChapterContent? contentFor(String chapterId) =>
      _contentCache[chapterId];

  /// 懒计算指定章节的指定页（翻页模式专用）。
  ///
  /// 通过 PageNavigator 按需计算单页并缓存，不预计算全章。
  PageSlice? computePage({
    required String chapterId,
    required ReaderViewSettings settings,
    required double pageWidth,
    required double pageHeight,
    required int pageIndex,
    double textScale = 1.0,
  }) {
    final data = get(chapterId, settings);
    if (data == null) return null;
    final navigator = data.getOrCreatePageNavigator(
      pageWidth,
      pageHeight,
      settings,
      textScale: textScale,
    );
    return navigator.getSlice(pageIndex);
  }

  /// 切换活动章节，驱逐远章，返回需预加载的 chapterId 列表。
  List<String> setActive(String chapterId) {
    _activeChapterId = chapterId;
    final activeIdx = _chapterIndex(chapterId);

    _cache.removeWhere((key, _) {
      final idx = _chapterIndex(key.chapterId);
      return (idx - activeIdx).abs() > 1;
    });
    _contentCache.removeWhere((chapterId, _) {
      final idx = _chapterIndex(chapterId);
      return (idx - activeIdx).abs() > 1;
    });

    final needFetch = <String>[];
    final prevId = _neighborId(activeIdx - 1);
    final nextId = _neighborId(activeIdx + 1);
    if (prevId != null && getByChapterId(prevId) == null) {
      needFetch.add(prevId);
    }
    if (nextId != null && getByChapterId(nextId) == null) {
      needFetch.add(nextId);
    }
    return needFetch;
  }

  /// 清除所有缓存（分页 + 累积高度）。
  void invalidateAll() {
    _cache.clear();
    _inflight.clear();
    _contentCache.clear();
    _activeChapterId = null;
  }

  /// 用新 settings 重新计算指定章节的累积高度，并重新映射缓存 key。
  ///
  /// 字体/行高变更时调用，避免清空缓存导致触发完整的章节重载。
  void rekeyAndRecomputeHeights(
    String chapterId,
    double pageWidth,
    ReaderViewSettings newSettings,
    double textScale, {
    bool prepareScrollLayout = true,
  }) {
    // 找到旧条目（任意 settings 版本）
    ChapterData? data;
    _CacheKey? oldKey;
    for (final entry in _cache.entries) {
      if (entry.key.chapterId == chapterId) {
        data = entry.value;
        oldKey = entry.key;
        break;
      }
    }
    if (data == null || oldKey == null) return;

    data.updateCumulativeHeights(
      prepareScrollLayout
          ? _computeCumulativeHeights(
            data.blocks,
            pageWidth,
            newSettings,
            textScale,
          )
          : const <double>[],
    );

    // 失效分页导航器（旧 settings 的闭包已过期）
    data.invalidatePageNavigator();

    // 重新映射 key（旧 key → 新 key）
    final newKey = _key(chapterId, newSettings);
    if (oldKey != newKey) {
      _cache.remove(oldKey);
      _cache[newKey] = data;
    }
  }

  List<double> _computeCumulativeHeights(
    List<ContentBlock> blocks,
    double pageWidth,
    ReaderViewSettings settings,
    double textScale,
  ) {
    final heights = <double>[];
    var cumulative = 0.0;
    for (final block in blocks) {
      cumulative += ReaderPaginationEngine.measureBlockHeight(
        block,
        pageWidth,
        settings,
        textScale: textScale,
      );
      heights.add(cumulative);
    }
    return heights;
  }

  int _chapterIndex(String id) => allChapters.indexWhere((c) => c.id == id);

  String? _neighborId(int idx) =>
      idx >= 0 && idx < allChapters.length ? allChapters[idx].id : null;

  /// 字符偏移 → 像素偏移（用于从服务端/本地恢复滚动位置）。
  ///
  /// 遍历 blocks 累加字符数，找到 [charOffset] 落在哪个 block，
  /// 返回该 block 起始位置的像素偏移（基于 [cumulativeHeights]）。
  /// 如果 charOffset 超出范围，返回 maxExtent。
  /// 字符偏移 → 像素偏移（用于模式切换时恢复滚动位置）。
  ///
  /// 文本块使用 TextPainter 精确测量块内高度，与分页引擎同一套逻辑。
  /// [pageWidth]、[settings]、[textScale] 用于 TextPainter 测量。
  double charOffsetToPixelOffset(
    String chapterId,
    int charOffset, {
    required double pageWidth,
    required ReaderViewSettings settings,
    double textScale = 1.0,
  }) {
    final data = getByChapterId(chapterId);
    if (data == null || data.blocks.isEmpty) return 0;
    if (charOffset <= 0) return 0;
    if (charOffset >= data.totalChars) {
      return data.cumulativeHeights.isEmpty ? 0 : data.cumulativeHeights.last;
    }
    // 二分定位 charOffset 所在块（字符前缀表），替代逐块线性累加。
    final prefixes = data.blockCharPrefixes;
    var lo = 0;
    var hi = data.blocks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (prefixes[mid + 1] <= charOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final accumulated = prefixes[lo];
    // charOffset 落在这个 block 内
    final blockStart = lo > 0 ? data.cumulativeHeights[lo - 1] : 0.0;
    final charOffsetInBlock = charOffset - accumulated;
    // 用 TextPainter 精确测量块内高度（与分页引擎同一套逻辑）
    final heightInBlock = ReaderPaginationEngine.measureHeightToCharOffset(
      data.blocks[lo],
      pageWidth,
      settings,
      charOffsetInBlock,
      textScale: textScale,
      blockGlobalOffset: accumulated,
      isContinuation: false,
    );
    return blockStart + heightInBlock;
  }

  /// 内容坐标 Y → 字符偏移（用于保存阅读进度）。
  ///
  /// [contentY] 是内容坐标系中的 Y 位置（scrollOffset + viewportAnchorY）。
  /// 与 [charOffsetToContentY] 互为逆运算，使用同一套累积块高度坐标系。
  int contentYToCharOffset(
    String chapterId,
    double contentY, {
    required double pageWidth,
    ReaderViewSettings? settings,
    double textScale = 1.0,
  }) {
    final data = getByChapterId(chapterId);
    if (data == null || data.blocks.isEmpty) return 0;
    if (data.cumulativeHeights.isEmpty) return 0;

    final totalHeight = data.cumulativeHeights.last;
    if (totalHeight <= 0) return 0;

    // 直接用 contentY（不再通过 maxExtent 换算比例）
    final normalizedOffset = contentY.clamp(0.0, totalHeight);

    // 二分查找 normalizedOffset 落在哪个 block 的累积高度区间内
    var lo = 0;
    var hi = data.cumulativeHeights.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (data.cumulativeHeights[mid] < normalizedOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    // lo 是 normalizedOffset 落入的 block 索引
    // 前缀表 O(1) 取前 lo 个 block 的字符数
    var charOffset = data.blockCharPrefixes[lo];

    // 在 block 内：用 TextPainter 视觉行测量精确计算（与 charOffsetToContentY 互逆）
    final blockHeight = _blockHeightAt(data, lo);
    if (blockHeight > 0 && settings != null) {
      final blockStart = lo > 0 ? data.cumulativeHeights[lo - 1] : 0;
      final offsetInBlock = normalizedOffset - blockStart;
      final block = data.blocks[lo];
      final blockChars = _blockCharCount(block);

      if (blockChars > 0 &&
          block is! ImageBlock &&
          block is! DividerBlock &&
          block is! TableBlock &&
          block is! HeadingBlock) {
        // 文本块：用视觉行测量精确查找 charOffset
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
              // 目标在当前视觉行内
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
              return charOffset.clamp(0, data.totalChars);
            }
            accumulated += vl.height;
          }
          // 超出所有视觉行，返回块末尾
          charOffset += blockChars;
          return charOffset.clamp(0, data.totalChars);
        }
      }

      // 非文本块或视觉行为空：线性插值
      if (blockChars > 0) {
        final progressInBlock = (offsetInBlock / blockHeight).clamp(0.0, 1.0);
        charOffset += (progressInBlock * blockChars).round();
      }
    }

    return charOffset.clamp(0, data.totalChars);
  }

  /// 获取指定 block 的高度（非累积）。
  double _blockHeightAt(ChapterData data, int index) {
    if (index < 0 || index >= data.cumulativeHeights.length) return 0;
    final cumulative = data.cumulativeHeights[index];
    final previous = index > 0 ? data.cumulativeHeights[index - 1] : 0;
    return cumulative - previous;
  }
}

/// 单块字符数：与 `_ReaderPaginationTextLayout.blockCharCount` 同一口径
/// 的顶层实现，供 ChapterData 前缀表与 ReaderContentLoader 共用。
int _blockCharCount(ContentBlock block) {
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
