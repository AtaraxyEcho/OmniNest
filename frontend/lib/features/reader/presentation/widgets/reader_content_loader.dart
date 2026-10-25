import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_block_text.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

part 'reader_content_loader_page_navigator.dart';
part 'reader_content_loader_models.dart';

/// 滚动模式的高度表是否已不属于当前排版参数。
///
/// 未记录过参数（-1）同样算过期：那张表不是在当前列宽下测出来的。
bool scrollMetricsStale({
  required double tablePageWidth,
  required double tableTextScale,
  required double pageWidth,
  required double textScale,
}) {
  // 列宽用与翻页导航器同一档容差：桌面自由缩放时窗口宽度每帧抖动零点几像素，
  // 精确相等判定会让整表反复作废重排。文字缩放是倍率，容差要小一个量级。
  return (tablePageWidth - pageWidth).abs() >= _layoutWidthTolerance ||
      (tableTextScale - textScale).abs() >= _layoutScaleTolerance;
}

/// 布局参数比较容差：列宽按像素，文字缩放按倍率。
const _layoutWidthTolerance = 0.5;
const _layoutScaleTolerance = 0.01;

/// 单章分页数据。
///
/// slices 和 cumulativeHeights 为内部状态，
/// 仅通过 ReaderContentLoader 的方法修改。
class ReaderContentLoader {
  ReaderContentLoader({required this.allChapters});

  final List<ReaderChapter> allChapters;
  final Map<_CacheKey, ChapterData> _cache = {};
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
      followBookTypesetting: settings.followBookTypesetting,
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
    var anchors = const <String, int>{};
    // isolate 只做 HTML 解析（parseBlocks 纯 Dart 代码，无 Flutter 依赖）
    // TextPainter 不能在 isolate 中使用（继承 NativeFieldWrapperClass2）
    // Web 平台 compute 返回 JSArray，无法转为 Dart List，直接调用
    if (isLarge && !kIsWeb) {
      final parsed = await compute(parseChapterPayload, (
        html: content.content,
        css: content.stylesheetCss,
      ));
      blocks = parsed.blocks;
      anchors = parsed.anchors;
    } else {
      final parsed = parseChapterPayload((
        html: content.content,
        css: content.stylesheetCss,
      ));
      blocks = parsed.blocks;
      anchors = parsed.anchors;
    }

    // 如果 HTML 解析无 blocks，用纯文本创建段落块（兜底）
    if (blocks.isEmpty && content.content.trim().isNotEmpty) {
      if (kDebugMode) {
        readerDebugLog(
          'ReaderContentLoader: parseBlocks returned empty, creating fallback paragraph',
        );
      }
      // 兜底文本必须走 stripHtml：书的样式表可能以内联 `<style>` 写在章节正文里
      // （EPUB 的外部表已改走书级池，不再进正文），只剥标签会把整份 CSS 留在
      // 正文里渲染，章字符数也被撑大。
      final plainText = stripHtml(content.content);
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
      anchors: anchors,
      totalChars: blocks.fold(
        0,
        (sum, b) => sum + BlockClipper.blockCharCount(b),
      ),
    );
  }

  void _prepareScrollMetricsIfNeeded(
    ChapterData data, {
    required bool prepareScrollLayout,
    required double pageWidth,
    required ReaderViewSettings settings,
    required double textScale,
  }) {
    if (!prepareScrollLayout) {
      return;
    }
    // 邻章预取停在估算上即可，否则每翻一章要多跑两章的全量 TextPainter。
    // 尚未确定当前章（首帧或缓存全清后）时不做抑制，保证单独使用 loader
    // 的场景也会收敛到精测高度。
    final activeChapterId = _activeChapterId;
    final isMeasuredChapter =
        activeChapterId == null || data.chapterId == activeChapterId;
    final layoutStale =
        data.cumulativeHeights.isEmpty ||
        scrollMetricsStale(
          tablePageWidth: data.scrollLayoutPageWidth,
          tableTextScale: data.scrollLayoutTextScale,
          pageWidth: pageWidth,
          textScale: textScale,
        );
    if (!layoutStale) {
      // 表已属于当前排版却只是估算（预取时填的那张）：成为当前章后必须补一轮
      // 精测，否则顺序通读全程按均值算进度与落点，确定高度也永远不生效。
      if (isMeasuredChapter && !data.hasPreciseHeights) {
        unawaited(
          _runPrecisePass(
            data,
            pageWidth: pageWidth,
            settings: settings,
            textScale: textScale,
          ),
        );
      }
      return;
    }
    if (data.cumulativeHeights.isNotEmpty) {
      // 列宽或文字缩放变了：旧表整张作废。抬代次必须走 cancelPrecisePass，
      // 否则在途句柄仍指向旧参数那一轮，新一轮会直接复用它并立刻早退。
      data.cancelPrecisePass();
      data.measuredThrough = 0;
      data.updateCumulativeHeights(const []);
      data.invalidatePageNavigator();
    }
    data.markScrollLayout(pageWidth, textScale);
    final blocks = data.blocks;
    // 当前章且块数在同步预算内：首帧一次测完整章。估算尾部会让首次落点按
    // 均值偏一次、再由恢复监控期修正，而条目确定高度本来也要等整章精测才
    // 可用；块数很多时仍走"估算立即发布＋精测分批让帧"，同步测完整章会
    // 冻结 UI 数百毫秒到秒级。
    if (isMeasuredChapter && blocks.length <= _syncFullMeasureBlocks) {
      data.updateCumulativeHeights(
        _computeCumulativeHeights(blocks, pageWidth, settings, textScale),
      );
      data.measuredThrough = blocks.length;
      data.markPreciseHeights();
      return;
    }
    // 第一阶段：精确测量头部若干块，以平均块高估算整章，立即填充
    // cumulative 数组，保证滚动映射从首帧起无空洞。
    // 估算基线优先取已精测章节的分块型高度均值（同书排版一致），
    // 降低 estimate→precise 转换时的窗口高度跳变。
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
    final typeAverages = _measuredBlockAverages(
      pageWidth: pageWidth,
      textScale: textScale,
    );
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
    if (isMeasuredChapter) {
      unawaited(
        _runPrecisePass(
          data,
          pageWidth: pageWidth,
          settings: settings,
          textScale: textScale,
        ),
      );
    }
  }

  /// 确保本章高度已精测：返回在途或新建的精测任务，重复调用共享同一任务。
  ///
  /// 旧实现对每帧轮询都重排一整轮（并把上一轮在批次边界杀死、从第 0 块重来），
  /// 两轮互相杀死导致净前进为零，恢复落位必然撞到总超时。
  Future<void> ensurePreciseHeights({
    required String chapterId,
    required double pageWidth,
    required ReaderViewSettings settings,
    required double textScale,
  }) {
    final data = get(chapterId, settings);
    if (data == null || data.blocks.isEmpty || data.hasPreciseHeights) {
      return Future<void>.value();
    }
    return _runPrecisePass(
      data,
      pageWidth: pageWidth,
      settings: settings,
      textScale: textScale,
    );
  }

  /// 第二阶段：分批精确测量并替换估算值（可续测、单飞）。
  ///
  /// 每批让出一帧；仅当代次或 heights 数组身份变化（切章、设置重算、
  /// rekey 替换）才中止，且中止时保留已测前缀与续测位置，下次接着测。
  Future<void> _runPrecisePass(
    ChapterData data, {
    required double pageWidth,
    required ReaderViewSettings settings,
    required double textScale,
  }) {
    final running = data.precisePass;
    if (running != null) {
      return running;
    }
    final pass = _measureHeights(
      data,
      pageWidth: pageWidth,
      settings: settings,
      textScale: textScale,
    );
    data.precisePass = pass;
    return pass.whenComplete(() {
      if (identical(data.precisePass, pass)) {
        data.precisePass = null;
      }
    });
  }

  Future<void> _measureHeights(
    ChapterData data, {
    required double pageWidth,
    required ReaderViewSettings settings,
    required double textScale,
  }) async {
    final generation = ++data.heightsGeneration;
    final blocks = data.blocks;
    // 以现有高度表为基线（phase-one 估算或部分精测），逐块用实测覆盖：
    // 分批发布的中间态保持单调且 totalHeight 恒有效，避免
    // 「前缀实测 + 尾部全 0」窗口期内进度映射归零。
    final heights =
        data.cumulativeHeights.length == blocks.length
            ? List<double>.of(data.cumulativeHeights)
            : List<double>.filled(blocks.length, 0);
    var cumulative = 0.0;
    final start = data.measuredThrough.clamp(0, blocks.length);
    for (var i = 0; i < start; i++) {
      cumulative = heights[i];
    }
    for (var i = start; i < blocks.length; i++) {
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
        // 先校验代次再发布：作废之后还写一整批旧参数高度，会把新表的起点数值
        // 与 cumulative 基线一起带歪，而且那段下标永远不会再重测。
        if (generation != data.heightsGeneration) {
          return;
        }
        data.updateCumulativeHeights(heights);
        // 进度只在真正发布后推进：未发布的测量不算"已精测到"，否则中断后
        // 续测会从这段从未落表的下标接着走，把它们当估算之外的既成事实。
        data.measuredThrough = i + 1;
        await Future<void>.delayed(Duration.zero);
        if (generation != data.heightsGeneration ||
            !identical(data.cumulativeHeights, heights)) {
          return;
        }
      }
    }
    data.markPreciseHeights();
  }

  /// 从首个已精测章节提取各块类型的平均高度，供邻章 phase-one 估算。
  ///
  /// 同一书排版一致，跨章块型均值比仅头部块实测更接近全章真实均值；
  /// 无已精测章节时返回 null，调用方退回头部均值。
  Map<Type, double>? _measuredBlockAverages({
    required double pageWidth,
    required double textScale,
  }) {
    for (final data in _cache.values) {
      if (!data.hasPreciseHeights || data.blocks.isEmpty) {
        continue;
      }
      // 均值只能来自同一套排版参数：旧列宽测出的表会让新章尾部估算整体偏小。
      if (scrollMetricsStale(
        tablePageWidth: data.scrollLayoutPageWidth,
        tableTextScale: data.scrollLayoutTextScale,
        pageWidth: pageWidth,
        textScale: textScale,
      )) {
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
        // 零高块（空段等）不参与均值，否则会把该类型的估算整体拉低。
        if (height <= 0) {
          continue;
        }
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
  /// 计算结果本身就是逐块实测，因此直接标记为已精测：旧实现只
  /// `updateCumulativeHeights`（该入口一律视为未精测），于是下一次恢复
  /// 又触发整章重测，把刚同步测完的一整章再测一遍。
  /// 块数很多时不同步测完整章（会冻结 UI 数百毫秒到秒级），
  /// 改为按 phase-one 估算立即发布、精测分批让帧。
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

    // 旧 settings 下在途的精测必须作废：继续测会把过期高度写进新表。
    data.cancelPrecisePass();
    data.measuredThrough = 0;
    data.markScrollLayout(pageWidth, textScale);

    if (!prepareScrollLayout) {
      data.updateCumulativeHeights(const <double>[]);
    } else if (data.blocks.length > _syncFullMeasureBlocks) {
      data.updateCumulativeHeights(
        _estimateCumulativeHeights(data, pageWidth, newSettings, textScale),
      );
      unawaited(
        _runPrecisePass(
          data,
          pageWidth: pageWidth,
          settings: newSettings,
          textScale: textScale,
        ),
      );
    } else {
      data.updateCumulativeHeights(
        _computeCumulativeHeights(
          data.blocks,
          pageWidth,
          newSettings,
          textScale,
        ),
      );
      data.measuredThrough = data.blocks.length;
      data.markPreciseHeights();
    }

    // 失效分页导航器（旧 settings 的闭包已过期）
    data.invalidatePageNavigator();

    // 重新映射 key（旧 key → 新 key）
    final newKey = _key(chapterId, newSettings);
    if (oldKey != newKey) {
      _cache.remove(oldKey);
      _cache[newKey] = data;
    }
  }

  /// 头部精测＋按块型均值估算的整章高度表（与 phase-one 同一策略）。
  List<double> _estimateCumulativeHeights(
    ChapterData data,
    double pageWidth,
    ReaderViewSettings settings,
    double textScale,
  ) {
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
    final result = List<double>.filled(blocks.length, 0);
    var running = 0.0;
    for (var i = 0; i < blocks.length; i++) {
      running +=
          i < headCount
              ? headHeights[i] - (i == 0 ? 0.0 : headHeights[i - 1])
              : estimateBase;
      result[i] = running;
    }
    return result;
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
    // 同一章在缓存里按排版参数各有一份；只按 chapterId 取会拿旧字号的高度表
    // 与新 settings 混算，模式切换时的滚动位置就会落到别的行上。
    final data = get(chapterId, settings) ?? getByChapterId(chapterId);
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
    final block = data.blocks[lo];
    // 用 TextPainter 精确测量块内高度（与分页引擎同一套逻辑）
    final heightInBlock = ReaderPaginationEngine.measureHeightToCharOffset(
      block,
      pageWidth,
      settings,
      charOffsetInBlock,
      textScale: textScale,
      blockGlobalOffset: accumulated,
      isContinuation: false,
    );
    // 渲染侧把块顶留白（段前留白、引用盒上内缩）画在第一行文字之前：
    // 不收这一份，块起点到首行之间差的那一截会让换算落在上一条文字上。
    // 列表等整块口径的非文本块，measureHeightToCharOffset 返回的块高已含这份留白。
    final leading =
        _hasLineFlowChrome(block)
            ? ReaderContentBlockItem.blockLeadingChrome(block, settings)
            : 0.0;
    return blockStart + leading + heightInBlock;
  }

  /// 块内按视觉行累加定位的文本块：只有这些块需要单独收块顶留白。
  static bool _hasLineFlowChrome(ContentBlock block) =>
      block is ParagraphBlock || block is BlockquoteBlock;

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
    // 与 charOffsetToPixelOffset 同一把尺：先按当前排版参数精确命中缓存，
    // 命中不到才退回按章找，避免用旧字号的高度表解释新的 contentY。
    final data =
        (settings != null ? get(chapterId, settings) : null) ??
        getByChapterId(chapterId);
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
      final blockChars = BlockClipper.blockCharCount(block);

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
          // 累积起点是块顶留白之后，不是块顶：段前留白画在第一行文字之前，
          // 从 0 起算会让整块的行号向下错一格，落在这个块里的进度因此少读一行。
          var accumulated =
              _hasLineFlowChrome(block)
                  ? ReaderContentBlockItem.blockLeadingChrome(block, settings)
                  : 0.0;
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
