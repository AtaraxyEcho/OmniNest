import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';

/// 从内容块提取纯文本（搜索 / TTS / 进度辅助）。
String plainTextFromBlocks(List<ContentBlock> blocks) {
  if (blocks.isEmpty) {
    return '';
  }
  final buffer = StringBuffer();
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0) {
      buffer.writeln();
    }
    appendBlockText(buffer, blocks[i]);
  }
  return buffer.toString();
}

/// 将单个块的可见文本写入 [buffer]。
void appendBlockText(StringBuffer buffer, ContentBlock block) {
  switch (block) {
    case HeadingBlock(:final text):
      buffer.write(text);
    case ParagraphBlock(:final lines):
      _writeLines(buffer, lines);
    case BlockquoteBlock(:final lines):
      _writeLines(buffer, lines);
    case ListBlock(:final items):
      for (var i = 0; i < items.length; i++) {
        if (i > 0) {
          buffer.writeln();
        }
        for (final span in items[i].spans) {
          buffer.write(span.text);
        }
      }
    case TableBlock(:final rows):
      for (var r = 0; r < rows.length; r++) {
        if (r > 0) {
          buffer.writeln();
        }
        final cells = rows[r].cells;
        for (var c = 0; c < cells.length; c++) {
          if (c > 0) {
            buffer.write('\t');
          }
          for (final span in cells[c]) {
            buffer.write(span.text);
          }
        }
      }
    case ImageBlock():
    case DividerBlock():
      break;
  }
}

void _writeLines(StringBuffer buffer, List<LineData> lines) {
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) {
      buffer.writeln();
    }
    for (final span in lines[i].spans) {
      buffer.write(span.text);
    }
  }
}
