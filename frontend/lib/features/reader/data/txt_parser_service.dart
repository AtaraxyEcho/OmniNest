import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kDebugMode, kIsWeb;
import 'package:gbk_codec/gbk_codec.dart';
import 'package:omninest/core/utils/yield_to_event_loop.dart';
import 'package:omninest/features/reader/domain/parsed_book.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

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
      final xhtmlContent = _textToXhtml(raw.content);
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
      final xhtmlContent = _textToXhtml(text);
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
    return _decodeText(bytes).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  /// 供 isolate 调用的纯函数解码入口。
  static String decodeTxtBytes(Uint8List bytes) {
    return TxtParserService().decodeText(bytes);
  }

  static const int _decodeIsolateThresholdBytes = 2 * 1024 * 1024;

  String? _decodedItemId;
  String? _decodedCacheText;

  /// 解码整本 TXT 并按条目缓存。
  ///
  /// 章节按字符偏移切自整本解码文本；大文件的 GBK 转码与全文换行
  /// 规范化在 isolate 中执行并只做一次，避免每次切章卡顿 UI 线程。
  /// Web 无 isolate：解码前后让出事件循环，换行规范化按块分片。
  Future<String> ensureDecodedText({
    required String itemId,
    required Uint8List bytes,
  }) async {
    if (_decodedItemId == itemId && _decodedCacheText != null) {
      return _decodedCacheText!;
    }
    final String text;
    if (kIsWeb) {
      await yieldToEventLoop();
      text = await _decodeTextYielding(bytes);
      await yieldToEventLoop();
    } else if (bytes.length < _decodeIsolateThresholdBytes) {
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
      return decoded.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    }
    final buffer = StringBuffer();
    const chunk = 512 * 1024;
    for (var offset = 0; offset < decoded.length; offset += chunk) {
      final end =
          (offset + chunk < decoded.length) ? offset + chunk : decoded.length;
      buffer.write(
        decoded
            .substring(offset, end)
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n'),
      );
      if (end < decoded.length) {
        await yieldToEventLoop();
      }
    }
    return buffer.toString();
  }

  /// 从已解码文本中按字符偏移取单章并转换为 XHTML。
  String chapterFromText(String text, int startOffset, int endOffset) {
    final safeStart = startOffset.clamp(0, text.length);
    final safeEnd = endOffset.clamp(safeStart, text.length);
    return _textToXhtml(text.substring(safeStart, safeEnd));
  }

  /// 按服务端记录的字符偏移读取单章并转换为 XHTML。
  String chapterToXhtml(Uint8List bytes, int startOffset, int endOffset) {
    final text = decodeText(bytes);
    final safeStart = startOffset.clamp(0, text.length);
    final safeEnd = endOffset.clamp(safeStart, text.length);
    return _textToXhtml(text.substring(safeStart, safeEnd));
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
  /// 检测顺序：UTF-8 BOM → UTF-8 → GBK → Latin-1。
  String _decodeText(Uint8List bytes) {
    // UTF-8 BOM
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }

    // 尝试 UTF-8（严格模式）
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (error) {
      if (kDebugMode) {
        readerDebugLog('TxtParser: UTF-8 decode failed, trying GBK: $error');
      }
    }

    // 尝试 GBK（中文常见编码）
    try {
      return gbk.decode(bytes);
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

  /// 将纯文本转换为 XHTML 片段
  ///
  /// 段落以双换行分隔，包裹在 <p> 标签中。
  String _textToXhtml(String text) {
    final paragraphs = text.split(RegExp(r'\n\s*\n'));
    final buffer = StringBuffer();
    for (final para in paragraphs) {
      final trimmed = para.trim();
      if (trimmed.isEmpty) continue;
      // 转义 XML 特殊字符
      final escaped = _escapeXml(trimmed);
      buffer.writeln('<p>$escaped</p>');
    }
    return buffer.toString();
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
