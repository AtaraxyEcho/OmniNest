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

  static int blockCharCount(ContentBlock block) {
    return switch (block) {
      HeadingBlock(:final text) => text.length,
      ParagraphBlock(:final lines) => _linesCharCount(lines),
      ImageBlock() => 0,
      DividerBlock() => 0,
      BlockquoteBlock(:final lines) => _linesCharCount(lines),
      ListBlock(:final items) => items.fold(
        0,
        (sum, item) => sum + _linesCharCount([LineData(spans: item.spans)]),
      ),
      TableBlock(:final rows) => rows.fold(
        0,
        (sum, row) =>
            sum +
            row.cells.fold(
              0,
              (cellSum, cell) =>
                  cellSum + _linesCharCount([LineData(spans: cell)]),
            ),
      ),
    };
  }

  static int _linesCharCount(List<LineData> lines) {
    var total = 0;
    for (final line in lines) {
      for (final span in line.spans) {
        total += span.text.length;
      }
    }
    return total;
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
  /// 调用本方法，无缓存时每帧重建 TextPainter。键含 settings 身份
  /// （排版参数）与 blockGlobalOffset（块前缀，章内恒定）；LRU 上限
  /// 64 防内存增长，换章/换排版自然淘汰。
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
          identical(entry.settings, settings) &&
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

      if (i > 0) {
        final previousLine = lines[i - 1];
        final previousIsEmpty =
            previousLine is LineData && previousLine.spans.isEmpty;
        final isNewParagraph =
            line is LineData && line.isNewParagraph && !previousIsEmpty;
        if (isNewParagraph) {
          allSpans.add(const TextSpan(text: '\n　　'));
          painterOffset += 3;
        } else {
          allSpans.add(const TextSpan(text: '\n'));
          painterOffset += 1;
        }
      } else if (!isContinuation) {
        allSpans.add(const TextSpan(text: '　　'));
        painterOffset += 2;
      }

      final renderedSpans = _ReaderPaginationMetrics.lineTextSpans(
        lineSpans,
        settings,
        textScale,
      );
      allSpans.addAll(renderedSpans);

      final lineStart = charAccum;
      var lineLength = 0;
      for (final span in lineSpans) {
        lineLength += span.text.length;
      }
      if (lineLength > 0) {
        contentSegments.add(
          _PainterContentSegment(
            painterStart: painterOffset,
            painterEnd: painterOffset + lineLength,
            globalStart: lineStart,
          ),
        );
      }
      painterOffset += lineLength;
      charAccum += lineLength;
    }

    if (allSpans.isEmpty) return [];

    final innerWidth =
        block is BlockquoteBlock
            ? pageWidth - 16
            : block is ListBlock
            ? pageWidth - 24
            : pageWidth;

    final painter = TextPainter(
      text: TextSpan(
        children: allSpans,
        style: _ReaderPaginationMetrics.baseStyle(
          settings,
          settings.fontSize * textScale,
        ),
      ),
      strutStyle: settings.bodyStrutStyle(textScale: textScale),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: innerWidth);

    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) return [];

    // 将每条视觉行的像素边界转换回章节字符范围。
    final result = <PaginationVisualLine>[];
    var segmentCursor = 0;
    for (final metric in metrics) {
      final top = metric.baseline - metric.ascent;
      final probePosition = painter.getPositionForOffset(
        Offset(0, top + metric.height / 2),
      );
      final lineBoundary = painter.getLineBoundary(probePosition);
      final painterStart = lineBoundary.start.clamp(0, painterOffset);
      final painterEnd = lineBoundary.end.clamp(0, painterOffset);

      if (painterStart >= painterEnd) continue;

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
          height: metric.height,
        ),
      );
    }

    return result;
  }
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
