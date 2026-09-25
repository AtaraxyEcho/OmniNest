import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:omninest/core/utils/yield_to_event_loop.dart';
import 'package:omninest/features/reader/data/reader_image_cache.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// XHTML 内容预处理器。
///
/// 提取正文并把章节图片写入缓存，HTML 始终使用轻量占位符引用图片。
class ReaderContentPreprocessor {
  /// 占位符前缀，用于标识需要替换的图片引用。
  static const _imgPlaceholderPrefix = '__IMG_';
  static const _imgPlaceholderSuffix = '__';
  static const _maxChapterImages = 100;
  static const _maxImageBytes = 20 * 1024 * 1024;
  static const _maxChapterImageBytes = 64 * 1024 * 1024;

  /// 提取 `<body>` 内容，将图片保存到磁盘缓存，
  /// HTML 中用占位符替代 base64 data URI。
  /// 返回的 HTML 可安全存入 SQLite（体积小）。
  static Future<String> preprocessForStorage({
    required String itemId,
    required String xhtml,
    Archive? archive,
    Uint8List? archiveBytes,
    String? contentPath,
  }) async {
    if (xhtml.trim().isEmpty) return xhtml;

    var body = _extractBody(xhtml);

    if (contentPath != null) {
      if (archive != null) {
        body = await _extractImagesToDisk(body, itemId, archive, contentPath);
      } else if (archiveBytes != null) {
        try {
          // 整包解压可能处理数十 MB 归档，原生平台放到 isolate 执行；
          // Web 上 compute 退化为同步执行，解码前后让出事件循环。
          final Archive decoded;
          if (kIsWeb) {
            await yieldToEventLoop();
            decoded = ZipDecoder().decodeBytes(archiveBytes);
            await yieldToEventLoop();
          } else {
            decoded = await compute(_decodeArchiveJob, archiveBytes);
          }
          body = await _extractImagesToDisk(body, itemId, decoded, contentPath);
        } on FormatException {
          rethrow;
        } catch (e) {
          if (kDebugMode) {
            readerDebugLog('Preprocessor: ZIP decode failed: $e');
          }
        }
      }
    }

    if (kDebugMode) {
      readerDebugLog(
        'Preprocessor: preprocessForStorage done, '
        '${body.length} chars',
      );
    }
    return body;
  }

  /// 提取图片到磁盘，HTML 中用占位符替代。
  ///
  /// 图片按顺序解压并写入磁盘，避免同一章节的图片同时驻留内存。
  static Future<String> _extractImagesToDisk(
    String html,
    String itemId,
    Archive archive,
    String contentPath,
  ) async {
    final chapterDir = _parentDir(contentPath);
    final storedPaths = <String>{};
    var resolvedCount = 0;
    var expandedBytes = 0;

    final result = await _replaceAsync(
      html,
      RegExp(r'<img\s[^>]*src=["\x27]([^"\x27]+)["\x27]', caseSensitive: false),
      (match) async {
        final originalSrc = match.group(1) ?? '';
        if (originalSrc.startsWith('data:')) {
          final inlineImage = await _decodeInlineImage(originalSrc);
          if (inlineImage == null) {
            return match.group(0)!;
          }
          final placeholder =
              '$_imgPlaceholderPrefix${inlineImage.path}$_imgPlaceholderSuffix';
          if (storedPaths.contains(inlineImage.path)) {
            return _replaceImageSource(match, placeholder);
          }
          _validateImageLimit(
            storedCount: storedPaths.length,
            expandedBytes: expandedBytes,
            imageBytes: inlineImage.bytes.length,
            imagePath: inlineImage.path,
          );
          await ReaderImageCache.saveImage(
            itemId: itemId,
            imagePath: inlineImage.path,
            bytes: inlineImage.bytes,
          );
          expandedBytes += inlineImage.bytes.length;
          storedPaths.add(inlineImage.path);
          resolvedCount++;
          return _replaceImageSource(match, placeholder);
        }
        if (originalSrc.startsWith('http://') ||
            originalSrc.startsWith('https://')) {
          return match.group(0)!;
        }

        final resolvedPath = _resolvePath(chapterDir, originalSrc);
        final placeholder =
            '$_imgPlaceholderPrefix$resolvedPath$_imgPlaceholderSuffix';
        if (storedPaths.contains(resolvedPath)) {
          return _replaceImageSource(match, placeholder);
        }

        final imageEntry = _findFileInArchive(archive, resolvedPath);
        if (imageEntry == null) {
          if (kDebugMode) {
            readerDebugLog('Preprocessor: image not found: $resolvedPath');
          }
          return match.group(0)!;
        }
        _validateImageLimit(
          storedCount: storedPaths.length,
          expandedBytes: expandedBytes,
          imageBytes: imageEntry.size,
          imagePath: resolvedPath,
        );

        final imageBytes = _entryBytes(imageEntry, maxBytes: _maxImageBytes);
        _validateImageLimit(
          storedCount: storedPaths.length,
          expandedBytes: expandedBytes,
          imageBytes: imageBytes.length,
          imagePath: resolvedPath,
        );
        expandedBytes += imageBytes.length;
        await ReaderImageCache.saveImage(
          itemId: itemId,
          imagePath: resolvedPath,
          bytes: imageBytes,
        );
        storedPaths.add(resolvedPath);
        resolvedCount++;

        return _replaceImageSource(match, placeholder);
      },
    );

    if (kDebugMode) {
      readerDebugLog('Preprocessor: extracted $resolvedCount images to disk');
    }
    return result;
  }

  static void _validateImageLimit({
    required int storedCount,
    required int expandedBytes,
    required int imageBytes,
    required String imagePath,
  }) {
    if (storedCount >= _maxChapterImages) {
      throw const FormatException('章节图片数量超过 100 张');
    }
    if (imageBytes < 0 || imageBytes > _maxImageBytes) {
      throw FormatException('章节图片超过 20 MiB: $imagePath');
    }
    if (expandedBytes > _maxChapterImageBytes - imageBytes) {
      throw const FormatException('章节图片总容量超过 64 MiB');
    }
  }

  static String _replaceImageSource(Match match, String replacement) {
    return match
        .group(0)!
        .replaceFirst(
          RegExp(r'src=["\x27][^"\x27]*["\x27]'),
          'src="$replacement"',
        );
  }

  static Future<_InlineImage?> _decodeInlineImage(String source) async {
    final commaIndex = source.indexOf(',');
    if (commaIndex <= 5 ||
        !source.substring(0, commaIndex).contains(';base64')) {
      return null;
    }
    final encoded = source.substring(commaIndex + 1);
    if (encoded.length > ((_maxImageBytes + 2) ~/ 3) * 4) {
      throw const FormatException('章节内嵌图片超过 20 MiB');
    }
    // 最大 20 MiB 的 base64 解码在原生平台移入 isolate；Web 前后让出事件循环。
    final Uint8List bytes;
    if (kIsWeb) {
      await yieldToEventLoop();
      bytes = base64Decode(encoded);
      await yieldToEventLoop();
    } else if (encoded.length < 1024 * 1024) {
      bytes = base64Decode(encoded);
    } else {
      bytes = await compute(_base64DecodeJob, encoded);
    }
    final mimeType = source.substring(5, source.indexOf(';', 5)).toLowerCase();
    final extension = switch (mimeType) {
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'image/svg+xml' => 'svg',
      _ => 'jpg',
    };
    final path = 'inline/${source.hashCode.toUnsigned(32)}.$extension';
    return _InlineImage(path: path, bytes: bytes);
  }

  /// 异步替换正则匹配项。
  static Future<String> _replaceAsync(
    String input,
    Pattern pattern,
    Future<String> Function(Match) replacer,
  ) async {
    final buffer = StringBuffer();
    var lastEnd = 0;
    for (final match in pattern.allMatches(input)) {
      buffer.write(input.substring(lastEnd, match.start));
      buffer.write(await replacer(match));
      lastEnd = match.end;
    }
    buffer.write(input.substring(lastEnd));
    return buffer.toString();
  }

  /// 提取 `<body>` 内容。
  static String _extractBody(String xhtml) {
    final bodyMatch = RegExp(
      r'<body[^>]*>([\s\S]*?)</body>',
      caseSensitive: false,
    ).firstMatch(xhtml);
    return bodyMatch?.group(1) ?? xhtml;
  }

  /// 获取路径的父目录。
  static String _parentDir(String path) {
    final lastSlash = path.lastIndexOf('/');
    return lastSlash >= 0 ? path.substring(0, lastSlash + 1) : '';
  }

  /// 解析相对路径。
  ///
  /// EPUB 规范允许 src 携带百分号编码（空格、非 ASCII 字符），而归档
  /// 条目名通常为解码形式；先解码再拼接，否则归档内定位失败导致图片
  /// 破图并被写入章节缓存。
  static String _resolvePath(String base, String relative) {
    var decoded = relative;
    if (decoded.contains('%')) {
      try {
        decoded = Uri.decodeComponent(decoded);
      } on FormatException {
        // 非法百分号序列保持原文
      }
    }
    if (decoded.startsWith('/')) return decoded.substring(1);
    final parts = (base + decoded).split('/');
    final resolved = <String>[];
    for (final part in parts) {
      if (part == '..') {
        if (resolved.isNotEmpty) resolved.removeLast();
      } else if (part.isNotEmpty && part != '.') {
        resolved.add(part);
      }
    }
    return resolved.join('/');
  }

  /// 从归档中查找文件。
  static ArchiveFile? _findFileInArchive(Archive archive, String path) {
    var entry = archive.findFile(path);
    if (entry != null) return entry;
    if (path.startsWith('/')) {
      entry = archive.findFile(path.substring(1));
      if (entry != null) return entry;
    }
    entry = archive.findFile(path.toLowerCase());
    if (entry != null) return entry;
    for (final file in archive.files) {
      final name = file.name.toLowerCase();
      final target = path.toLowerCase();
      if (name.endsWith(target) || target.endsWith(name)) {
        return file;
      }
    }
    return null;
  }

  /// 安全读取归档条目字节。
  static Uint8List _entryBytes(ArchiveFile entry, {required int maxBytes}) {
    if (entry.size < 0 || entry.size > maxBytes) {
      throw FormatException('归档图片超过容量上限: ${entry.name}');
    }
    try {
      final content = entry.content;
      if (content.length > maxBytes) {
        throw FormatException('归档图片解压后超过容量上限: ${entry.name}');
      }
      return content;
    } finally {
      entry.clear();
    }
  }
}

class _InlineImage {
  const _InlineImage({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;
}

/// isolate 中解压归档的纯函数入口。
Archive _decodeArchiveJob(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

/// isolate 中解码 base64 的纯函数入口。
Uint8List _base64DecodeJob(String encoded) => base64Decode(encoded);
