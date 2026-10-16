import 'dart:ui';

import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_annotation_handler.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';

/// 将阅读批注投影到内容块并按批注边界切分行内文本。
abstract final class ReaderContentAnnotationProjector {
  static List<ContentBlock> apply(
    List<ContentBlock> blocks,
    List<ReaderAnnotation> annotations,
  ) {
    if (annotations.isEmpty) return blocks;
    return blocks.map((block) {
      if (block is ParagraphBlock) {
        return ParagraphBlock(
          lines: _applyToLines(block.lines, annotations),
          hasTrailingSpacing: block.hasTrailingSpacing,
          style: block.style,
        );
      }
      if (block is BlockquoteBlock) {
        return BlockquoteBlock(
          lines: _applyToLines(block.lines, annotations),
          startOffset: block.startOffset,
          style: block.style,
          hasTopPadding: block.hasTopPadding,
          hasBottomPadding: block.hasBottomPadding,
        );
      }
      if (block is ListBlock) {
        return ListBlock(
          items:
              block.items.map((item) {
                return ListItemData(
                  spans: _applyToSpans(item.spans, annotations),
                );
              }).toList(),
          isOrdered: block.isOrdered,
          startOffset: block.startOffset,
        );
      }
      if (block is TableBlock) {
        return TableBlock(
          rows:
              block.rows.map((row) {
                return TableRowData(
                  cells:
                      row.cells.map((cell) {
                        return _applyToSpans(cell, annotations);
                      }).toList(),
                  isHeader: row.isHeader,
                );
              }).toList(),
          startOffset: block.startOffset,
        );
      }
      return block;
    }).toList();
  }

  static List<LineData> _applyToLines(
    List<LineData> lines,
    List<ReaderAnnotation> annotations,
  ) {
    return lines.map((line) {
      // 重建行必须带上全部字段：
      // - isNewParagraph 是首行缩进标记，丢了会让加过批注的段落失去首行缩进；
      // - style 是书给该源段落的排版，绘制侧 `firstLineIndentChars(line.style)`
      //   取它，丢了「跟随原书」下书表达的缩进会整章消失，而测量侧仍用带样式的
      //   ChapterData.blocks ⇒ 测量/渲染分叉（固定 itemExtent 下裁行、页预算偏一行）；
      // - trailingCollapsedChars 参与 LineData.sourceChars 记账，丢了会让批注偏移
      //   与页裁剪落到不同字符位置。
      return LineData(
        spans: _applyToSpans(line.spans, annotations),
        isNewParagraph: line.isNewParagraph,
        collapsedChars: line.collapsedChars,
        trailingCollapsedChars: line.trailingCollapsedChars,
        softWrap: line.softWrap,
        style: line.style,
      );
    }).toList();
  }

  static List<ReaderInlineSpan> _applyToSpans(
    List<ReaderInlineSpan> spans,
    List<ReaderAnnotation> annotations,
  ) {
    final result = <ReaderInlineSpan>[];
    for (final span in spans) {
      result.addAll(_splitSpan(span, annotations));
    }
    return result;
  }

  static List<ReaderInlineSpan> _splitSpan(
    ReaderInlineSpan span,
    List<ReaderAnnotation> annotations,
  ) {
    final spanStart = span.startOffset;
    final spanEnd = spanStart + span.text.length;
    final overlapping =
        annotations
            .where(
              (annotation) =>
                  annotation.startOffset < spanEnd &&
                  annotation.endOffset > spanStart,
            )
            .toList()
          ..sort(
            (left, right) => left.startOffset.compareTo(right.startOffset),
          );
    if (overlapping.isEmpty) return [span];

    final result = <ReaderInlineSpan>[];
    var cursor = spanStart;
    for (final annotation in overlapping) {
      final annotationStart = annotation.startOffset.clamp(cursor, spanEnd);
      final annotationEnd = annotation.endOffset.clamp(cursor, spanEnd);
      if (annotationStart >= annotationEnd) continue;
      if (annotationStart > cursor) {
        result.add(_copySpan(span, cursor, annotationStart - cursor));
      }
      final highlightText = span.text.substring(
        annotationStart - spanStart,
        annotationEnd - spanStart,
      );
      final color = ReaderAnnotationHandler.parseAnnotationColor(
        annotation.color,
      );
      result.add(
        _copySpan(
          span,
          annotationStart,
          annotationEnd - annotationStart,
          backgroundColor: color.withValues(alpha: 0.25),
          textOverride: highlightText,
        ),
      );
      cursor = annotationEnd;
    }
    if (cursor < spanEnd) {
      result.add(_copySpan(span, cursor, spanEnd - cursor));
    }
    return result;
  }

  static ReaderInlineSpan _copySpan(
    ReaderInlineSpan source,
    int startOffset,
    int length, {
    Color? backgroundColor,
    String? textOverride,
  }) {
    return ReaderInlineSpan(
      text:
          textOverride ??
          source.text.substring(
            startOffset - source.startOffset,
            startOffset - source.startOffset + length,
          ),
      isBold: source.isBold,
      isItalic: source.isItalic,
      isHeading: source.isHeading,
      href: source.href,
      isCode: source.isCode,
      startOffset: startOffset,
      backgroundColor: backgroundColor ?? source.backgroundColor,
      isSuperscript: source.isSuperscript,
      isSubscript: source.isSubscript,
      isMarked: source.isMarked,
      isDeleted: source.isDeleted,
      isUnderlined: source.isUnderlined,
    );
  }
}
