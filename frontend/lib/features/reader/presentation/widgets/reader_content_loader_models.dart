part of 'reader_content_loader.dart';

class ChapterData {
  ChapterData({
    required this.chapterId,
    required this.content,
    required this.blocks,
    List<PageSlice> slices = const [],
    List<double> cumulativeHeights = const [],
    this.totalChars = 0,
    this.anchors = const {},
  }) : _slices = slices,
       _cumulativeHeights = cumulativeHeights;

  final String chapterId;
  final ReaderChapterContent content;
  final List<ContentBlock> blocks;
  final int totalChars;

  /// 章内锚点（`id` / `name`）在字符域里的位置，与块偏移、页区间同一个口径。
  final Map<String, int> anchors;

  List<PageSlice> get slices => _slices;
  final List<PageSlice> _slices;

  List<double> get cumulativeHeights => _cumulativeHeights;
  List<double> _cumulativeHeights;

  List<int> _blockCharPrefixes = const [];

  ChapterSearchCorpus? _searchCorpus;

  /// 章内检索语料：面板给出的命中下标是可绘制文本位置，跳转前要经它换算到块源字符域。
  ///
  /// 与块内容同生命周期，惰性构建一次；块换章或重解析后 ChapterData 会重建，缓存自然失效。
  ChapterSearchCorpus get searchCorpus =>
      _searchCorpus ??= ChapterSearchCorpus.fromBlocks(blocks);

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
  bool? _navigatorFollowBookTypesetting;

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
        _navigatorTextScale != textScale ||
        // 「跟随原书排版」改变段距、对齐与行高：漏这一项时同一份页链会被当成
        // 还是旧排版算出来的那些页，翻页按书的版式落位、装页按读者的默认档。
        _navigatorFollowBookTypesetting != settings.followBookTypesetting;
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
        computeFn: pageLayout.computeNextPage,
      );
    }
    _navigatorPageWidth = pageWidth;
    _navigatorPageHeight = pageHeight;
    _navigatorFontSize = settings.fontSize;
    _navigatorLineHeight = settings.lineHeight;
    _navigatorFontFamily = settings.fontFamily;
    _navigatorTextScale = textScale;
    _navigatorFollowBookTypesetting = settings.followBookTypesetting;
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
    _navigatorFollowBookTypesetting = null;
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

  /// 书的排版意图参与块高与装页，所以它也是缓存键的一维：
  /// 少了这一维，打开或关闭「跟随原书」会复用上一档测出来的高度表与页区间，
  /// 版面看着像没反应，实际是拿旧表在渲染。
  final bool followBookTypesetting;

  const _CacheKey({
    required this.chapterId,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.followBookTypesetting,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _CacheKey &&
          chapterId == other.chapterId &&
          fontSize == other.fontSize &&
          lineHeight == other.lineHeight &&
          fontFamily == other.fontFamily &&
          followBookTypesetting == other.followBookTypesetting);

  @override
  int get hashCode => Object.hash(
    chapterId,
    fontSize,
    lineHeight,
    fontFamily,
    followBookTypesetting,
  );
}
