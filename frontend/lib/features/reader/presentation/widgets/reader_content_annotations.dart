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
        );
      }
      if (block is BlockquoteBlock) {
        return BlockquoteBlock(
          lines: _applyToLines(block.lines, annotations),
          startOffset: block.startOffset,
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
      // isNewParagraph 是首行缩进标记，必须随行保留：投影重建时丢弃
      // 会让加过批注的段落失去首行缩进（布局视为非段首行）。
      return LineData(
        spans: _applyToSpans(line.spans, annotations),
        isNewParagraph: line.isNewParagraph,
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
