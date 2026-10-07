import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kDebugMode, kIsWeb;
import 'package:gbk_codec/gbk_codec.dart';
import 'package:omninest/core/utils/yield_to_event_loop.dart';
import 'package:omninest/features/reader/domain/parsed_book.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';

/// TXT 文件解析服务
///
/// 将纯文本文件按章节模式拆分，并转换为可渲染的 XHTML 片段。
class TxtParserService {
  /// 卷级模式（Volume、卷、篇、PART）
  static final _volumePattern = RegExp(
    r'^(?:第[零一二三四五六七八九十百千万\d]+[卷篇]|PART\s+[IVXLC\d]+)',
    multiLine: true,
    caseSensitive: false,
  );

  /// 章级模式（Chapter、章、回）
  static final _chapterPattern = RegExp(
    r'^(?:'
    r'第[零一二三四五六七八九十百千万\d]+[章回]'
    r'|Chapter\s+\d+'
    r'|CHAPTER\s+\d+'
    r'|(?:\d{1,4})\s*[\.、]\s*\S'
    r')',
    multiLine: true,
  );

  /// 节级模式（Section、节）
  static final _sectionPattern = RegExp(
    r'^第[零一二三四五六七八九十百千万\d]+[节]',
    multiLine: true,
  );

  /// 综合章节匹配模式（用于拆分）
  static final _splitPattern = RegExp(
    r'^(?:'
    r'第[零一二三四五六七八九十百千万\d]+[章回节卷篇]'
    r'|Chapter\s+\d+'
    r'|CHAPTER\s+\d+'
    r'|PART\s+[IVXLC\d]+'
    r'|(?:\d{1,4})\s*[\.、]\s*\S'
    r')',
    multiLine: true,
  );

  /// 解析 TXT 字节流为 [ParsedBook]
  ///
  /// 自动检测编码：UTF-8 BOM → UTF-8 → GBK → Latin-1。
  /// [fileName] 用于提取书名（去除扩展名）。
  ParsedBook parse(Uint8List bytes, {String? fileName}) {
    final text = decodeText(bytes);

    // 从文件名提取标题
    final title = _extractTitle(fileName);

    // 按章节模式拆分
    final rawChapters = _splitChapters(text);

    final chapters = <ParsedChapter>[];
    for (var i = 0; i < rawChapters.length; i++) {
      final raw = rawChapters[i];
      final xhtmlContent = textToXhtml(raw.content);
      chapters.add(
        ParsedChapter(
          number: i + 1,
          title: raw.title ?? '第${i + 1}章',
          xhtmlContent: xhtmlContent,
          charCount: raw.content.length,
          level: raw.level,
        ),
      );
    }

    // 如果没有检测到章节，将整个文本作为单章
    if (chapters.isEmpty) {
      final xhtmlContent = textToXhtml(text);
      chapters.add(
        ParsedChapter(
          number: 1,
          title: title ?? '正文',
          xhtmlContent: xhtmlContent,
          charCount: text.length,
        ),
      );
    }

    return ParsedBook(chapters: chapters, title: title);
  }

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

  /// 从已解码文本中按字符偏移取单章并转换为 XHTML。
  String chapterFromText(String text, int startOffset, int endOffset) {
    return textToXhtml(rawChapterSlice(text, startOffset, endOffset));
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
  /// 分段模式按章级统计二选一，不逐行判断、不在同一章内混用：
  /// - Mode P（行即段）：中文 TXT 主流排版——段间无空行、段首行首空白缩进，
  ///   每个换行都是段落边界，逐行产出 `<p>`；
  /// - Mode W（行为软换行）：其余情况按空行分段，段内换行原样保留，
  ///   避免把硬换行文件（每行约 35-80 字符断行）切成假段落。
  ///
  /// 两种模式都不剥行首空白，并把被用作段落边界的空白原样带进下一段行首：
  /// 转换结果与源文本逐字符对应，缩进由解析端剥除后计入 `collapsedChars`，
  /// 块模型的字符总数因此继续等于切片长度，进度与批注不会随分段模式漂移。
  String textToXhtml(String text) {
    final groups = <String>[];
    if (_isLinePerParagraph(text)) {
      var carriedSeparators = 0;
      var isFirstLine = true;
      for (final line in text.split('\n')) {
        if (!isFirstLine) {
          // 行终止符是源字符：作为下一段的行首空白结转，由解析端计入折叠量。
          carriedSeparators += 1;
        }
        isFirstLine = false;
        if (line.trim().isEmpty) {
          continue;
        }
        groups.add('\n' * carriedSeparators + line);
        carriedSeparators = 0;
      }
      // 章末剩余的终止符没有后继段落可承接，挂在最后一段的尾部，
      // 解析端会把它当作尾随空白折叠并计入折叠量。
      if (groups.isNotEmpty && carriedSeparators > 0) {
        final tail = groups.length - 1;
        groups[tail] += '\n' * carriedSeparators;
      }
    } else {
      // Mode W：偶数下标是段落组，奇数下标是组间的空白行分隔符。
      final pieces = <String>[];
      var cursor = 0;
      for (final match in _blankLinePattern.allMatches(text)) {
        pieces.add(text.substring(cursor, match.start));
        pieces.add(match[0]!);
        cursor = match.end;
      }
      pieces.add(text.substring(cursor));

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

  /// 行首/行尾空白剥除，含全角空格与零宽空格。
  static final _edgeWhitespacePattern = RegExp(r'^[\s　﻿]+|[\s　﻿]+$');

  /// 校验本章切片的首行是否就是服务端记录的章节标题。
  ///
  /// 返回 false 表示前后端解码出的字符域不一致（编码判定或坏序列策略分歧），
  /// 此时按偏移切出的内容会静默错位到别的章节。
  /// 单章"正文"（后端未识别出任何标题）与空切片不参与判定，避免误报。
  static bool sliceStartsWithTitle(String rawSlice, String title) {
    final expected = title.trim();
    if (expected.isEmpty || expected == '正文') {
      return true;
    }
    final newline = rawSlice.indexOf('\n');
    final firstLine = (newline < 0 ? rawSlice : rawSlice.substring(0, newline))
        .replaceAll(_edgeWhitespacePattern, '');
    if (firstLine.isEmpty) {
      return false;
    }
    return firstLine == expected || firstLine.startsWith(expected);
  }

  /// 按服务端记录的字符偏移读取单章并转换为 XHTML。
  String chapterToXhtml(Uint8List bytes, int startOffset, int endOffset) {
    final text = decodeText(bytes);
    final safeStart = startOffset.clamp(0, text.length);
    final safeEnd = endOffset.clamp(safeStart, text.length);
    return textToXhtml(text.substring(safeStart, safeEnd));
  }

  /// 从文件名提取标题（去掉扩展名）
  String? _extractTitle(String? fileName) {
    if (fileName == null || fileName.isEmpty) return null;
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot <= 0) return fileName;
    return fileName.substring(0, lastDot);
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

  /// 按章节模式拆分文本，自动推断层级
  List<_RawChapter> _splitChapters(String text) {
    final matches = _splitPattern.allMatches(text).toList();
    if (matches.isEmpty) return const [];

    final chapters = <_RawChapter>[];
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
      final chunk = text.substring(start, end).trim();
      if (chunk.isEmpty) continue;

      final firstNewline = chunk.indexOf('\n');
      final title =
          firstNewline > 0 ? chunk.substring(0, firstNewline).trim() : null;
      final content =
          firstNewline > 0 ? chunk.substring(firstNewline + 1).trim() : chunk;

      // 根据标题模式推断层级
      final titleStr = title ?? '';
      final level = _inferLevel(titleStr);

      chapters.add(_RawChapter(title: title, content: content, level: level));
    }

    return chapters;
  }

  /// 根据标题文本推断层级
  int _inferLevel(String title) {
    // 卷/篇
    if (_volumePattern.hasMatch(title)) return 0;
    // 节
    if (_sectionPattern.hasMatch(title)) return 2;
    // 章/回
    if (_chapterPattern.hasMatch(title)) return 1;
    // 默认章级
    return 1;
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

  /// 判断本章应按"每行一段"分段。
  ///
  /// 判据：本章不用空行分段，且抽样内的非空行有足够比例以行首空白缩进。
  /// 段间既无空行也无缩进的硬换行文件会被判为 Mode W，这是文本本身缺少信息，
  /// 不做逐行启发式猜测。
  bool _isLinePerParagraph(String text) {
    if (_blankLinePattern.hasMatch(text)) {
      return false;
    }
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
      if (nonEmpty >= _modeSampleLines) {
        break;
      }
    }
    if (nonEmpty < _modeMinSampledLines) {
      return false;
    }
    return indented / nonEmpty >= _modeIndentedLineRatio;
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

/// 内部使用的原始章节数据
class _RawChapter {
  const _RawChapter({this.title, required this.content, this.level = 1});

  final String? title;
  final String content;
  final int level;
}
