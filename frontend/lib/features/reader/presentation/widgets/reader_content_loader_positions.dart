part of 'reader_content_loader.dart';

/// 字符偏移与像素偏移互算（从 ReaderContentLoader 主体拆出）。
extension ReaderContentLoaderPositions on ReaderContentLoader {
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
}
