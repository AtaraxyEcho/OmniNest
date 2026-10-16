import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:omninest/core/utils/yield_to_event_loop.dart';
import 'package:omninest/features/reader/data/reader_image_cache.dart';
import 'package:omninest/features/reader/domain/reader_html_scan.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';
import 'package:omninest/core/utils/lenient_uri_decode.dart';

/// XHTML 内容预处理器。
///
/// 提取正文并把章节图片写入缓存，HTML 始终使用轻量占位符引用图片。
class ReaderContentPreprocessor {
  /// 占位符前缀，用于标识需要替换的图片引用。
  static const _imgPlaceholderPrefix = '__IMG_';
  static const _imgPlaceholderSuffix = '__';
  static const _maxChapterImages = 100;

  static const _maxImageBytes = FileSizeThresholds.readerInlineImageMaxBytes;
  static const _maxChapterImageBytes =
      FileSizeThresholds.readerChapterImageMaxBytes;

  /// 提取 `<body>` 内容，将图片保存到磁盘缓存，
  /// HTML 中用占位符替代 base64 data URI。
  /// 返回的 HTML 可安全存入 SQLite（体积小）。
  ///
  /// `droppedImageCount` 是本章因超出数量或容量上限而未落盘的图片数：
  /// 渲染端每张降级图只有自己占位错误，读者看不出"少了 N 张"，需要这个总数做集中提示。
  static Future<ReaderPreprocessedContent> preprocessForStorage({
    required String itemId,
    required String xhtml,
    Archive? archive,
    Uint8List? archiveBytes,
    String? contentPath,
    EpubEntryBytesReader? readEntryBytes,
  }) async {
    if (xhtml.trim().isEmpty) {
      return ReaderPreprocessedContent(html: xhtml, droppedImageCount: 0);
    }

    var body = _extractBody(xhtml);
    var droppedImageCount = 0;

    if (contentPath != null) {
      if (archive != null) {
        // 图片提取失败不得让整章不可读：保留原始 src，渲染端会对无法加载的图片
        // 单独显示错误与重试，而不是把章节判死。
        final extracted = await _guardedExtract(
          body,
          () => _extractImagesToDisk(
            body,
            itemId,
            archive,
            contentPath,
            readEntryBytes: readEntryBytes,
          ),
        );
        body = extracted.html;
        droppedImageCount = extracted.droppedImageCount;
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
          final extracted = await _extractImagesToDisk(
            body,
            itemId,
            decoded,
            contentPath,
            readEntryBytes: readEntryBytes,
          );
          body = extracted.html;
          droppedImageCount = extracted.droppedImageCount;
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
    return ReaderPreprocessedContent(
      html: body,
      droppedImageCount: droppedImageCount,
    );
  }

  /// 图片提取的兜底：任何意外都退化为"不替换占位符"，章节正文仍然可读。
  ///
  /// 退化时返回的是未替换的原始正文，此前计数对应的占位符并不在其中，
  /// 因此降级计数必须归零，否则提示会报出读者看不到的缺图数。
  static Future<ReaderPreprocessedContent> _guardedExtract(
    String body,
    Future<ReaderPreprocessedContent> Function() extract,
  ) async {
    try {
      return await extract();
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('Preprocessor: image extraction degraded: $e');
      }
      return ReaderPreprocessedContent(html: body, droppedImageCount: 0);
    }
  }

  /// 提取图片到磁盘，HTML 中用占位符替代。
  ///
  /// 图片按顺序解压并写入磁盘，避免同一章节的图片同时驻留内存。
  /// 超出数量或容量上限的图片**降级**为"不加载"（HTML 保留占位符但不落盘），
  /// 渲染端会对该图单独显示错误与重试；旧实现直接抛异常让整章不可读且重试必败。
  ///
  /// `<img>` 用定界扫描逐个取出，只替换标签自己的 src 属性区间，alt/class 等其余
  /// 属性原样留在待入库的 HTML 里。属性解析天然区分 `data-src` 与 `src`；旧的
  /// `[^>]*?` 惰性量词要在主 isolate 上模拟逐字符扩展，畸形章节实测几十秒。
  static Future<ReaderPreprocessedContent> _extractImagesToDisk(
    String html,
    String itemId,
    Archive archive,
    String contentPath, {
    EpubEntryBytesReader? readEntryBytes,
  }) async {
    final chapterDir = _parentDir(contentPath);
    final storedPaths = <String>{};
    final handledEntries = <ArchiveFile>{};
    var resolvedCount = 0;
    var droppedCount = 0;
    var expandedBytes = 0;

    String placeholderOf(String path) =>
        '$_imgPlaceholderPrefix$path$_imgPlaceholderSuffix';

    /// 返回写回 src 属性的内容；null 表示保留书里原来的 src。
    Future<String?> resolveImage(HtmlAttribute src) async {
      final originalSrc = src.value;

      String drop(String path) {
        droppedCount++;
        storedPaths.add(path);
        return placeholderOf(path);
      }

      if (originalSrc.startsWith('data:')) {
        final inlineImage = await _decodeInlineImage(originalSrc);
        if (inlineImage == null) {
          return null;
        }
        if (storedPaths.contains(inlineImage.path)) {
          return placeholderOf(inlineImage.path);
        }
        if (inlineImage.tooLarge ||
            !_isImageWithinLimits(
              storedCount: storedPaths.length,
              expandedBytes: expandedBytes,
              imageBytes: inlineImage.bytes.length,
              imagePath: inlineImage.path,
            )) {
          return drop(inlineImage.path);
        }
        await ReaderImageCache.saveImage(
          itemId: itemId,
          imagePath: inlineImage.path,
          bytes: inlineImage.bytes,
          mimeType: inlineImage.mimeType,
        );
        expandedBytes += inlineImage.bytes.length;
        storedPaths.add(inlineImage.path);
        resolvedCount++;
        return placeholderOf(inlineImage.path);
      }
      if (originalSrc.startsWith('http://') ||
          originalSrc.startsWith('https://')) {
        return null;
      }

      final resolvedPath = _resolvePath(chapterDir, originalSrc);
      if (storedPaths.contains(resolvedPath)) {
        return placeholderOf(resolvedPath);
      }

      final imageEntry = _findFileInArchive(archive, resolvedPath);
      if (imageEntry == null) {
        if (kDebugMode) {
          readerDebugLog('Preprocessor: image not found: $resolvedPath');
        }
        return null;
      }
      // 同一归档条目可能被不同写法的 src 命中；按条目身份去重，
      // 避免对同一条目重复解压与重复计入容量。
      if (!handledEntries.add(imageEntry)) {
        storedPaths.add(resolvedPath);
        return placeholderOf(resolvedPath);
      }
      if (!_isImageWithinLimits(
        storedCount: storedPaths.length,
        expandedBytes: expandedBytes,
        imageBytes: imageEntry.size,
        imagePath: resolvedPath,
      )) {
        return drop(resolvedPath);
      }

      // 归档字节的读取一律走 `EpubParserService`：它把解压量记进归档预算，
      // 超阈值时释放整个归档。绕过它直接取 `entry.content` 会让多图章节的
      // 图片字节永久留在归档实例里。
      final imageBytes =
          readEntryBytes == null
              ? _entryBytes(imageEntry, maxBytes: _maxImageBytes)
              : readEntryBytes(imageEntry, maxBytes: _maxImageBytes);
      if (!_isImageWithinLimits(
        storedCount: storedPaths.length,
        expandedBytes: expandedBytes,
        imageBytes: imageBytes.length,
        imagePath: resolvedPath,
      )) {
        return drop(resolvedPath);
      }
      if (imageBytes.isEmpty) {
        // 0 字节不是"没有图片"就是条目已被丢弃，两者都不该静默入库。
        return drop(resolvedPath);
      }
      expandedBytes += imageBytes.length;
      await ReaderImageCache.saveImage(
        itemId: itemId,
        imagePath: resolvedPath,
        bytes: imageBytes,
        mimeType: _mimeTypeOfPath(resolvedPath),
      );
      storedPaths.add(resolvedPath);
      resolvedCount++;

      return placeholderOf(resolvedPath);
    }

    final buffer = StringBuffer();
    var cursor = 0;
    for (final tag in scanHtmlTags(html, const {'img'})) {
      final src = tag.attribute('src');
      if (src == null) {
        continue;
      }
      final replacement = await resolveImage(src);
      if (replacement == null) {
        continue;
      }
      buffer
        ..write(html.substring(cursor, src.start))
        ..write('src="$replacement"');
      cursor = src.end;
    }
    buffer.write(html.substring(cursor));
    final result = buffer.toString();

    if (kDebugMode) {
      readerDebugLog(
        'Preprocessor: extracted $resolvedCount images to disk'
        '${droppedCount > 0 ? ', dropped $droppedCount over limits' : ''}',
      );
    }
    return ReaderPreprocessedContent(
      html: result,
      droppedImageCount: droppedCount,
    );
  }

  /// 图片是否仍在单章数量、单图与单章总容量限制内。
  static bool _isImageWithinLimits({
    required int storedCount,
    required int expandedBytes,
    required int imageBytes,
    required String imagePath,
  }) {
    String? reason;
    if (storedCount >= _maxChapterImages) {
      reason = '单章图片数量超过 $_maxChapterImages 张';
    } else if (imageBytes < 0 || imageBytes > _maxImageBytes) {
      reason = '单图超过 $_maxImageBytes 字节';
    } else if (expandedBytes > _maxChapterImageBytes - imageBytes) {
      reason = '单章图片总容量超过 $_maxChapterImageBytes 字节';
    }
    if (reason == null) {
      return true;
    }
    if (kDebugMode) {
      // 降级必须可查：哪张图因何原因未被加载。
      readerDebugLog('Preprocessor: image skipped ($reason): $imagePath');
    }
    return false;
  }

  /// 归档内图片的 MIME：EPUB 只有文件名可用，按扩展名推断。
  ///
  /// 记错 MIME 会让缓存里所有图片都按默认档处理，导出与排障都失去依据。
  static String _mimeTypeOfPath(String path) {
    final lower = path.toLowerCase();
    final dot = lower.lastIndexOf('.');
    return switch (dot < 0 ? '' : lower.substring(dot + 1)) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' || 'svgz' => 'image/svg+xml',
      'avif' => 'image/avif',
      _ => 'image/jpeg',
    };
  }

  static Future<_InlineImage?> _decodeInlineImage(String source) async {
    final commaIndex = source.indexOf(',');
    if (commaIndex <= 5 ||
        !source.substring(0, commaIndex).contains(';base64')) {
      return null;
    }
    final mimeType = source.substring(5, source.indexOf(';', 5)).toLowerCase();
    final extension = switch (mimeType) {
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'image/svg+xml' => 'svg',
      _ => 'jpg',
    };
    final encoded = source.substring(commaIndex + 1);
    // 路径必须是内容的稳定摘要：`String.hashCode` 只有 32 位且跨进程不保证一致，
    // 预处理结果落进 SQLite 后重启就会指错图，同章两张内联图撞上同一哈希更是串图。
    final digest = crypto.sha256.convert(utf8.encode(encoded));
    final path = 'inline/${digest.toString().substring(0, 24)}.$extension';
    if (encoded.length > ((_maxImageBytes + 2) ~/ 3) * 4) {
      // 超大内嵌图不抛异常：调用方把它降级为"不加载"，正文仍然可读，
      // 且原始 data URI 不会留在待入库的 HTML 里。
      return _InlineImage(
        path: path,
        bytes: Uint8List(0),
        mimeType: mimeType,
        tooLarge: true,
      );
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
    return _InlineImage(path: path, bytes: bytes, mimeType: mimeType);
  }

  /// 提取 `<body>` 内容。
  ///
  /// 用两次定界扫描代替 `<body[^>]*>([\s\S]*?)</body>`：惰性量符要在主 isolate 上
  /// 模拟逐字符扩展，8 MiB 的单章 HTML 会白付一次回溯；找不到开/闭标签时与旧写法
  /// 一致地退回整串。
  static String _extractBody(String xhtml) {
    final openMatch = RegExp(
      r'<body[^>]*>',
      caseSensitive: false,
    ).firstMatch(xhtml);
    if (openMatch == null) {
      return xhtml;
    }
    for (final closeMatch in RegExp(
      r'</body\s*>',
      caseSensitive: false,
    ).allMatches(xhtml, openMatch.end)) {
      return xhtml.substring(openMatch.end, closeMatch.start);
    }
    return xhtml;
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
    final decoded = lenientDecodeComponent(relative);
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
    // 段边界锚定的兜底：允许条目少一层容器前缀或多一层根目录，但不允许任意尾部相同
    // 的条目抢走路径（`pter1.xhtml` 顶替 `OEBPS/text/chapter1.xhtml` 那类错配）。
    final target = path.toLowerCase();
    for (final file in archive.files) {
      final name = file.name.toLowerCase();
      if (name.isEmpty || target.isEmpty) continue;
      if (name == target ||
          name.endsWith('/$target') ||
          target.endsWith('/$name')) {
        return file;
      }
    }
    return null;
  }

  /// 安全读取归档条目字节。
  ///
  /// 不 `clear()` 条目：archive 4.x 的 `clear()` 会丢弃内容来源，之后同一条目
  /// 再读只得到 0 字节而 `size` 仍是原值，会让大小校验放行一张破图（D-35）。
  /// 解压字节随归档实例保留，由 `EpubParserService` 的保留量上限统一回收。
  static Uint8List _entryBytes(ArchiveFile entry, {required int maxBytes}) {
    if (entry.size < 0 || entry.size > maxBytes) {
      throw FormatException('归档图片超过容量上限: ${entry.name}');
    }
    final content = entry.content;
    if (content.length > maxBytes) {
      throw FormatException('归档图片解压后超过容量上限: ${entry.name}');
    }
    return content;
  }
}

/// 预处理结果：可入库的正文与本章未落盘的图片数。
class ReaderPreprocessedContent {
  const ReaderPreprocessedContent({
    required this.html,
    required this.droppedImageCount,
  });

  final String html;
  final int droppedImageCount;
}

class _InlineImage {
  const _InlineImage({
    required this.path,
    required this.bytes,
    required this.mimeType,
    this.tooLarge = false,
  });

  final String path;
  final Uint8List bytes;

  /// data URI 自己声明的类型：入库时必须原样带上，否则所有图片都被记成默认档。
  final String mimeType;

  /// 超过单图容量上限：不解码、不落盘，由调用方降级为不加载。
  final bool tooLarge;
}

/// 归档条目字段的读取回调（由 `EpubParserService.readArchiveEntryBytes` 提供）。
typedef EpubEntryBytesReader =
    Uint8List Function(ArchiveFile entry, {required int maxBytes});

/// isolate 中解压归档的纯函数入口。
Archive _decodeArchiveJob(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

/// isolate 中解码 base64 的纯函数入口。
Uint8List _base64DecodeJob(String encoded) => base64Decode(encoded);
