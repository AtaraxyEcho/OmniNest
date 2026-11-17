/// 单页切片：表示一个页面包含的 ContentBlock 范围。
///
/// [startIndex]/[endIndex] 为块级范围。
/// [startLine]/[endLine] 为块内行级范围，支持段落内精确切割：
/// - [startLine] > 0：起始块从该行开始
/// - [endLine] >= 0：结束块到该行结束（不含）
/// - [endLine] == -1（默认）：包含结束块的所有行
///
/// [startCharOffset]/[endCharOffset] 为章节全文字符偏移，
/// 用于进度保存/恢复和未来的字符级渲染裁剪。
class PageSlice {
  const PageSlice({
    required this.startIndex,
    required this.endIndex,
    this.startLine = 0,
    this.endLine = -1,
    this.startCharOffset = 0,
    this.endCharOffset = 0,
    this.cursorEnd = -1,
    this.accountedHeight = -1,
    this.chainContinueBlock = -1,
  });

  final int startIndex;
  final int endIndex;
  final int startLine;
  final int endLine;

  /// 本页起始字符在章节全文中的偏移。
  final int startCharOffset;

  /// 本页结束字符在章节全文中的偏移（不含）。
  final int endCharOffset;

  /// 链接下一页的游标偏移；负值表示与 [endCharOffset] 相同。
  ///
  /// 图片等零字符块在字符轴上宽度为 0，无法用真实字符偏移区分「图片页」
  /// 与「图片之后的页」。图片页的 [startCharOffset]/[endCharOffset] 保持
  /// 真实偏移（供进度保存与恢复），翻页游标则由 [cursorEnd] 指向图片之后，
  /// 保证页链能够继续推进且不吞掉后一段正文的首字符。
  final int cursorEnd;

  /// 零宽块链没能在这一页画完时，下一页要接着画的块索引；负值表示链已画完。
  ///
  /// 连续的图片与分隔线在字符轴上同宽（0），游标只能表示"链之前"和"链之后"，
  /// 表示不了"链里的第几张"。所以链被页高切成多页时，游标原地不动，续页位置
  /// 由这里带着——它不进字符域，进度、锚点与批注的偏移口径因此不受影响。
  final int chainContinueBlock;

  /// 下一页的计算起点。
  int get nextCursor => cursorEnd >= 0 ? cursorEnd : endCharOffset;

  /// 装页时算给这一页的高度（含已预扣的块间距）。
  ///
  /// 负值表示这一页不是逐行累计出来的（空章页）。逐行累计与渲染两侧对同一页各算
  /// 一次是两类不同的错误：预算算错要改装页，测量对不上要改测量口径，只有把引擎
  /// 算到的值一起带出来，回归才不用靠猜来判断锅在哪一侧。
  final double accountedHeight;

  int get length => endIndex - startIndex;
}

/// 翻页模式的显示页数 = 正文页数 + 章末收页。
///
/// 收页只在整章分页完成后挂上：正文页数是懒算的，未完成时把收页算进去，边界判定会
/// 以为已经到了章末，翻页手势提前把读者送进下一章。
int readerDisplayPageCount({
  required int contentPages,
  required bool fullyPaginated,
}) => fullyPaginated && contentPages > 0 ? contentPages + 1 : contentPages;

/// 第 [pageIndex] 页是不是章末收页（本章正文之外的最后一页）。
bool isReaderChapterEndPage({
  required int pageIndex,
  required int contentPages,
  required bool fullyPaginated,
}) => fullyPaginated && contentPages > 0 && pageIndex == contentPages;

/// 某一页在章节字符域里的位置：正文页取页首偏移，章末收页取本章末尾，越界页取 0。
///
/// 收页没有正文切片。若与"越界"一样记 0，读者在章末合上书就会被送回章首——
/// 进度与恢复两条通路都经由这里取值，两侧不会各写一份判据。
int readerPageCharOffset({
  required PageSlice? slice,
  required int pageIndex,
  required int contentPages,
  required bool fullyPaginated,
  required int totalChars,
}) {
  if (slice != null) return slice.startCharOffset;
  return isReaderChapterEndPage(
        pageIndex: pageIndex,
        contentPages: contentPages,
        fullyPaginated: fullyPaginated,
      )
      ? totalChars
      : 0;
}

/// 公开视觉行信息（供 ReaderContentLoader 使用）。
class VisualLineInfo {
  const VisualLineInfo({
    required this.globalStart,
    required this.globalEnd,
    required this.height,
  });

  final int globalStart;
  final int globalEnd;
  final double height;
}

/// 分页引擎内部使用的平铺行引用。
class PaginationLineRef {
  const PaginationLineRef({
    required this.blockIndex,
    required this.lineIndex,
    required this.isTextual,
    this.fixedHeight = 0,
  });

  final int blockIndex;
  final int lineIndex;
  final bool isTextual;
  final double fixedHeight;
}

/// 分页引擎测量得到的视觉行范围。
class PaginationVisualLine {
  const PaginationVisualLine({
    required this.globalStart,
    required this.globalEnd,
    required this.height,
  });

  final int globalStart;
  final int globalEnd;
  final double height;
}
