import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';

/// 在章节 blocks 中定位选中文本的字符范围。
///
/// 与单章 ReaderViewContent 的选区解析同源，供连续滚动邻章批注复用。
/// 返回 (start, end)，未命中时返回 null。
(int, int)? resolveSelectionRangeInBlocks(
  List<ContentBlock> blocks,
  String selectedText, {
  int baseOffset = 0,
}) {
  if (selectedText.isEmpty || blocks.isEmpty) {
    return null;
  }
  var running = baseOffset;
  for (final block in blocks) {
    final spans = _spansOf(block, running);
    for (final span in spans) {
      final local = span.text.indexOf(selectedText);
      if (local >= 0) {
        final start = span.startOffset + local;
        return (start, start + selectedText.length);
      }
      final normalized = _findNormalizedOffset(span.text, selectedText);
      if (normalized != null) {
        final start = span.startOffset + normalized;
        return (start, start + selectedText.length);
      }
    }
    running += _blockTextLength(block);
  }
  return null;
}

/// 判断选中文本是否出现在给定 blocks 中。
bool blocksContainSelection(List<ContentBlock> blocks, String selectedText) {
  return resolveSelectionRangeInBlocks(blocks, selectedText) != null;
}

List<ReaderInlineSpan> _spansOf(ContentBlock block, int runningOffset) {
  return switch (block) {
    ParagraphBlock(:final lines) => [for (final line in lines) ...line.spans],
    BlockquoteBlock(:final lines) => [for (final line in lines) ...line.spans],
    ListBlock(:final items) => [for (final item in items) ...item.spans],
    HeadingBlock(:final text) => [
      ReaderInlineSpan(text: text, startOffset: runningOffset),
    ],
    TableBlock(:final rows) => [
      for (final row in rows)
        for (final cell in row.cells) ...cell,
    ],
    ImageBlock() || DividerBlock() => const <ReaderInlineSpan>[],
  };
}

int _blockTextLength(ContentBlock block) {
  return switch (block) {
    HeadingBlock(:final text) => text.length,
    ParagraphBlock(:final lines) => lines.fold(
      0,
      (s, l) => s + l.spans.fold(0, (s2, sp) => s2 + sp.text.length),
    ),
    BlockquoteBlock(:final lines) => lines.fold(
      0,
      (s, l) => s + l.spans.fold(0, (s2, sp) => s2 + sp.text.length),
    ),
    ListBlock(:final items) => items.fold(
      0,
      (s, i) => s + i.spans.fold(0, (s2, sp) => s2 + sp.text.length),
    ),
    TableBlock(:final rows) => rows.fold(
      0,
      (s, r) =>
          s +
          r.cells.fold(
            0,
            (s2, c) => s2 + c.fold(0, (s3, sp) => s3 + sp.text.length),
          ),
    ),
    ImageBlock() || DividerBlock() => 0,
  };
}

int? _findNormalizedOffset(String source, String selectedText) {
  final normalizedSource = source.replaceAll(RegExp(r'\s+'), ' ');
  final normalizedSelection = selectedText.replaceAll(RegExp(r'\s+'), ' ');
  final normalizedOffset = normalizedSource.indexOf(normalizedSelection);
  if (normalizedOffset < 0) {
    return null;
  }
  var sourceOffset = 0;
  var normalizedIndex = 0;
  while (sourceOffset < source.length && normalizedIndex < normalizedOffset) {
    if (RegExp(r'\s').hasMatch(source[sourceOffset])) {
      while (sourceOffset < source.length &&
          RegExp(r'\s').hasMatch(source[sourceOffset])) {
        sourceOffset++;
      }
      normalizedIndex++;
    } else {
      sourceOffset++;
      normalizedIndex++;
    }
  }
  return sourceOffset;
}
