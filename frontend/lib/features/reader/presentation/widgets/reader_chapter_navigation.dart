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

  /// 定位到 EPUB 内部锚点。
  anchor,
}

/// 一次章节导航的确定性意图。
class ReaderChapterNavigationIntent {
  const ReaderChapterNavigationIntent._(
    this.entryPoint, {
    this.charOffset,
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
  final String? anchorHref;

  /// 是否为用户提供返回跳转前位置的入口。
  final bool offerReturn;

  /// 路由 entry 查询参数 → 初始导航意图。
  ///
  /// `chapter` 表示用户从目录显式选章，进入目标章章首，不得被
  /// 「全局最新进度在其他章」的续读 defer 劫持；其余值（含 null）
  /// 一律按续读语义恢复。
  static ReaderChapterNavigationIntent intentForRouteEntry(String? entry) {
    if (entry == 'chapter') {
      return const ReaderChapterNavigationIntent.start();
    }
    return const ReaderChapterNavigationIntent.resume();
  }
}
