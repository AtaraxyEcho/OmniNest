import 'dart:math' as math;

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

  String? _compactText;
  List<int>? _compactToPlain;

  /// 懒缓存去除空白与不可见占位符的紧凑语料与下标映射表（O(N) 一次构建，长文本匹配零正则回溯）。
  (String, List<int>) compactView() {
    if (_compactText != null && _compactToPlain != null) {
      return (_compactText!, _compactToPlain!);
    }
    final buf = StringBuffer();
    final map = <int>[];
    for (var i = 0; i < plainText.length; i++) {
      final code = plainText.codeUnitAt(i);
      if (_isIgnorableSelectionCodeUnit(code)) continue;
      buf.writeCharCode(code);
      map.add(i);
    }
    _compactText = buf.toString();
    _compactToPlain = map;
    return (_compactText!, _compactToPlain!);
  }

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
  // 优先走 L1/L2 紧凑无空白 O(N) 索引匹配：彻底解决长文本跨段换行/不可见字符导致的失配与正则回溯卡顿。
  final compactNeedleBuf = StringBuffer();
  for (var i = 0; i < needle.length; i++) {
    final code = needle.codeUnitAt(i);
    if (_isIgnorableSelectionCodeUnit(code)) continue;
    compactNeedleBuf.writeCharCode(code);
  }
  final compactNeedle = compactNeedleBuf.toString();
  if (compactNeedle.isEmpty) return null;

  final (compactText, compactToPlain) = corpus.compactView();
  if (compactText.isEmpty) return null;

  (int, int)? pickClosest(List<(int, int)> spans) {
    if (spans.isEmpty) return null;
    var best = spans.first;
    final anchor = anchorCharOffset;
    if (anchor != null && spans.length > 1) {
      var bestDist = (corpus.toCharOffset(best.$1) - anchor).abs();
      for (final s in spans.skip(1)) {
        final d = (corpus.toCharOffset(s.$1) - anchor).abs();
        if (d < bestDist) {
          bestDist = d;
          best = s;
        }
      }
    }
    return (corpus.toCharOffset(best.$1), corpus.toCharOffsetEnd(best.$2));
  }

  // L1+L2: 直接在紧凑语料中收集全部精确命中区间
  final exactHits = <(int, int)>[];
  var searchFrom = 0;
  while (searchFrom <= compactText.length - compactNeedle.length) {
    final idx = compactText.indexOf(compactNeedle, searchFrom);
    if (idx < 0) break;
    exactHits.add((
      compactToPlain[idx],
      compactToPlain[idx + compactNeedle.length - 1],
    ));
    searchFrom = idx + 1;
    if (exactHits.length >= 24) break;
  }
  final exact = pickClosest(exactHits);
  if (exact != null) return exact;

  // L3: 超长跨段选区首尾 12 字锚点闭合匹配（容错中间插入页码或特殊排版符）
  if (compactNeedle.length >= 24) {
    const anchorLen = 12;
    final head = compactNeedle.substring(0, anchorLen);
    final tail = compactNeedle.substring(compactNeedle.length - anchorLen);
    final headIdx = compactText.indexOf(head);
    if (headIdx >= 0) {
      final minTailStart = headIdx + anchorLen;
      final maxTailEnd = math.min(
        compactText.length,
        headIdx + compactNeedle.length + 80,
      );
      if (minTailStart < maxTailEnd) {
        final tailIdx = compactText.indexOf(tail, minTailStart);
        if (tailIdx >= 0 && tailIdx + anchorLen <= maxTailEnd) {
          return (
            corpus.toCharOffset(compactToPlain[headIdx]),
            corpus.toCharOffsetEnd(compactToPlain[tailIdx + anchorLen - 1]),
          );
        }
      }
    }
  }
  return null;
}

bool _isIgnorableSelectionCodeUnit(int code) {
  return code == 0x20 ||
      code == 0x09 ||
      code == 0x0A ||
      code == 0x0D ||
      code == 0x00A0 ||
      code == 0x3000 ||
      code == 0x200B ||
      code == 0xFEFF ||
      code == 0xFFFC;
}
