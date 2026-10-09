import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

part 'reader_content_loader_page_navigator.dart';

/// 滚动列表条目相对块高的附加间距。
///
/// 标题块之后渲染层会多插一段间距（ReaderViewContent._buildBlock），
/// 高度表必须计同一份，否则条目实际高度与表按标题数累积偏离。
double scrollBlockExtraSpacing(ContentBlock block) =>
    block is HeadingBlock ? ReaderContentBlockItem.headingBottomSpacing : 0.0;

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
        prefixes[i + 1] = prefixes[i] + BlockClipper.blockCharCount(blocks[i]);
      }
      _blockCharPrefixes = prefixes;
    }
    return _blockCharPrefixes;
  }

  /// 滚动列表逐项确定高度；尚未整章精测时返回 null。
  ///
  /// 提供确定高度可让 maxScrollExtent 与"当前构建了哪些项"无关：懒构建的
  /// SliverList 会用已构建项均值外推未构建项，深位置恢复按虚高范围 jumpTo
  /// 后，范围随构建收缩会把落点钳到目标之前。itemExtentBuilder 不接受
  /// 空洞高度，因此只在整章测得后给出。
  ///
  /// 判据必须用精测标记而不是数组长度：估算填充同样是整章长度，把它当成
  /// 确定高度会强制未测尾部按均值占位——真实文本更高时被裁字，更矮时留白。
  List<double>? get blockExtents {
    if (!_hasPreciseHeights) return null;
    final heights = _cumulativeHeights;
    if (heights.isEmpty || heights.length != blocks.length) return null;
    final extents = List<double>.filled(heights.length, 0);
    var previous = 0.0;
    for (var i = 0; i < heights.length; i++) {
      extents[i] = heights[i] - previous;
      previous = heights[i];
    }
    return extents.every((extent) => extent >= 0) ? extents : null;
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

  /// 本表所依据的列宽与文字缩放；与之不符的表视为过期。
  ///
  /// 缓存键只含章节与字号/行高/字体，视口变化不会换键，因此宽度与缩放要
  /// 由表自身记账，否则换宽后条目实际高度与表不符，字符偏移↔像素映射整章偏。
  double scrollLayoutPageWidth = -1;
  double scrollLayoutTextScale = -1;

  /// 记录本表对应的列宽与文字缩放（仅限 ReaderContentLoader 调用）。
  void markScrollLayout(double pageWidth, double textScale) {
    scrollLayoutPageWidth = pageWidth;
    scrollLayoutTextScale = textScale;
  }

  /// 本章精测代次。
  ///
  /// 代次必须按章隔离：loader 级单一计数器会让邻章预取的每一次排批
  /// 都在批次边界杀死当前章的在途精测，当前章又因高度表非空不再重测，
  /// 于是整章永久停留在估算高度上，进度与恢复落点全部按估算计算。
  int heightsGeneration = 0;

  /// 已精测到的块下标（用于中断后续测，而不是从第 0 块重来）。
  int measuredThrough = 0;

  /// 在途精测任务。重复请求（例如恢复落位每帧轮询）必须等同一个任务，
  /// 不能再各起一轮互相杀死。
  Future<void>? precisePass;

  /// 作废在途精测：设置变更、缓存失效或重新排期前调用。
  void cancelPrecisePass() {
    heightsGeneration++;
    // 在途句柄必须一并释放：只抬代次的话，新一轮请求会复用这个注定早退的旧
    // 任务并立刻返回，新参数下反而再没人排精测，整章永久停在估算上。
    precisePass = null;
  }
}

/// 滚动模式测高分批参数：头部精确测量块数与每批测量块数。
const _metricsPhaseOneBlocks = 12;
const _metricsBatchBlocks = 40;

/// 允许同步测完整章的块数上限，超过则改走"估算＋分批精测"。
///
/// 章节首次准备滚动布局与设置变更重测共用该预算：同步测完整章会让首帧
/// 或改字号那一帧停住数百毫秒，只在块数足够小时才值得换掉估算窗口。
const _syncFullMeasureBlocks = 200;

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
      headCumulative +=
          ReaderPaginationEngine.measureBlockHeight(
            blocks[i],
            pageWidth,
            settings,
            textScale: textScale,
          ) +
          scrollBlockExtraSpacing(blocks[i]);
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
      cumulative +=
          ReaderPaginationEngine.measureBlockHeight(
            blocks[i],
            pageWidth,
            settings,
            textScale: textScale,
          ) +
          // 标题后的包装层间距同样占据滚动条目高度，不计入会让表比渲染矮。
          scrollBlockExtraSpacing(blocks[i]);
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
      headCumulative +=
          ReaderPaginationEngine.measureBlockHeight(
            blocks[i],
            pageWidth,
            settings,
            textScale: textScale,
          ) +
          scrollBlockExtraSpacing(blocks[i]);
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
      cumulative +=
          ReaderPaginationEngine.measureBlockHeight(
            block,
            pageWidth,
            settings,
            textScale: textScale,
          ) +
          // 标题后的包装层间距由列表条目实际占据，漏算会让整章表比渲染矮，
          // 且该入口标记为已精测后还直接决定条目确定高度。
          scrollBlockExtraSpacing(block);
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
