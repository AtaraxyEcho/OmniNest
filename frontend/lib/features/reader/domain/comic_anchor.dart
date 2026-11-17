/// 漫画阅读锚点 — 统一的阅读位置表示。
///
/// 翻页/滚动模式切换、进度保存/恢复、分包合并后都以此为唯一真相。
/// 不使用 progressPercent 参与定位，它只做 UI 展示。
class ComicAnchor {
  const ComicAnchor({
    required this.pageId,
    required this.pageIndex,
    this.pageFingerprint,
    this.sourceId,
    this.sourcePageIndex,
    this.catalogKey,
    this.intraPageOffset = 0.0,
    this.manifestVersion = 1,
  });

  /// 页面 ID（最稳定的锚点）。
  final String pageId;

  /// 页面索引（当 pageId 找不到时的 fallback）。
  final int pageIndex;

  /// 页面指纹（目录变更后仍可定位）。
  final String? pageFingerprint;

  /// 来源文件 ID。
  final String? sourceId;

  /// 页面在来源文件内的索引。
  final int? sourcePageIndex;

  /// 页面所属目录键。
  final String? catalogKey;

  /// 页内偏移（0.0-1.0，滚动模式用）。
  final double intraPageOffset;

  /// 清单版本号（版本不一致时降级用 fingerprint/pageIndex）。
  final int manifestVersion;

  /// 创建一个修改了 intraPageOffset 的副本。
  ComicAnchor withIntraPageOffset(double offset) {
    return ComicAnchor(
      pageId: pageId,
      pageIndex: pageIndex,
      pageFingerprint: pageFingerprint,
      sourceId: sourceId,
      sourcePageIndex: sourcePageIndex,
      catalogKey: catalogKey,
      intraPageOffset: offset,
      manifestVersion: manifestVersion,
    );
  }

  @override
  String toString() =>
      'ComicAnchor(pageId=$pageId, pageIndex=$pageIndex, '
      'intra=${intraPageOffset.toStringAsFixed(3)})';
}
