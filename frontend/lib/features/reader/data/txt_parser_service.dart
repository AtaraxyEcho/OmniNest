import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kDebugMode, kIsWeb;
import 'package:gbk_codec/gbk_codec.dart';
import 'package:omninest/core/utils/yield_to_event_loop.dart';
import 'package:omninest/features/reader/domain/chapter_title_normalizer.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';

/// TXT 文件解析服务
///
/// 解码 TXT 文本，并把按服务端偏移切出的单章正文转换为可渲染的 XHTML 片段。
///
/// 章节的识别与区间划分只由后端 `ReaderTextParser` 决定：客户端不另算一套目录，
/// 否则同一本书在两端的章数与位次会不一致。
class TxtParserService {
  /// 解码并规范化 TXT 文本，偏移规则与服务端章节清单保持一致。
  String decodeText(Uint8List bytes) {
    return _normalizeLineEndings(_decodeText(bytes));
  }

  /// 单遍把 CRLF 与 CR 规范化为 LF。
  ///
  /// 不使用两次全文 `replaceAll`：百万字符级的中间串会整本重建，是 Web 与
  /// 原生 UI isolate 掉帧的直接来源。
  static String _normalizeLineEndings(String input) {
    if (!input.contains('\r')) {
      return input;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final char = input.codeUnitAt(i);
      if (char == 13) {
        buffer.write('\n');
        if (i + 1 < input.length && input.codeUnitAt(i + 1) == 10) {
          i++;
        }
      } else {
        buffer.writeCharCode(char);
      }
    }
    return buffer.toString();
  }

  /// 供 isolate 调用的纯函数解码入口。
  static String decodeTxtBytes(Uint8List bytes) {
    return TxtParserService().decodeText(bytes);
  }

  static const int _decodeIsolateThresholdBytes =
      FileSizeThresholds.txtDecodeIsolateThresholdBytes;

  String? _decodedItemId;
  String? _decodedCacheText;

  /// 判断是否纯 ASCII：纯 ASCII 的解码为线性开销，可以留在 UI isolate。
  static bool _isPureAscii(Uint8List bytes) {
    for (final byte in bytes) {
      if (byte & 0x80 != 0) {
        return false;
      }
    }
    return true;
  }

  /// 解码整本 TXT 并按条目缓存。
  ///
  /// 章节按字符偏移切自整本解码文本；大文件的 GBK 转码与全文换行
  /// 规范化在 isolate 中执行并只做一次，避免每次切章卡顿 UI 线程。
  /// Web 无 isolate：解码前后让出事件循环，换行规范化按块分片。
  ///
  /// 含非 ASCII 字节的小文件也走 isolate：GBK 分支的转码开销远高于纯 ASCII 同尺寸文件，
  /// 按字节数阈值统一判定会让中文小书冻结 UI。
  Future<String> ensureDecodedText({
    required String itemId,
    required Uint8List bytes,
  }) async {
    if (_decodedItemId == itemId && _decodedCacheText != null) {
      return _decodedCacheText!;
    }
    final String text;
    final keepOnUiIsolate =
        bytes.length < _decodeIsolateThresholdBytes && _isPureAscii(bytes);
    if (kIsWeb) {
      await yieldToEventLoop();
      text = await _decodeTextYielding(bytes);
      await yieldToEventLoop();
    } else if (keepOnUiIsolate) {
      text = decodeText(bytes);
    } else {
      text = await compute(decodeTxtBytes, bytes);
    }
    _decodedItemId = itemId;
    _decodedCacheText = text;
    return text;
  }

  /// Web 专用：解码后按 512Ki 字符块规范化换行，块间让出事件循环。
  Future<String> _decodeTextYielding(Uint8List bytes) async {
    final decoded = _decodeText(bytes);
    if (decoded.length < 512 * 1024) {
      return _normalizeLineEndings(decoded);
    }
    final buffer = StringBuffer();
    const chunk = 512 * 1024;
    var carriedReturn = '';
    for (var offset = 0; offset < decoded.length; offset += chunk) {
      final end =
          (offset + chunk < decoded.length) ? offset + chunk : decoded.length;
      var piece = carriedReturn + decoded.substring(offset, end);
      carriedReturn = '';
      // 块边界正好落在 CRLF 中间时，把 CR 推到下一块再规范化，避免多出一个空行。
      if (end < decoded.length && piece.endsWith('\r')) {
        piece = piece.substring(0, piece.length - 1);
        carriedReturn = '\r';
      }
      buffer.write(_normalizeLineEndings(piece));
      if (end < decoded.length) {
        await yieldToEventLoop();
      }
    }
    if (carriedReturn.isNotEmpty) {
      buffer.write(_normalizeLineEndings(carriedReturn));
    }
    return buffer.toString();
  }

  /// 按服务端记录的字符偏移取出本章原始文本，不做任何转换。
  ///
  /// 偏移由后端在同一解码字符域内累计；前端按 [start,end) 切出的片段首行
  /// 应当就是后端记录的本章标题行，这给了偏移错位一个可观测的检视点。
  String rawChapterSlice(String text, int startOffset, int endOffset) {
    final safeStart = startOffset.clamp(0, text.length);
    final safeEnd = endOffset.clamp(safeStart, text.length);
    return text.substring(safeStart, safeEnd);
  }

  /// 将纯文本转换为 XHTML 片段。
  ///
  /// 转换前先按章级统计屏蔽抓取残留（章题下的分隔线行、段末字数计数器），
  /// 见 [_maskScrapeResidue]；屏蔽只改成等长空白，不动字符域。
  ///
  /// 分段模式按章级统计二选一，不逐行判断、不在同一章内混用：
  /// - Mode P（行即段）：中文 TXT 主流排版——段间不空行，每个换行都是段落边界，
  ///   逐行产出 `<p>`；靠行首缩进或行长离散认出这一档（网文正文常零缩进）；
  /// - Mode W（行为软换行）：本章确实靠空行分段，或行宽贴着同一个定宽折行，
  ///   按空行分段、段内换行原样保留，避免把硬换行文件切成假段落。
  ///
  /// 两种模式都不剥行首空白，并把被用作段落边界的空白原样带进下一段行首：
  /// 转换结果与源文本逐字符对应，缩进由解析端剥除后计入 `collapsedChars`，
  /// 块模型的字符总数因此继续等于切片长度，进度与批注不会随分段模式漂移。
  String textToXhtml(String text) {
    final source = _maskScrapeResidue(text);
    final groups = <String>[];
    if (_isLinePerParagraph(source)) {
      var carriedSeparators = '';
      var isFirstLine = true;
      for (final line in source.split('\n')) {
        if (!isFirstLine) {
          // 行终止符是源字符：作为下一段的行首空白结转，由解析端计入折叠量。
          carriedSeparators += '\n';
        }
        isFirstLine = false;
        if (line.trim().isEmpty) {
          // 空白行整行也是源字符：连同终止符一起原样结转，否则块字符总数比切片短。
          // 结转成空白而不是等量换行，被屏蔽的分隔线行才不会伪装出二十几个空行。
          carriedSeparators += line;
          continue;
        }
        groups.add(carriedSeparators + line);
        carriedSeparators = '';
      }
      // 章末剩余的终止符没有后继段落可承接，挂在最后一段的尾部，
      // 解析端会把它当作尾随空白折叠并计入折叠量。
      if (groups.isNotEmpty && carriedSeparators.isNotEmpty) {
        final tail = groups.length - 1;
        groups[tail] += carriedSeparators;
      }
    } else {
      // Mode W：偶数下标是段落组，奇数下标是组间的空白行分隔符。
      final pieces = <String>[];
      var cursor = 0;
      for (final match in _blankLinePattern.allMatches(source)) {
        pieces.add(source.substring(cursor, match.start));
        pieces.add(match[0]!);
        cursor = match.end;
      }
      pieces.add(source.substring(cursor));

      var carried = '';
      for (var index = 0; index < pieces.length; index++) {
        final piece = pieces[index];
        if (index.isOdd) {
          carried += piece;
          continue;
        }
        final content = carried + piece;
        if (content.trim().isEmpty) {
          carried = content;
          continue;
        }
        carried = '';
        groups.add(content);
      }
      if (groups.isNotEmpty && carried.isNotEmpty) {
        final tail = groups.length - 1;
        groups[tail] += carried;
      }
    }

    final buffer = StringBuffer();
    for (final group in groups) {
      buffer.writeln('<p>${_escapeXml(group)}</p>');
    }
    return buffer.toString();
  }

  /// 整行只有分隔符：网文 TXT 在每个标题行下垫一条 `----`，是版式不是正文。
  static final _ruleLinePattern = RegExp(r'^[\s　]*[-=*—–_~～]{3,}[\s　]*$');

  /// 段末字数计数器：句末标点后挂 1-4 位数字并停在行尾（抓取站的剩余字数）。
  ///
  /// 只认句末标点在后继的位置，正文里 `暂定7月12日八公山` 这类真实数字
  /// 前面不是标点，不会被当成计数器。
  static final _trailingCounterPattern = RegExp(
    r'^(.*[。！？；：…’”》）】—－・，])([ \u3000]*\d{1,4})$',
  );

  /// 判定计数器的抽样行数上限，与判定的最低占比。
  static const int _residueSampleLines = 400;
  static const int _residueMinSampledLines = 8;

  /// 计数器占比门槛：本章多数行都挂着一个这种数字，才认定它是抓取残留。
  static const double _residueCounterLineRatio = 0.7;

  /// 把抓取残留改写成等长空白，而不是删掉。
  ///
  /// 删字符会让块模型的字符总数短于源切片，翻页窗口与批注偏移按源空间解释时
  /// 会整体错位；改成等长空白后解析端按普通空白折叠并计入折叠量，字符域不变。
  String _maskScrapeResidue(String text) {
    if (!text.contains('\n')) {
      return text;
    }
    final lines = text.split('\n');
    final countersDomin = _trailingCounterShare(lines);
    var changed = false;
    final masked = <String>[];
    for (final line in lines) {
      if (_ruleLinePattern.hasMatch(line)) {
        changed = true;
        masked.add(' ' * line.length);
        continue;
      }
      final counter =
          countersDomin ? _trailingCounterPattern.firstMatch(line) : null;
      if (counter == null) {
        masked.add(line);
        continue;
      }
      changed = true;
      masked.add('${counter.group(1)!}${' ' * counter.group(2)!.length}');
    }
    return changed ? masked.join('\n') : text;
  }

  /// 抽样内"句末标点后挂数字并停在行尾"的非空行占比。
  bool _trailingCounterShare(List<String> lines) {
    var sampled = 0;
    var counters = 0;
    for (final line in lines) {
      if (line.trim().isEmpty || _ruleLinePattern.hasMatch(line)) {
        continue;
      }
      sampled += 1;
      if (_trailingCounterPattern.hasMatch(line)) {
        counters += 1;
      }
      if (sampled >= _residueSampleLines) {
        break;
      }
    }
    if (sampled < _residueMinSampledLines) {
      return false;
    }
    return counters / sampled >= _residueCounterLineRatio;
  }

  /// 行首/行尾空白剥除，含全角空格与零宽空格。
  static final _edgeWhitespacePattern = RegExp(r'^[\s　﻿]+|[\s　﻿]+$');

  /// 校验本章切片的首行是否就是服务端记录的章节标题。
  ///
  /// 返回 false 表示前后端解码出的字符域不一致（编码判定或坏序列策略分歧），
  /// 此时按偏移切出的内容会静默错位到别的章节。
  /// 单章"正文"（后端未识别出任何标题）与空切片不参与判定，避免误报。
  ///
  /// 比对前两侧都施加 [normalizeChapterTitle]：入库标题已按目录位次归一掉重复序号，
  /// 直接拿它比对首行会把每一章都误判成偏移漂移。[chapterOrdinal] 必须与后端建清单时
  /// 用的是同一个 1-based 位次，否则两侧归一留下的标记不同。
  static bool sliceStartsWithTitle(
    String rawSlice,
    String title, {
    required int chapterOrdinal,
  }) {
    final expected = normalizeChapterTitle(title.trim(), chapterOrdinal);
    if (expected.isEmpty || expected == '正文') {
      return true;
    }
    final newline = rawSlice.indexOf('\n');
    final firstLine = (newline < 0 ? rawSlice : rawSlice.substring(0, newline))
        .replaceAll(_edgeWhitespacePattern, '');
    if (firstLine.isEmpty) {
      return false;
    }
    final actual = normalizeChapterTitle(firstLine, chapterOrdinal);
    return actual == expected || actual.startsWith(expected);
  }

  /// 自动检测编码并解码文本
  ///
  /// 检测顺序：UTF-8 BOM → UTF-8 → GBK → Latin-1，与后端 `ReaderTextParser.detectCharset`
  /// 的判定次序保持一致，否则两端解码出的字符串长度不同会让服务端偏移整体错位。
  String _decodeText(Uint8List bytes) {
    // UTF-8 BOM：BOM 不进入偏移域；BOM 后仍可能出现坏字节，必须容错而不是抛出。
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return _decodeUtf8OrReplace(bytes.sublist(3));
    }

    // 尝试 UTF-8（严格模式）
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (error) {
      if (kDebugMode) {
        readerDebugLog('TxtParser: UTF-8 decode failed, trying GBK: $error');
      }
    }

    // 尝试 GBK（中文常见编码）。`gbk` 的映射表以双字节 GBK 码元为键，逐字节查表永不命中，
    // 实际退化为 Latin-1；必须使用同包内按双字节组合查表的 `gbk_bytes`。
    try {
      return gbk_bytes.decode(bytes);
    } catch (error) {
      if (kDebugMode) {
        readerDebugLog(
          'TxtParser: GBK decode failed, falling back to Latin-1: $error',
        );
      }
    }

    // 最终回退
    return latin1.decode(bytes);
  }

  /// UTF-8 宽松解码，坏序列替换为 U+FFFD，与后端 InputStreamReader 的 REPLACE 策略一致。
  String _decodeUtf8OrReplace(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// 行首缩进判据：至少一个空白字符（含全角空格）后紧跟非空白内容。
  static final _leadingIndentPattern = RegExp(r'^[ \t　]+\S');

  /// 空行分段判据。
  static final _blankLinePattern = RegExp(r'\n\s*\n');

  /// Mode P 判定的章级取样上限与非空行下限。
  static const int _modeSampleLines = 400;
  static const int _modeMinSampledLines = 2;

  /// Mode P 要求的最小缩进行占比。
  static const double _modeIndentedLineRatio = 0.3;

  /// 空行算作分段机制所需的最低非空块数：孤立在章首/章尾的空白行不算。
  static const int _modeMinBlankGroups = 2;

  /// 判为定宽硬换行的行数下限与"贴着同一宽度"的占比。
  static const int _modeWrapMinSampledLines = 8;
  static const double _modeFixedWidthLineRatio = 0.7;

  /// 定宽判定里允许比参照宽度短的字符数（段末短句与标点悬挂）。
  static const int _modeWrapWidthSlack = 3;

  /// 判断本章应按"每行一段"分段。
  ///
  /// 三道判据按信息强度递进，前一道不成立才降级到下一道：
  /// - 空行分段：只有空白行确实把本章切成多个非空块时，才认定本书用空行分段。
  ///   按"出现过空行"一刀切会让章尾那一个空行否掉整档（服务端正文切片就带着它）；
  /// - 行首缩进：抽样非空行有足够比例以行首空白缩进——中文 TXT 的经典排版；
  /// - 行长离散：网文正文常零缩进、段间不空行，段落靠换行分开，行宽长短不齐。
  ///   只有多数行都贴着同一个宽度才判为定宽硬换行，此时段内换行不是段落边界。
  ///
  /// 三道都不成立时保持 Mode W，不做逐行启发式猜测。
  bool _isLinePerParagraph(String text) {
    if (_blankSeparatedGroupCount(text) >= _modeMinBlankGroups) {
      return false;
    }
    final lengths = <int>[];
    var nonEmpty = 0;
    var indented = 0;
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) {
        continue;
      }
      nonEmpty++;
      if (_leadingIndentPattern.hasMatch(line)) {
        indented++;
      }
      // 离散量的是去掉行首空白后的正文宽度，否则缩进本身会撑出离散。
      lengths.add(line.trim().length);
      if (nonEmpty >= _modeSampleLines) {
        break;
      }
    }
    if (nonEmpty < _modeMinSampledLines) {
      return false;
    }
    if (indented / nonEmpty >= _modeIndentedLineRatio) {
      return true;
    }
    if (lengths.length < _modeWrapMinSampledLines) {
      return false;
    }
    return !_isFixedWidthWrapping(lengths);
  }

  /// 空白行把本章切出的非空块数。
  int _blankSeparatedGroupCount(String text) {
    var groups = 0;
    for (final piece in text.split(_blankLinePattern)) {
      if (piece.trim().isNotEmpty) {
        groups++;
      }
    }
    return groups;
  }

  /// 行宽是否贴着同一个宽度（定宽硬换行的签名）。
  ///
  /// 参照宽度取 90 分位而不是最大值：畸形文件里个别超长行会把上限抬高，
  /// 让真正定宽的书看起来"离散"。
  bool _isFixedWidthWrapping(List<int> lengths) {
    final sorted = <int>[...lengths]..sort();
    final reference =
        sorted[(sorted.length * 0.9 - 1).clamp(0, sorted.length - 1).toInt()];
    var atWidth = 0;
    for (final length in sorted) {
      if (length >= reference - _modeWrapWidthSlack) {
        atWidth++;
      }
    }
    return atWidth / sorted.length >= _modeFixedWidthLineRatio;
  }

  /// 转义 XML 特殊字符
  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
