/// 章节进入位置。
enum ReaderChapterEntryPoint {
  /// 首次打开阅读器时恢复最后阅读位置。
  resume,

  /// 从章节开头开始阅读。
  start,

  /// 从章节末尾开始阅读。
  end,

  /// 定位到明确的字符偏移。
  offset,

  /// 定位到章内比例（底栏进度条拖拽）。
  proportion,

  /// 定位到 EPUB 内部锚点。
  anchor,
}

/// 一次章节导航的确定性意图。
class ReaderChapterNavigationIntent {
  const ReaderChapterNavigationIntent._(
    this.entryPoint, {
    this.charOffset,
    this.chapterRatio,
    this.anchorHref,
    this.offerReturn = false,
  });

  /// 首次进入阅读器时恢复最后阅读位置。
  const ReaderChapterNavigationIntent.resume()
    : this._(ReaderChapterEntryPoint.resume);

  /// 从章节开头进入。
  const ReaderChapterNavigationIntent.start({bool offerReturn = false})
    : this._(ReaderChapterEntryPoint.start, offerReturn: offerReturn);

  /// 从章节末尾进入。
  ///
  /// 回退到上一章属于跳转行为，[offerReturn] 为 true 时提供
  /// "回到原进度"浮层。
  const ReaderChapterNavigationIntent.end({bool offerReturn = false})
    : this._(ReaderChapterEntryPoint.end, offerReturn: offerReturn);

  /// 从明确字符偏移进入。
  const ReaderChapterNavigationIntent.offset(
    int charOffset, {
    bool offerReturn = false,
  }) : this._(
         ReaderChapterEntryPoint.offset,
         charOffset: charOffset,
         offerReturn: offerReturn,
       );

  /// 从章内比例进入（底栏进度条拖拽）。
  ///
  /// 全书比例的分母是服务端清单字符数，而落位用的是客户端块字符域：跨章时目标章
  /// 还没解析，只能把比例带过去，由内容加载完成后按当章 painted 字符数换算。
  const ReaderChapterNavigationIntent.proportion(
    double chapterRatio, {
    bool offerReturn = false,
  }) : this._(
         ReaderChapterEntryPoint.proportion,
         chapterRatio: chapterRatio,
         offerReturn: offerReturn,
       );

  /// 从 EPUB 内部锚点进入。
  const ReaderChapterNavigationIntent.anchor(
    String? anchorHref, {
    bool offerReturn = false,
  }) : this._(
         ReaderChapterEntryPoint.anchor,
         anchorHref: anchorHref,
         offerReturn: offerReturn,
       );

  final ReaderChapterEntryPoint entryPoint;
  final int? charOffset;

  /// [ReaderChapterEntryPoint.proportion] 的章内比例（0.0-1.0）。
  final double? chapterRatio;
  final String? anchorHref;

  /// 是否为用户提供返回跳转前位置的入口。
  final bool offerReturn;

  /// 路由 entry 查询参数 → 初始导航意图。
  ///
  /// `chapter` 表示用户从目录显式选章，进入目标章章首，不得被
  /// 「全局最新进度在其他章」的续读 defer 劫持；`offset` 配合
  /// [charOffset] 表示从书签等精确定位进入；其余值（含 null）
  /// 一律按续读语义恢复。
  static ReaderChapterNavigationIntent intentForRouteEntry(
    String? entry, {
    int? charOffset,
  }) {
    if (entry == 'offset' && charOffset != null && charOffset > 0) {
      return ReaderChapterNavigationIntent.offset(charOffset);
    }
    if (entry == 'chapter') {
      return const ReaderChapterNavigationIntent.start();
    }
    return const ReaderChapterNavigationIntent.resume();
  }
}
