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

  /// 下一页的计算起点。
  int get nextCursor => cursorEnd >= 0 ? cursorEnd : endCharOffset;

  int get length => endIndex - startIndex;
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
