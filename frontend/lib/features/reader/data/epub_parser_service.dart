import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';
import 'package:omninest/core/utils/lenient_uri_decode.dart';
import 'package:omninest/features/reader/data/epub_archive_loader.dart';
import 'package:omninest/features/reader/data/epub_archive_source.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';
import 'package:xml/xml.dart';

/// 按条目声明解码 EPUB 内部文本。
///
/// 中文圈常见旧制 EPUB 的内部 XHTML/OPF 为 GBK 编码；严格 utf8 解码会
/// 抛异常导致章节静默空白。优先读取 XML 声明的 encoding，声明为 GBK
/// 系列时用 GBK 解码，其余按宽松 utf8 处理避免坏字节毁掉整章。
String decodeEpubText(List<int> bytes) {
  final declared = _declaredEncoding(bytes);
  if (declared != null && _isGbkFamily(declared)) {
    // `gbk` 的映射表以双字节 GBK 码元为键，逐字节查表永不命中（等价 Latin-1）；
    // 必须使用按双字节组合查表的 `gbk_bytes`。
    return gbk_bytes.decode(bytes);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String? _declaredEncoding(List<int> bytes) {
  final head = utf8.decode(bytes.take(200).toList(), allowMalformed: true);
  final match = RegExp(
    r'''encoding\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(head);
  return match?.group(1)?.trim();
}

bool _isGbkFamily(String name) {
  final normalized = name.replaceAll('-', '').toLowerCase();
  return normalized == 'gbk' ||
      normalized == 'gb2312' ||
      normalized == 'gb18030';
}

/// EPUB 归档超过安全解析边界。
class EpubParseLimitException implements Exception {
  const EpubParseLimitException(this.message);

  final String message;

  @override
  String toString() => 'EpubParseLimitException: $message';
}

/// EPUB 文件解析服务
///
/// 从 EPUB ZIP 归档中提取元数据、封面和章节内容。
/// 使用 archive + xml 包，不依赖 epubx（避免 image 版本冲突）。
class EpubParserService {
  static const _maxArchiveEntries = 10000;
  static const _maxExpandedBytes = FileSizeThresholds.epubMaxExpandedBytes;
  static const _maxExpansionRatio = 250;
  static const _ratioCheckThresholdBytes =
      FileSizeThresholds.epubRatioCheckThresholdBytes;
  static const _maxTextEntryBytes = FileSizeThresholds.epubMaxTextEntryBytes;

  /// 缓存已解压的 Archive，避免重复解压整个 ZIP 归档。
  Archive? _cachedArchive;
  int? _cachedArchiveHash;
  int? _cachedArchiveLength;
  String? _cachedArchivePath;
  EpubArchiveSource? _fileSource;

  /// 当前归档实例已保留的解压字节数，超过阈值即释放整个归档。
  int _retainedEntryBytes = 0;

  /// 当前持有租约的数量。归档被持有时不得释放或重开。
  int _leaseHolders = 0;

  /// 等待中的租约请求（FIFO）。
  final List<void Function()> _leaseWaiters = [];

  /// 持有期间收到释放请求时记下来，等最后一个租约归还后再执行。
  bool _releaseRequested = false;

  /// 获取缓存的 Archive，未命中时解压并缓存。
  ///
  /// 使用长度 + 内容哈希判断缓存命中，避免 Uint8List 引用比较问题。
  /// 旧实现在每个公共入口先 `releaseArchive()`，使这里的命中分支永远走不到，
  /// 每次切章都重新解析 central directory 与全部本地头；现在缓存真的会被复用。
  Archive? _getCachedArchive(Uint8List archiveBytes) {
    final hash = _computeHash(archiveBytes);
    if (_cachedArchive != null &&
        _cachedArchiveLength == archiveBytes.length &&
        _cachedArchiveHash == hash) {
      return _cachedArchive;
    }
    releaseArchive();
    final archive = ZipDecoder().decodeBytes(archiveBytes);
    _validateArchive(archive, archiveBytes.length);
    _cachedArchive = archive;
    _cachedArchiveHash = hash;
    _cachedArchiveLength = archiveBytes.length;
    return _cachedArchive;
  }

  /// 获取文件流归档缓存，未命中时打开并缓存。
  ///
  /// 调用方必须持有租约：换路径意味着关闭上一个 `InputFileStream`，
  /// 而它可能正被另一个章节的预处理读取。
  Archive? _getCachedFileArchive(String path) {
    if (_cachedArchive != null && _cachedArchivePath == path) {
      return _cachedArchive;
    }
    releaseArchive();
    final source = openEpubArchiveFile(path);
    try {
      _validateArchive(source.archive, source.compressedBytes);
      _fileSource = source;
      _cachedArchive = source.archive;
      _cachedArchivePath = path;
      return _cachedArchive;
    } catch (_) {
      source.close();
      rethrow;
    }
  }

  /// 取得一次归档使用租约。
  ///
  /// 归档内部是同一个文件句柄上的 `FileBuffer`，两个章节并发读取会互相打乱读取位置；
  /// 而"解析＋图片预处理"整段跨多次 await，只有在整段期间持有租约，
  /// 邻章预取才不能中途关闭当前章正在使用的流。
  /// 租约互斥：同一时刻只有一个持有者，预取因此排在当前章之后。
  Future<EpubArchiveLease> acquireLease() {
    if (_leaseHolders == 0) {
      _leaseHolders = 1;
      return Future<EpubArchiveLease>.value(EpubArchiveLease(this));
    }
    final completer = Completer<EpubArchiveLease>();
    _leaseWaiters.add(() {
      _leaseHolders += 1;
      completer.complete(EpubArchiveLease(this));
    });
    return completer.future;
  }

  void _releaseLease() {
    if (_leaseHolders == 0) {
      return;
    }
    _leaseHolders -= 1;
    if (_leaseWaiters.isNotEmpty) {
      _leaseWaiters.removeAt(0)();
      return;
    }
    if (_releaseRequested) {
      _releaseRequested = false;
      _doReleaseArchive();
    }
  }

  /// 释放正在使用的 Archive：调用方必须已归还全部租约，
  /// 否则本次释放被推迟到最后一个租约归还时执行。
  void releaseArchive() {
    if (_leaseHolders > 0 || _leaseWaiters.isNotEmpty) {
      _releaseRequested = true;
      return;
    }
    _doReleaseArchive();
  }

  void _doReleaseArchive() {
    _fileSource?.close();
    _fileSource = null;
    _cachedArchive = null;
    _cachedArchiveHash = null;
    _cachedArchiveLength = null;
    _cachedArchivePath = null;
    _retainedEntryBytes = 0;
  }

  /// 获取当前缓存的 Archive（仅供持有租约期间读取）。
  Archive? get cachedArchive => _cachedArchive;

  /// 计算字节数组的快速哈希（采样 + 长度）。
  int _computeHash(Uint8List bytes) {
    // 采样首尾各 100 字节 + 长度，平衡速度和碰撞率
    var hash = bytes.length;
    final sampleSize = bytes.length < 200 ? bytes.length : 100;
    for (var i = 0; i < sampleSize; i++) {
      hash = hash * 31 + bytes[i];
    }
    for (var i = bytes.length - sampleSize; i < bytes.length; i++) {
      hash = hash * 31 + bytes[i];
    }
    return hash;
  }

  /// 解析 EPUB 元数据和章节目录

  /// 从原生文件流解析 EPUB 元数据和章节目录。

  /// 判断 EPUB 是否为固定版式（漫画/图片型 EPUB）。
  ///
  /// 检查 OPF 中的 `rendition:layout` 属性。
  /// 返回 `true` 表示 pre-paginated（固定版式），应按漫画方式解析。

  /// 从原生文件流判断 EPUB 是否为固定版式。

  /// 按需解析单个章节的 XHTML 内容。
  ///
  /// 调用方必须持有 [acquireLease] 取得的租约，直到本章的图片预处理完成：
  /// 本方法只在归档上读取，不再自行释放归档——旧实现在入口 `releaseArchive()`
  /// 会让邻章预取关掉当前章仍在使用的文件流，并把解压缓存彻底作废。
  Future<String?> parseChapter(Uint8List archiveBytes, String contentPath) {
    assert(_leaseHolders > 0, 'parseChapter 必须在持有归档租约时调用');
    return _parseChapterArchive(
      () => _getCachedArchive(archiveBytes),
      contentPath,
    );
  }

  /// 从原生文件流按需解析单个章节。同样要求调用方持有租约。
  Future<String?> parseChapterFile(String path, String contentPath) {
    assert(_leaseHolders > 0, 'parseChapterFile 必须在持有归档租约时调用');
    return _parseChapterArchive(() => _getCachedFileArchive(path), contentPath);
  }

  Future<String?> _parseChapterArchive(
    Archive? Function() loadArchive,
    String contentPath,
  ) async {
    try {
      final archive = loadArchive();
      if (archive == null) return null;

      final containerEntry = _findEntry(archive, 'META-INF/container.xml');
      if (containerEntry == null) return null;
      final opfPath = _parseContainerXml(_entryBytes(containerEntry));
      if (opfPath == null) return null;

      final directPath = _normalizeArchivePath(
        lenientDecodeComponent(contentPath),
      );
      final fullPath = _resolvePath(opfPath, contentPath);
      final fileEntry =
          _findExactEntry(archive, fullPath) ??
          _findExactEntry(archive, directPath) ??
          _findEntry(archive, fullPath);
      if (fileEntry == null) {
        if (kDebugMode) {
          readerDebugLog('EPUB: chapter file not found: $fullPath');
        }
        return null;
      }

      return decodeEpubText(_entryBytes(fileEntry));
    } on EpubParseLimitException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('EPUB: parseChapter failed for $contentPath: $e');
      }
      return null;
    }
  }

  // ── Private helpers ──────────────────────────────────────────

  /// 在归档中查找文件（忽略大小写和前导斜杠）
  ArchiveFile? _findEntry(Archive archive, String path) {
    // 直接匹配
    var entry = archive.findFile(path);
    if (entry != null) return entry;

    // 去掉前导斜杠
    if (path.startsWith('/')) {
      entry = archive.findFile(path.substring(1));
      if (entry != null) return entry;
    }

    // 尝试小写路径
    entry = archive.findFile(path.toLowerCase());
    if (entry != null) return entry;

    // 遍历所有条目做模糊匹配
    for (final file in archive.files) {
      if (file.name.toLowerCase().endsWith(path.toLowerCase()) ||
          path.toLowerCase().endsWith(file.name.toLowerCase())) {
        return file;
      }
    }
    return null;
  }

  ArchiveFile? _findExactEntry(Archive archive, String path) {
    final normalizedPath = _normalizeArchivePath(path).toLowerCase();
    for (final file in archive.files) {
      if (_normalizeArchivePath(file.name).toLowerCase() == normalizedPath) {
        return file;
      }
    }
    return _findExactEntryByRecoveredName(archive, normalizedPath);
  }

  /// 旧中文工具打包的 ZIP 条目名常用 GBK 字节，而 archive 4.x 对非 UTF-8 条目名
  /// 逐字节回退成 Latin-1（字节保留、字形错乱），与已按 GBK 正确解码的 OPF href
  /// 对不上，章节因此静默变 null。把乱码名还原成字节再按 GBK 重解一次参与比较。
  ArchiveFile? _findExactEntryByRecoveredName(
    Archive archive,
    String normalizedPath,
  ) {
    for (final file in archive.files) {
      final recovered = _recoverGbkName(file.name);
      if (recovered == null) {
        continue;
      }
      try {
        if (_normalizeArchivePath(recovered).toLowerCase() == normalizedPath) {
          return file;
        }
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  /// 名字全在 Latin-1 范围内时才值得尝试重解（archive 的逐字节回退即此形态）。
  String? _recoverGbkName(String name) {
    var hasNonAscii = false;
    for (final unit in name.codeUnits) {
      if (unit > 0xFF) {
        return null;
      }
      if (unit > 0x7F) {
        hasNonAscii = true;
      }
    }
    if (!hasNonAscii) {
      return null;
    }
    try {
      final recovered = gbk_bytes.decode(latin1.encode(name));
      return recovered == name ? null : recovered;
    } on FormatException {
      return null;
    }
  }

  /// 校验归档目录和展开容量边界。
  void _validateArchive(Archive archive, int compressedBytes) {
    if (archive.files.length > _maxArchiveEntries) {
      throw const EpubParseLimitException('EPUB 归档条目数量超过 10000');
    }
    var expandedBytes = 0;
    for (final file in archive.files) {
      if (file.isSymbolicLink) {
        throw EpubParseLimitException('EPUB 不允许符号链接条目: ${file.name}');
      }
      final normalized = file.name.replaceAll('\\', '/');
      final segments = normalized.split('/');
      if (normalized.startsWith('/') || segments.contains('..')) {
        throw EpubParseLimitException('EPUB 条目路径不安全: ${file.name}');
      }
      if (file.size < 0 || expandedBytes > _maxExpandedBytes - file.size) {
        throw const EpubParseLimitException('EPUB 总展开体积超过 1 GiB');
      }
      expandedBytes += file.size;
    }
    if (expandedBytes > _ratioCheckThresholdBytes &&
        compressedBytes > 0 &&
        expandedBytes > compressedBytes * _maxExpansionRatio) {
      throw const EpubParseLimitException('EPUB 压缩比超过安全上限');
    }
  }

  /// 安全读取归档条目字节。
  ///
  /// 不 `clear()` 条目：archive 4.x 的 `ArchiveFile.clear()` 会把内容来源一并丢弃，
  /// 之后同一条目再读只得到 0 字节，而 `size` 仍报原值绕过大小校验（D-35）。
  /// 解压结果随归档实例保留，累计超过阈值时释放整个归档（有租约则延后到归还）。
  Uint8List _entryBytes(
    ArchiveFile entry, {
    int maxBytes = _maxTextEntryBytes,
  }) {
    if (entry.size < 0 || entry.size > maxBytes) {
      throw EpubParseLimitException('归档条目超过解析上限: ${entry.name}');
    }
    final content = entry.content;
    if (content.length > maxBytes) {
      throw EpubParseLimitException('归档条目解压后超过解析上限: ${entry.name}');
    }
    _retainedEntryBytes += content.length;
    if (_retainedEntryBytes > FileSizeThresholds.epubRetainedEntryBytes) {
      releaseArchive();
    }
    return content;
  }

  /// 解析 container.xml 获取 OPF 路径
  String? _parseContainerXml(Uint8List bytes) {
    try {
      final doc = XmlDocument.parse(decodeEpubText(bytes));
      final rootfile = doc.findAllElements('rootfile').firstOrNull;
      return rootfile?.getAttribute('full-path');
    } on EpubParseLimitException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('EPUB: container.xml parse failed: $e');
      }
      return null;
    }
  }

  /// 从 OPF 中提取 Dublin Core 元素

  /// 从 OPF 中提取封面图片

  /// 构建 manifest 映射 (id → href)

  /// 从 OPF spine 构建章节 href 列表

  // ── TOC 层级解析 ──

  /// 解析 TOC 文件获取章节层级映射。
  ///
  /// 返回 Map<相对href, level>，level 从 0 开始。
  /// 优先解析 EPUB3 nav.xhtml，回退到 EPUB2 toc.ncx。

  /// 解析 EPUB3 nav.xhtml（<nav epub:type="toc">）

  /// 递归遍历 nav.xhtml 的 <ol> 结构

  /// 解析 EPUB2 toc.ncx（`<navMap>`/`<navPoint>`）

  /// 递归遍历 toc.ncx 的 `<navPoint>` 结构

  /// 根据 href 查找 TOC 中的层级，回退到 0
  ///
  /// tocLevels 的 key 已经是完整路径（相对于 EPUB 根目录），
  /// spine href 需要解析为完整路径后比较。

  /// 从 HTML 中提取标题（第一个 h1-h6）

  /// 解析相对路径
  String _resolvePath(String basePath, String relativePath) {
    final decoded = lenientDecodeComponent(relativePath);
    if (decoded.startsWith('/')) {
      return _normalizeArchivePath(decoded);
    }
    final normalizedBase = _normalizeArchivePath(basePath);
    final lastSlash = normalizedBase.lastIndexOf('/');
    final baseDirectory =
        lastSlash < 0 ? '' : normalizedBase.substring(0, lastSlash + 1);
    return _normalizeArchivePath('$baseDirectory$decoded');
  }

  String _normalizeArchivePath(String path) {
    final pathWithoutFragment = path
        .split('#')
        .first
        .split('?')
        .first
        .replaceAll('\\', '/');
    final resolved = <String>[];
    for (final part in pathWithoutFragment.split('/')) {
      if (part.isEmpty || part == '.') {
        continue;
      }
      if (part == '..') {
        if (resolved.isEmpty) {
          throw const FormatException('EPUB 归档路径越界');
        }
        resolved.removeLast();
        continue;
      }
      resolved.add(part);
    }
    return resolved.join('/');
  }

  /// 去除 HTML 标签，提取纯文本
}

/// 归档使用租约。归还前，归档不会被释放、重开或换路径。
///
/// 由 [EpubParserService.acquireLease] 取得，必须在 `finally` 中 [release]；
/// 重复归还是无害的。
class EpubArchiveLease {
  EpubArchiveLease(this._service);

  final EpubParserService _service;

  bool _released = false;

  /// 归还租约。
  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _service._releaseLease();
  }
}
