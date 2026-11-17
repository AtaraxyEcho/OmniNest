import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';

/// 章节可检索文本，以及逐码元回到块源字符域（`charOffset`）的映射表。
///
/// 阅读器里有三套文本坐标：`stripHtml(原始 HTML)` 的剥离域、可绘制文本域，以及
/// 分页、滚动定位与批注共同使用的块源字符域。前两套与源域之间是**双向**漂移：HTML 标签
/// 换成空格会多出字符，行首缩进、段内软换行与 TXT 掩码空白又会在别处坍缩掉。检索命中
/// 下标必须经本表换算，直接当 `charOffset` 用会偏到别的段落去。
class ChapterSearchCorpus {
  ChapterSearchCorpus({required this.plainText, required this.charOffsets});

  /// 从内容块构建检索文本与偏移映射，文本形状与 [plainTextFromBlocks] 完全一致。
  factory ChapterSearchCorpus.fromBlocks(List<ContentBlock> blocks) {
    if (blocks.isEmpty) {
      return ChapterSearchCorpus(plainText: '', charOffsets: const <int>[]);
    }
    final buffer = StringBuffer();
    final offsets = <int>[];
    var blockStart = 0;

    void writeText(String text, int sourceStart) {
      for (var i = 0; i < text.length; i++) {
        buffer.writeCharCode(text.codeUnitAt(i));
        offsets.add(sourceStart + i);
      }
    }

    // 源文本里不存在这些分隔符：它们没有自己的源字符，落到后面第一个实字符的位置。
    void writeSeparator(String text, int targetOffset) {
      for (var i = 0; i < text.length; i++) {
        buffer.writeCharCode(text.codeUnitAt(i));
        offsets.add(targetOffset);
      }
    }

    void writeSpans(List<ReaderInlineSpan> spans) {
      for (final span in spans) {
        writeText(span.text, span.startOffset);
      }
    }

    void writeLines(List<LineData> lines) {
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) {
          writeSeparator('\n', lineStart(lines, i, blockStart));
        }
        writeSpans(lines[i].spans);
      }
    }

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (i > 0) {
        writeSeparator('\n', blockStart);
      }
      switch (block) {
        case HeadingBlock(:final text, :final startOffset):
          writeText(text, startOffset);
        case ParagraphBlock(:final lines):
          writeLines(lines);
        case BlockquoteBlock(:final lines):
          writeLines(lines);
        case ListBlock(:final items):
          for (var index = 0; index < items.length; index++) {
            final spans = items[index].spans;
            if (index > 0 && spans.isNotEmpty) {
              writeSeparator('\n', spans.first.startOffset);
            }
            writeSpans(spans);
          }
        case TableBlock(:final rows):
          for (var r = 0; r < rows.length; r++) {
            final cells = rows[r].cells;
            if (r > 0) {
              writeSeparator('\n', _rowStart(cells, blockStart));
            }
            for (var c = 0; c < cells.length; c++) {
              if (c > 0 && cells[c].isNotEmpty) {
                writeSeparator('\t', cells[c].first.startOffset);
              }
              writeSpans(cells[c]);
            }
          }
        case ImageBlock():
        case DividerBlock():
          break;
      }
      blockStart += BlockClipper.blockCharCount(block);
    }

    return ChapterSearchCorpus(
      plainText: buffer.toString(),
      charOffsets: offsets,
    );
  }

  final String plainText;

  /// 与 [plainText] 逐码元对齐的源字符域偏移。
  final List<int> charOffsets;

  /// 把检索文本下标换算成章节块源字符域偏移。
  int toCharOffset(int plainIndex) {
    if (charOffsets.isEmpty) {
      return 0;
    }
    if (plainIndex <= 0) {
      return charOffsets.first;
    }
    if (plainIndex >= charOffsets.length) {
      return charOffsets.last;
    }
    return charOffsets[plainIndex];
  }

  /// 命中区间**末尾**的下一个源字符位置，供选区右端点使用。
  int toCharOffsetEnd(int plainLastIndex) {
    if (charOffsets.isEmpty) {
      return 0;
    }
    return charOffsets[plainLastIndex.clamp(0, charOffsets.length - 1)] + 1;
  }

  /// 第 [index] 行在源字符域的起点（含被剥掉的行首空白）。
  static int lineStart(List<LineData> lines, int index, int fallback) {
    final line = lines[index];
    if (line.spans.isEmpty) {
      return fallback;
    }
    return line.spans.first.startOffset - line.collapsedChars;
  }

  static int _rowStart(List<List<ReaderInlineSpan>> cells, int fallback) {
    for (final cell in cells) {
      if (cell.isNotEmpty) {
        return cell.first.startOffset;
      }
    }
    return fallback;
  }
}

/// 从内容块提取纯文本（搜索 / TTS / 进度辅助）。
///
/// 下标是可绘制文本位置，与分页字符域不同源：块与行之间补的 `\n`、单元格之间补的 `\t`
/// 都是合成分隔符，源文本里不存在；行首与行尾的折叠空白反过来在字符域里有位置。
/// 要定位到页或标注，用 [ChapterSearchCorpus.toCharOffset] 换算。
String plainTextFromBlocks(List<ContentBlock> blocks) {
  return ChapterSearchCorpus.fromBlocks(blocks).plainText;
}

/// 在 [corpus] 里匹配 [needle]，返回块源字符域的起止区间 `[start, end)`。
///
/// 选区来自渲染后的文本：跨行、跨段、跨内联样式与跨已有高亮切分边界都是常态，所以匹配
/// 在连续语料上做，词元之间按任意空白段容错（渲染折行与源文本折叠空白的数量都不固定）。
/// 同一章里重复出现的短词会有多处命中：给了 [anchorCharOffset]（例如当前视口中心）时
/// 取离它最近的一处，否则退回文档顺序的第一处。
(int, int)? matchCorpusRange(
  ChapterSearchCorpus corpus,
  String needle, {
  int? anchorCharOffset,
}) {
  if (corpus.plainText.isEmpty || needle.isEmpty) {
    return null;
  }
  final tokens =
      needle
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty)
          .map(RegExp.escape)
          .toList();
  if (tokens.isEmpty) {
    return null;
  }
  // 选区与语料的空白不必一一对应：渲染折行会给选中文字补出换行或空格，
  // 而同一段里跨内联样式边界的两个字在两边都可能没有空白。词元之间容许零个或多个空白。
  final matches =
      RegExp(tokens.join(r'\s*')).allMatches(corpus.plainText).toList();
  if (matches.isEmpty) {
    return null;
  }
  var chosen = matches.first;
  final anchor = anchorCharOffset;
  if (anchor != null && matches.length > 1) {
    var bestDistance = _distanceToAnchor(corpus, matches.first, anchor);
    for (final match in matches.skip(1)) {
      final distance = _distanceToAnchor(corpus, match, anchor);
      if (distance < bestDistance) {
        bestDistance = distance;
        chosen = match;
      }
    }
  }
  return (
    corpus.toCharOffset(chosen.start),
    corpus.toCharOffsetEnd(chosen.end - 1),
  );
}

int _distanceToAnchor(
  ChapterSearchCorpus corpus,
  RegExpMatch match,
  int anchorCharOffset,
) {
  return (corpus.toCharOffset(match.start) - anchorCharOffset).abs();
}
