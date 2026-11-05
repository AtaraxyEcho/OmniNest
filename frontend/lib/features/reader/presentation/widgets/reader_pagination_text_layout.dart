part of 'reader_pagination_engine.dart';

/// 负责阅读文本的字符统计、视觉行测量与偏移映射。
abstract final class _ReaderPaginationTextLayout {
  static List<int> computeCumulativeCharOffsets(List<ContentBlock> blocks) {
    final offsets = List<int>.filled(blocks.length, 0);
    var cumulative = 0;
    for (var i = 0; i < blocks.length; i++) {
      offsets[i] = cumulative;
      cumulative += blockCharCount(blocks[i]);
    }
    return offsets;
  }

  /// 单块字符数：统一走 `BlockClipper.blockCharCount` 的**源文本空间**口径。
  ///
  /// 页区间、块前缀与共享视觉行测量器必须共处同一坐标系：折叠空白虽不可
  /// 绘制，却要计入页与页之间的区间，否则翻页会漏掉章尾字符，且同一
  /// charOffset 在滚动侧与翻页侧指向不同文本。
  static int blockCharCount(ContentBlock block) =>
      BlockClipper.blockCharCount(block);

  /// 清空静态视觉行测量缓存。
  ///
  /// 本类无实例状态，清空只影响跨调用的测量结果复用。供排版参数、字号
  /// 缩放或文本环境整体变化后由调用方显式触发（退出阅读页经
  /// `clearReaderPaginationCaches`），用于释放旧 blocks 与 settings 身份引用；
  /// 本文件内部不得调用，避免测量热路径缓存反复失效。
  static void clearCaches() {
    _visualLinesCache.clear();
  }

  static List<dynamic>? _getBlockLines(ContentBlock block) {
    return switch (block) {
      ParagraphBlock(:final lines) => lines,
      BlockquoteBlock(:final lines) => lines,
      ListBlock(:final items) => items,
      _ => null,
    };
  }

  /// 视觉行测量缓存：滚动热路径的 contentYToCharOffset 每帧对命中块
  /// 调用本方法，无缓存时每帧重建 TextPainter。键含 settings 值
  /// （排版参数，按字段比较而非身份：父层 copyWith 出等值实例不该击穿缓存）
  /// 与 blockGlobalOffset（块前缀，章内恒定）；LRU 上限 64 防内存增长。
  static final List<_VisualLinesCacheEntry> _visualLinesCache =
      <_VisualLinesCacheEntry>[];
  static const _visualLinesCacheLimit = 64;

  static List<VisualLineInfo> measureVisualLines(
    ContentBlock block,
    double pageWidth,
    ReaderViewSettings settings,
    double textScale, {
    required int blockGlobalOffset,
    bool isContinuation = false,
  }) {
    for (var i = 0; i < _visualLinesCache.length; i++) {
      final entry = _visualLinesCache[i];
      if (identical(entry.block, block) &&
          entry.pageWidth == pageWidth &&
          entry.settings == settings &&
          entry.textScale == textScale &&
          entry.blockGlobalOffset == blockGlobalOffset &&
          entry.isContinuation == isContinuation) {
        if (i != 0) {
          _visualLinesCache.removeAt(i);
          _visualLinesCache.insert(0, entry);
        }
        return entry.result;
      }
    }
    final internal = measureVisualLinesInternal(
      block,
      pageWidth,
      settings,
      textScale,
      blockGlobalOffset: blockGlobalOffset,
      isContinuation: isContinuation,
    );
    final result =
        internal
            .map(
              (line) => VisualLineInfo(
                globalStart: line.globalStart,
                globalEnd: line.globalEnd,
                height: line.height,
              ),
            )
            .toList();
    _visualLinesCache.insert(
      0,
      _VisualLinesCacheEntry(
        block: block,
        pageWidth: pageWidth,
        settings: settings,
        textScale: textScale,
        blockGlobalOffset: blockGlobalOffset,
        isContinuation: isContinuation,
        result: result,
      ),
    );
    while (_visualLinesCache.length > _visualLinesCacheLimit) {
      _visualLinesCache.removeLast();
    }
    return result;
  }

  static List<PaginationVisualLine> measureVisualLinesInternal(
    ContentBlock block,
    double pageWidth,
    ReaderViewSettings settings,
    double textScale, {
    required int blockGlobalOffset,
    bool isContinuation = false,
  }) {
    final lines = _getBlockLines(block);
    if (lines == null || lines.isEmpty) return [];

    final allSpans = <InlineSpan>[];
    final placeholderDimensions = <PlaceholderDimensions>[];
    final contentSegments = <_PainterContentSegment>[];
    var charAccum = blockGlobalOffset;
    var painterOffset = 0;

    // 逻辑行合并为单个 TextPainter 文本，插入段落缩进和换行。
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final List<ReaderInlineSpan> lineSpans;
      if (line is LineData) {
        lineSpans = line.spans;
      } else if (line is ListItemData) {
        lineSpans = line.spans;
      } else {
        lineSpans = [];
      }

      // 列表项不共享段落规则：渲染侧的"缩进位"是符号列，注入缩进会让首项比绘制
      // 多占两个字宽，同一块在两侧折出不同行数。
      final gap =
          block is ListBlock
              ? ParagraphLineGap(newLine: i > 0, indentChars: 0)
              : paragraphGap(
                isFirstLine: i == 0,
                isNewParagraph: line is LineData && line.isNewParagraph,
                previousLineIsEmpty:
                    i > 0 &&
                    lines[i - 1] is LineData &&
                    (lines[i - 1] as LineData).spans.isEmpty,
                isBlockContinuation: isContinuation,
                startsWithFullWidthIndent: lineStartsWithFullWidthIndent(
                  lineSpans,
                ),
                indentChars: settings.firstLineIndentChars(
                  line is LineData ? line.style : null,
                ),
                isSoftWrap: line is LineData && line.softWrap,
              );
      final indentWidth = settings.indentBoxWidth(
        indentChars: gap.indentChars,
        blockquote: block is BlockquoteBlock,
        textScale: textScale,
      );
      allSpans.addAll(paragraphGapSpans(gap, indentWidth: indentWidth));
      if (gap.indentChars > 0 && indentWidth > 0) {
        // TextPainter 不会替 WidgetSpan 量尺寸：必须把与绘制侧同一个宽度
        // 显式喂给它，否则 layout 直接断言失败。
        placeholderDimensions.add(
          PlaceholderDimensions(
            size: Size(indentWidth, 0),
            alignment: PlaceholderAlignment.bottom,
          ),
        );
      }
      // 缩进盒子在排版文本里只占一个 0xFFFC 码元，不占章节字符域的位置。
      painterOffset += gap.painterUnits;

      final renderedSpans =
          _ReaderPaginationMetrics.lineTextSpans(
            lineSpans,
            settings,
            textScale,
          ).toList();
      allSpans.addAll(renderedSpans);

      // 折叠字符有行首与行尾两份：行首那份让本行可绘制文本整体后移（`lineStart`），
      // 行尾那份不属于本行绘制，但占用源位置——不加进 charAccum，下一行的起点就会偏早，
      // 于是同一字符会在两页各画一次（页链铺贴出现重复）。
      final collapsedChars = line is LineData ? line.collapsedChars : 0;
      final trailingChars = line is LineData ? line.trailingCollapsedChars : 0;
      final lineStart = charAccum + collapsedChars;
      var lineLength = 0;
      for (final span in lineSpans) {
        lineLength += span.text.length;
      }
      var paintedLength = 0;
      for (final span in renderedSpans) {
        paintedLength += span.text?.length ?? 0;
      }
      if (lineLength > 0) {
        contentSegments.add(
          _PainterContentSegment(
            painterStart: painterOffset,
            painterEnd: painterOffset + paintedLength,
            globalStart: lineStart,
          ),
        );
      }
      painterOffset += paintedLength;
      charAccum += lineLength + collapsedChars + trailingChars;
    }

    if (allSpans.isEmpty) return [];

    final isQuote = block is BlockquoteBlock;
    // 行高倍率挂在块级样式上：绘制侧按同一份样式折行，两侧必须一起放大。
    final lineHeightScale = settings.lineHeightScaleFor(switch (block) {
      ParagraphBlock(:final style) => style,
      BlockquoteBlock(:final style) => style,
      _ => null,
    });
    final innerWidth = switch (block) {
      // 稿子的强调条是叠在左内缩槽里的浮层，不占文字宽度：只扣 22 的左内缩。
      // 以前按 `Border.left` 实现时要连条一起扣，改成叠层后仍扣就会多算一行。
      BlockquoteBlock() =>
        pageWidth - ReaderContentBlockItem.blockquoteInnerLeftPadding,
      ListBlock() => pageWidth - ReaderContentBlockItem.listMarkerColumnWidth,
      _ => pageWidth,
    };

    final painter =
        TextPainter(
            text: TextSpan(
              children: allSpans,
              // 引用块比正文大 1px、行高固定 1.75：绘制用这一份，测量也必须用这一份。
              style:
                  isQuote
                      ? settings.blockquoteStyle(
                        textScale: textScale,
                        lineHeightScale: lineHeightScale,
                      )
                      : settings.measurementBaseStyle(
                        textScale: textScale,
                        lineHeightScale: lineHeightScale,
                      ),
            ),
            strutStyle:
                isQuote
                    ? settings.blockquoteStrutStyle(
                      textScale: textScale,
                      lineHeightScale: lineHeightScale,
                    )
                    : settings.bodyStrutStyle(
                      textScale: textScale,
                      lineHeightScale: lineHeightScale,
                    ),
            textDirection: TextDirection.ltr,
            maxLines: null,
          )
          ..setPlaceholderDimensions(
            placeholderDimensions.isEmpty ? null : placeholderDimensions,
          )
          ..layout(maxWidth: innerWidth);

    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) return [];
    final lineTops = [
      for (final metric in metrics) metric.baseline - metric.ascent,
    ];
    final lineHeights = _ReaderPaginationMetrics.lineHeightsFromTops(
      lineTops,
      painter.height,
    );

    // 将每条视觉行的像素边界转换回章节字符范围。
    final result = <PaginationVisualLine>[];
    var segmentCursor = 0;
    // 空白视觉行（`<pre>` 里的 `\n\n`）没有字符可映射，但仍然占一个行高：
    // 块高由各行高度累加得出，把它们整行丢掉会让测量比渲染少 N 行，
    // 紧约束的列表条目直接报 RenderFlex overflow，翻页模式下页底还会裁字。
    var pendingEmptyHeight = 0.0;
    for (var lineIndex = 0; lineIndex < metrics.length; lineIndex++) {
      final top = lineTops[lineIndex];
      final probePosition = painter.getPositionForOffset(
        Offset(0, top + lineHeights[lineIndex] / 2),
      );
      final lineBoundary = painter.getLineBoundary(probePosition);
      final painterStart = lineBoundary.start.clamp(0, painterOffset);
      final painterEnd = lineBoundary.end.clamp(0, painterOffset);

      if (painterStart >= painterEnd) {
        pendingEmptyHeight += lineHeights[lineIndex];
        continue;
      }

      while (segmentCursor < contentSegments.length &&
          contentSegments[segmentCursor].painterEnd <= painterStart) {
        segmentCursor++;
      }

      int? globalStart;
      int? globalEnd;
      for (var index = segmentCursor; index < contentSegments.length; index++) {
        final segment = contentSegments[index];
        if (segment.painterStart >= painterEnd) {
          break;
        }
        final overlapStart = math.max(painterStart, segment.painterStart);
        final overlapEnd = math.min(painterEnd, segment.painterEnd);
        if (overlapStart >= overlapEnd) {
          continue;
        }
        globalStart ??=
            segment.globalStart + overlapStart - segment.painterStart;
        globalEnd = segment.globalStart + overlapEnd - segment.painterStart;
      }

      if (globalStart == null || globalEnd == null) continue;
      if (globalEnd <= globalStart) globalEnd = globalStart + 1;

      result.add(
        PaginationVisualLine(
          globalStart: globalStart,
          globalEnd: globalEnd,
          height: lineHeights[lineIndex] + pendingEmptyHeight,
        ),
      );
      pendingEmptyHeight = 0;
    }
    if (pendingEmptyHeight > 0 && result.isNotEmpty) {
      final tail = result.removeLast();
      result.add(
        PaginationVisualLine(
          globalStart: tail.globalStart,
          globalEnd: tail.globalEnd,
          height: tail.height + pendingEmptyHeight,
        ),
      );
    }

    return result;
  }
}

/// 释放分页引擎的章节级静态缓存：前缀偏移、字符/块区间裁剪与视觉行测量。
///
/// 这些缓存都以整章 `List<ContentBlock>` 为键或值，离开阅读页后不清空会让
/// 最后一章正文随进程常驻。退出阅读页时由页面显式调用。
void clearReaderPaginationCaches() {
  BlockClipper.clearCaches();
  _ReaderPaginationTextLayout.clearCaches();
}

/// TextPainter 字符区间到章节字符区间的映射。
class _PainterContentSegment {
  const _PainterContentSegment({
    required this.painterStart,
    required this.painterEnd,
    required this.globalStart,
  });

  final int painterStart;
  final int painterEnd;
  final int globalStart;
}

/// 视觉行测量缓存条目。
class _VisualLinesCacheEntry {
  const _VisualLinesCacheEntry({
    required this.block,
    required this.pageWidth,
    required this.settings,
    required this.textScale,
    required this.blockGlobalOffset,
    required this.isContinuation,
    required this.result,
  });

  final ContentBlock block;
  final double pageWidth;
  final ReaderViewSettings settings;
  final double textScale;
  final int blockGlobalOffset;
  final bool isContinuation;
  final List<VisualLineInfo> result;
}
